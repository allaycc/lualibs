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
  -- Convenience: an env table the caller can hand to load(...).
  session.env = setmetatable({ fs = hooked }, { __index = _G })

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
    return manifest
  end

  return session
end

return M
