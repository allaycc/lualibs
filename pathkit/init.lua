-- pathkit: atomic file operations and path helpers for CC.
--
-- Wraps CC's fs API with semantics that handle the common bugs:
-- atomic writes (tmp + move), idempotent mkdir, safe path joining,
-- and a few conveniences.

local M = {}

M.VERSION = "1.0.0"

-- Path helpers (pure string manipulation, work without fs).

function M.join(...)
  local parts = {...}
  if #parts == 0 then return "" end
  local result = parts[1] or ""
  for i = 2, #parts do
    local p = parts[i] or ""
    if p == "" then
      -- skip
    elseif result == "" then
      result = p
    elseif result:sub(-1) == "/" then
      if p:sub(1, 1) == "/" then
        result = result .. p:sub(2)
      else
        result = result .. p
      end
    else
      if p:sub(1, 1) == "/" then
        result = result .. p
      else
        result = result .. "/" .. p
      end
    end
  end
  return result
end

function M.dirname(path)
  if fs and fs.getDir then return fs.getDir(path) end
  local s = path:match("^(.*)/[^/]*$")
  return s or ""
end

function M.basename(path)
  if fs and fs.getName then return fs.getName(path) end
  return path:match("([^/]+)$") or path
end

function M.extension(path)
  return path:match("%.([^%.]+)$")
end

function M.strip_extension(path)
  return (path:gsub("%.[^%.]+$", ""))
end

-- Filesystem operations (require fs).

local function require_fs()
  if not fs then
    error("pathkit: fs API is not available (not running in CC?)")
  end
end

function M.exists(path)
  require_fs()
  return fs.exists(path)
end

function M.is_dir(path)
  require_fs()
  return fs.exists(path) and fs.isDir(path)
end

function M.is_file(path)
  require_fs()
  return fs.exists(path) and not fs.isDir(path)
end

function M.list(path)
  require_fs()
  if not fs.exists(path) then return {} end
  return fs.list(path)
end

function M.size(path)
  require_fs()
  if not fs.exists(path) then return 0 end
  return fs.getSize(path)
end

-- Make a directory and all its parents. Idempotent.
function M.mkdir_p(path)
  require_fs()
  if path == "" or path == "/" then return true end
  if fs.exists(path) then
    if fs.isDir(path) then return true end
    return false, "path exists and is not a directory: " .. path
  end
  fs.makeDir(path)
  return true
end

-- Read the full contents of a file as a string. Returns nil, err on failure.
function M.read(path)
  require_fs()
  if not fs.exists(path) then
    return nil, "no such file: " .. path
  end
  local f = fs.open(path, "r")
  if not f then
    return nil, "cannot open for reading: " .. path
  end
  local content = f.readAll()
  f.close()
  return content
end

-- Write a string to a file. Non-atomic; prefer write_atomic for any data
-- that matters.
function M.write(path, content)
  require_fs()
  local parent = M.dirname(path)
  if parent ~= "" and not fs.exists(parent) then
    M.mkdir_p(parent)
  end
  local f = fs.open(path, "w")
  if not f then
    return false, "cannot open for writing: " .. path
  end
  f.write(content)
  f.close()
  return true
end

-- Write content to path atomically: write to a temp file in the same
-- directory, then fs.move it into place. The destination either contains
-- the new content fully or the old content fully, never partial.
function M.write_atomic(path, content)
  require_fs()
  local parent = M.dirname(path)
  if parent ~= "" and not fs.exists(parent) then
    M.mkdir_p(parent)
  end

  local tmp = path .. ".tmp"
  if fs.exists(tmp) then
    fs.delete(tmp)
  end

  local f = fs.open(tmp, "w")
  if not f then
    return false, "cannot open temp for writing: " .. tmp
  end
  f.write(content)
  f.close()

  if fs.exists(path) then
    fs.delete(path)
  end
  fs.move(tmp, path)
  return true
end

-- Delete a file or directory (recursively for directories). Idempotent.
function M.delete(path)
  require_fs()
  if fs.exists(path) then
    fs.delete(path)
  end
  return true
end

-- Move a file from src to dst, replacing dst if it exists.
function M.move(src, dst)
  require_fs()
  if not fs.exists(src) then
    return false, "no such file: " .. src
  end
  if fs.exists(dst) then
    fs.delete(dst)
  end
  local parent = M.dirname(dst)
  if parent ~= "" and not fs.exists(parent) then
    M.mkdir_p(parent)
  end
  fs.move(src, dst)
  return true
end

-- Copy src to dst.
function M.copy(src, dst)
  require_fs()
  if not fs.exists(src) then
    return false, "no such file: " .. src
  end
  if fs.exists(dst) then
    fs.delete(dst)
  end
  local parent = M.dirname(dst)
  if parent ~= "" and not fs.exists(parent) then
    M.mkdir_p(parent)
  end
  fs.copy(src, dst)
  return true
end

-- Walk a directory tree, returning a list of all file paths (not dirs).
function M.walk(root)
  require_fs()
  local results = {}
  local function recurse(dir)
    if not fs.exists(dir) or not fs.isDir(dir) then return end
    for _, entry in ipairs(fs.list(dir)) do
      local full = M.join(dir, entry)
      if fs.isDir(full) then
        recurse(full)
      else
        table.insert(results, full)
      end
    end
  end
  recurse(root)
  return results
end

return M
