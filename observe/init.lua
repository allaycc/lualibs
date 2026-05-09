-- observe: hook CC's fs API to track every filesystem mutation made by
-- code running in the observed env. Intended for wrapping arbitrary
-- installers and capturing what they wrote, so allay can manage their
-- output the same way it manages its own atomic installs.
--
-- Usage:
--
--   local observe = require("observe")
--   local session = observe.start()        -- hooks set up
--
--   -- Run the installer in an env where fs is the hooked table.
--   load(installer_src, "installer", "t", session.env)()
--
--   local manifest = session:finish()
--   -- manifest.writes  = { { path, mode, sha256, bytes } ... }
--   -- manifest.deletes = { path ... }
--   -- manifest.dirs    = { path ... }
--   -- manifest.moves   = { { from, to } ... }
--   -- manifest.copies  = { { from, to } ... }
--
-- The hooks pass through to the real fs by default — observe records
-- but does not intercept. Atomicity (staging writes to a temp area and
-- committing only on success) is a separate concern; this module just
-- watches.

local M = {}

M.VERSION = "1.0.0"

-- Try to load hash for SHA-256ing captured files. Fall back to nil so
-- callers can hash later if the lib isn't loadable.
local function try_load_hash()
  local ok, mod = pcall(require, "hash")
  if ok then return mod end
  return _G.hash
end

-- Read a file's content via the real fs (bypassing our hooks). Used to
-- compute SHA-256 after an installer closes a write handle.
local function read_file(real_fs, path)
  local f = real_fs.open(path, "rb")
  if not f then f = real_fs.open(path, "r") end
  if not f then return nil end
  local content = f.readAll()
  f.close()
  return content
end

-- Wrap an open() call. We need to track the path the installer wrote to.
-- We can't intercept .write() directly because handles are opaque tables
-- with closures; instead we record the path on open and re-read after
-- close to get the final content.
local function make_open(real_fs, session)
  return function(path, mode)
    local handle = real_fs.open(path, mode)
    if not handle then return nil end
    if mode and mode:find("[wa]") then
      table.insert(session.writes, { path = path, mode = mode })
    end
    return handle
  end
end

local function request_url(args)
  local first = args[1]
  if type(first) == "table" then
    return first.url or first[1] or "?"
  end
  return tostring(first or "?")
end

local function make_http_get(real_http, session)
  return function(...)
    local args = {...}
    local url = request_url(args)
    local response, err = real_http.get(...)
    if not response then
      table.insert(session.fetches, {
        url = url,
        ok = false,
        error = tostring(err or "http.get failed"),
      })
      return nil, err
    end

    local record = { url = url, ok = true }
    if response.getResponseCode then
      local ok, code = pcall(response.getResponseCode)
      if ok then record.status = code end
    end
    table.insert(session.fetches, record)

    local wrapped = setmetatable({}, { __index = response })
    wrapped.readAll = function()
      local body = response.readAll()
      record.body = body or ""
      record.bytes = #record.body
      return body
    end
    wrapped.close = function()
      if response.close then return response.close() end
    end
    return wrapped
  end
end

local function split_words(s)
  local out = {}
  for word in tostring(s or ""):gmatch("%S+") do
    table.insert(out, word)
  end
  return out
end

local function copy_args(args, start_at)
  local out = {}
  for i = start_at or 1, #args do table.insert(out, args[i]) end
  return out
end

local function make_package_proxy()
  local proxy = {}
  if type(_G.package) == "table" then
    for k, v in pairs(_G.package) do proxy[k] = v end
  end
  proxy.path = proxy.path or ""
  proxy.loaded = proxy.loaded or {}
  proxy.preload = proxy.preload or {}
  return proxy
end

