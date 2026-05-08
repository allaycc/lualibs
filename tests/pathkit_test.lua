-- pathkit tests. Pure-string functions tested directly.
-- Filesystem functions tested with a fake fs implementation.
package.path = package.path .. ";../?/init.lua;../?.lua"

-- Set up a fake fs module before requiring pathkit.
local files = {}  -- path -> { content = string } | { dir = true }

_G.fs = {
  exists = function(path) return files[path] ~= nil end,
  isDir = function(path) return files[path] and files[path].dir == true end,
  getDir = function(path) return path:match("^(.*)/[^/]*$") or "" end,
  getName = function(path) return path:match("([^/]+)$") or path end,
  getSize = function(path)
    local f = files[path]
    if not f or f.dir then return 0 end
    return #(f.content or "")
  end,
  makeDir = function(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
      table.insert(parts, part)
      local cur = "/" .. table.concat(parts, "/")
      if not files[cur] then files[cur] = { dir = true } end
    end
    if path:sub(1, 1) ~= "/" then files[path] = { dir = true } end
  end,
  list = function(path)
    local results = {}
    local prefix = path == "/" and "/" or (path .. "/")
    for p, _ in pairs(files) do
      if p:sub(1, #prefix) == prefix then
        local rest = p:sub(#prefix + 1)
        if not rest:find("/") and rest ~= "" then
          table.insert(results, rest)
        end
      end
    end
    return results
  end,
  open = function(path, mode)
    if mode == "r" then
      if not files[path] or files[path].dir then return nil end
      local content = files[path].content
      return {
        readAll = function() return content end,
        close = function() end,
      }
    elseif mode == "w" then
      local entry = { content = "" }
      return {
        write = function(_, data)
          if type(_) == "string" then data = _ end  -- both call styles
          entry.content = entry.content .. data
        end,
        close = function() files[path] = entry end,
      }
    end
    return nil
  end,
  delete = function(path)
    files[path] = nil
    -- delete children too
    for p, _ in pairs(files) do
      if p:sub(1, #path + 1) == path .. "/" then
        files[p] = nil
      end
    end
  end,
  move = function(src, dst)
    files[dst] = files[src]
    files[src] = nil
  end,
  copy = function(src, dst)
    files[dst] = { content = files[src].content }
  end,
}

local pk = require("pathkit")

local total, failed = 0, 0
local function check(name, expected, actual)
  total = total + 1
  if expected == actual then
    print("[PASS] " .. name)
  else
    failed = failed + 1
    print("[FAIL] " .. name)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
  end
end

-- Path helpers (pure strings).
check("join basic", "/a/b/c", pk.join("/a", "b", "c"))
check("join with trailing slash", "/a/b/c", pk.join("/a/", "b", "c"))
check("join with leading slash", "/a/b/c", pk.join("/a", "/b", "/c"))
check("join empty parts", "/a/b", pk.join("/a", "", "b"))
check("join single", "/a", pk.join("/a"))
check("join no args", "", pk.join())

check("dirname normal", "/a/b", pk.dirname("/a/b/c"))
check("dirname root file", "", pk.dirname("foo"))
check("basename normal", "c.lua", pk.basename("/a/b/c.lua"))
check("extension lua", "lua", pk.extension("foo.lua"))
check("extension none", nil, pk.extension("foo"))
check("strip_extension", "foo", pk.strip_extension("foo.lua"))

-- Filesystem ops via fake fs.
files = {}  -- reset

pk.write("/test/a.txt", "hello")
check("write creates file", true, pk.exists("/test/a.txt"))
check("write content correct", "hello", pk.read("/test/a.txt"))
check("write created parent dir", true, pk.is_dir("/test"))

pk.write_atomic("/test/b.txt", "world")
check("atomic write content", "world", pk.read("/test/b.txt"))
check("atomic write left no tmp", false, pk.exists("/test/b.txt.tmp"))

pk.write_atomic("/test/b.txt", "replaced")
check("atomic overwrite", "replaced", pk.read("/test/b.txt"))

pk.mkdir_p("/test/sub/deep")
check("mkdir_p deep dir", true, pk.is_dir("/test/sub/deep"))

local ok, err = pk.read("/nonexistent")
check("read missing returns nil", nil, ok)
check("read missing has error", true, err ~= nil)

pk.delete("/test/b.txt")
check("delete removes", false, pk.exists("/test/b.txt"))

pk.write("/test/c.txt", "c content")
pk.move("/test/c.txt", "/test/d.txt")
check("move source gone", false, pk.exists("/test/c.txt"))
check("move dest exists", true, pk.exists("/test/d.txt"))
check("move content preserved", "c content", pk.read("/test/d.txt"))

pk.copy("/test/d.txt", "/test/e.txt")
check("copy source still there", true, pk.exists("/test/d.txt"))
check("copy dest exists", true, pk.exists("/test/e.txt"))

print()
print(string.format("pathkit: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