function M.start(opts)
  opts = opts or {}
  local real_fs = opts.fs or _G.fs
  if not real_fs then
    error("observe: no fs available (pass opts.fs or run inside CC)")
  end

  local session = {
    real_fs = real_fs,
    writes  = {},
    deletes = {},
    dirs    = {},
    moves   = {},
    copies  = {},
    fetches = {},
    shell_runs = {},
  }

  local hooked = setmetatable({}, { __index = real_fs })

  hooked.open    = make_open(real_fs, session)
  hooked.delete  = function(path)
    table.insert(session.deletes, path)
    return real_fs.delete(path)
  end
  hooked.makeDir = function(path)
    table.insert(session.dirs, path)
    return real_fs.makeDir(path)
  end
  hooked.move    = function(from, to)
    table.insert(session.moves, { from = from, to = to })
    return real_fs.move(from, to)
  end
  hooked.copy    = function(from, to)
    table.insert(session.copies, { from = from, to = to })
    return real_fs.copy(from, to)
  end

  session.fs = hooked
  -- Convenience: an env table the caller can hand to load(...). Helper files
  -- loaded by the installer should inherit the same observed fs table, so we
  -- provide env-local loadfile/dofile shims instead of falling back to _G.
  local env
  local function observed_loadfile(path, mode, load_env)
    local f = real_fs.open(path, "r")
    if not f then f = real_fs.open(path, "rb") end
    if not f then return nil, "cannot open " .. tostring(path) end
    local source = f.readAll()
    f.close()
    return load(source, "@" .. tostring(path), mode or "t", load_env or env)
  end

  local function observed_dofile(path)
    local fn, err = observed_loadfile(path, "t", env)
    if not fn then error(err, 2) end
    return fn()
  end

  local current_program = opts.running_program
  local unpack_fn = table.unpack or unpack

  local function with_running_program(path, fn, ...)
    local previous = current_program
    current_program = path
    local results = { pcall(fn, ...) }
    current_program = previous
    if not results[1] then error(results[2], 0) end
    table.remove(results, 1)
    return unpack_fn(results)
  end

  local http_proxy
  if _G.http then
    http_proxy = setmetatable({}, { __index = _G.http })
    if _G.http.get then
      http_proxy.get = make_http_get(_G.http, session)
    end
  end

  local shell_proxy
  local function resolve_program(command)
    if not command or command == "" then return nil end
    if real_fs.exists and real_fs.exists(command) then return command end
    if real_fs.exists and real_fs.exists(command .. ".lua") then
      return command .. ".lua"
    end
    if _G.shell and _G.shell.resolveProgram then
      local ok, resolved = pcall(_G.shell.resolveProgram, command)
      if ok and resolved and real_fs.exists and real_fs.exists(resolved) then
        return resolved
      end
    end
    return nil
  end

  local function run_observed_file(path, args)
    local fn, err = observed_loadfile(path, "t", env)
    if not fn then error(err, 2) end
    return with_running_program(path, fn, unpack_fn(args or {}))
  end

  local function observed_wget(args)
    if args[1] == "run" then
      local url = args[2]
      if not url or not http_proxy or not http_proxy.get then return false end
      local response, err = http_proxy.get(url)
      if not response then error(err or "wget run failed", 2) end
      local body = response.readAll()
      response.close()
      local fn, load_err = load(body, "@" .. url, "t", env)
      if not fn then error(load_err, 2) end
      return with_running_program(url, fn, unpack_fn(copy_args(args, 3)))
    end

    local url, dest = args[1], args[2]
    if not url or not dest or not http_proxy or not http_proxy.get then
      return false
    end
    local response, err = http_proxy.get(url)
    if not response then error(err or "wget failed", 2) end
    local body = response.readAll()
    response.close()
    local f, open_err = hooked.open(dest, "w")
    if not f then error(open_err or ("cannot open " .. dest), 2) end
    f.write(body)
    f.close()
    return true
  end

  local function observed_shell_run(...)
    local raw = {...}
    if #raw == 0 then return false end
    local parts
    if #raw == 1 then
      parts = split_words(raw[1])
    else
      parts = raw
    end
    local command = tostring(parts[1] or "")
    local args = copy_args(parts, 2)
    local recorded_args = {}
    for _, arg in ipairs(args) do table.insert(recorded_args, tostring(arg)) end
    table.insert(session.shell_runs, { command = command, args = recorded_args })

    if command == "wget" or command == "wget.lua" then
      return observed_wget(args)
    end

    local path = resolve_program(command)
    if path then return run_observed_file(path, args) end
    if _G.shell and _G.shell.run then
      return _G.shell.run(...)
    end
    return false
  end

  local os_proxy
  if _G.os then
    os_proxy = setmetatable({}, { __index = _G.os })
    os_proxy.run = function(run_env, path, ...)
      table.insert(session.shell_runs, {
        command = "os.run",
        args = { tostring(path or "") },
      })
      local child_env = {}
      if type(run_env) == "table" then
        for k, v in pairs(run_env) do child_env[k] = v end
      end
      child_env.fs = hooked
      child_env.http = http_proxy
      child_env.shell = shell_proxy
      child_env.os = os_proxy
      child_env.loadfile = observed_loadfile
      child_env.dofile = observed_dofile
      setmetatable(child_env, { __index = env })
      local fn, err = observed_loadfile(path, "t", child_env)
      if not fn then return false, err end
      return with_running_program(path, fn, ...)
    end
  end

  local env_base = {
    fs = hooked,
    loadfile = observed_loadfile,
    dofile = observed_dofile,
    http = http_proxy,
    os = os_proxy,
    package = make_package_proxy(),
  }

  if _G.shell then
    shell_proxy = setmetatable({}, { __index = _G.shell })
    shell_proxy.run = observed_shell_run
    shell_proxy.getRunningProgram = function()
      if current_program then
        return current_program
      end
      if _G.shell.getRunningProgram then
        return _G.shell.getRunningProgram()
      end
      return nil
    end
    env_base.shell = shell_proxy
  end

  env = setmetatable(env_base, { __index = _G })
  session.env = env

  -- Snapshot every captured write into the final manifest, deduping by
  -- path (an installer that writes the same file twice should appear once)
  -- and computing SHA-256 of the final on-disk content.
  session.finish = function(self)
    local hash = try_load_hash()
    local seen = {}
    local order = {}
    for _, w in ipairs(self.writes) do
      if not seen[w.path] then
        table.insert(order, w.path)
      end
      seen[w.path] = w.mode
    end

    local manifest = {
      writes  = {},
      deletes = self.deletes,
      dirs    = self.dirs,
      moves   = self.moves,
      copies  = self.copies,
      fetches = {},
      shell_runs = self.shell_runs,
    }
    for _, path in ipairs(order) do
      local content = read_file(self.real_fs, path)
      local entry = { path = path, mode = seen[path] }
      if content then
        entry.bytes = #content
        if hash and hash.sha256hex then
          entry.sha256 = hash.sha256hex(content)
        end
      else
        entry.bytes = 0
      end
      table.insert(manifest.writes, entry)
    end
    for _, fetch in ipairs(self.fetches) do
      local entry = {
        url = fetch.url,
        ok = fetch.ok == true,
        status = fetch.status,
        error = fetch.error,
      }
      if fetch.body then
        entry.bytes = #fetch.body
        if hash and hash.sha256hex then
          entry.sha256 = hash.sha256hex(fetch.body)
        end
      elseif fetch.bytes then
        entry.bytes = fetch.bytes
      end
      table.insert(manifest.fetches, entry)
    end
    return manifest
  end

  return session
end

return M
