-- observe tests. Mock fs, run an "installer," verify the manifest.
package.path = package.path .. ";../?/init.lua;../?.lua"

local files = {}

_G.fs = {
  exists = function(p) return files[p] ~= nil end,
  isDir  = function(p) return files[p] and files[p].dir == true end,
  open = function(path, mode)
    if mode == "r" or mode == "rb" then
      if not files[path] or files[path].dir then return nil end
      return {
        readAll = function() return files[path].content end,
        close = function() end,
      }
    elseif mode:find("w") then
      local entry = { content = "" }
      return {
        write = function(_, d)
          if type(_) == "string" then d = _ end
          entry.content = entry.content .. (d or "")
        end,
        close = function() files[path] = entry end,
      }
    elseif mode:find("a") then
      local existing = (files[path] and files[path].content) or ""
      local entry = { content = existing }
      return {
        write = function(_, d)
          if type(_) == "string" then d = _ end
          entry.content = entry.content .. (d or "")
        end,
        close = function() files[path] = entry end,
      }
    end
  end,
  delete = function(p)
    files[p] = nil
    for k, _ in pairs(files) do
      if k:sub(1, #p + 1) == p .. "/" then files[k] = nil end
    end
  end,
  makeDir = function(p) files[p] = { dir = true } end,
  move = function(a, b) files[b] = files[a]; files[a] = nil end,
  copy = function(a, b) files[b] = { content = files[a].content } end,
}

-- Stub hash so we get deterministic-ish sha values in tests.
package.preload.hash = function()
  return { sha256hex = function(s) return "sha:" .. tostring(#s) end }
end

local observe = require("observe")

local total, failed = 0, 0
local function check(name, expected, actual)
  total = total + 1
  if expected == actual then
    print("[PASS] " .. name)
  else
    failed = failed + 1
    print("[FAIL] " .. name)
    print("  expected: " .. tostring(expected))
    print("  actual:   " .. tostring(actual))
  end
end

-- ---------- writes ----------
files = {}
local s = observe.start()
local f = s.fs.open("/test.lua", "w"); f.write("hello"); f.close()
local m = s:finish()
check("captured 1 write",     1,           #m.writes)
check("write path",           "/test.lua", m.writes[1].path)
check("write mode w",         "w",         m.writes[1].mode)
check("write sha",            "sha:5",     m.writes[1].sha256)
check("write bytes",          5,           m.writes[1].bytes)

-- ---------- delete ----------
files = { ["/old"] = { content = "x" } }
local s2 = observe.start()
s2.fs.delete("/old")
local m2 = s2:finish()
check("captured delete",      "/old", m2.deletes[1])
check("file actually deleted", nil,    files["/old"])

-- ---------- makeDir ----------
files = {}
local s3 = observe.start()
s3.fs.makeDir("/new/dir")
local m3 = s3:finish()
check("captured makeDir",     "/new/dir", m3.dirs[1])

-- ---------- move ----------
files = { ["/a"] = { content = "x" } }
local s4 = observe.start()
s4.fs.move("/a", "/b")
local m4 = s4:finish()
check("captured move from",   "/a", m4.moves[1].from)
check("captured move to",     "/b", m4.moves[1].to)

-- ---------- copy ----------
files = { ["/a"] = { content = "x" } }
local s5 = observe.start()
s5.fs.copy("/a", "/c")
local m5 = s5:finish()
check("captured copy from",   "/a", m5.copies[1].from)
check("captured copy to",     "/c", m5.copies[1].to)

-- ---------- pass-through ----------
files = { ["/exists"] = { content = "yes" } }
local s6 = observe.start()
check("pass-through exists",     true,  s6.fs.exists("/exists"))
check("pass-through not-exists", false, s6.fs.exists("/nope"))

-- ---------- run a fake installer in the env ----------
files = {}
local s7 = observe.start()
local code = [[
  local f = fs.open("/installed.lua", "w")
  f.write("payload")
  f.close()
  fs.makeDir("/lib")
]]
local fn, err = load(code, "installer", "t", s7.env)
assert(fn, "loader err: " .. tostring(err))
fn()
local m7 = s7:finish()
check("installer wrote 1 file",       1,                #m7.writes)
check("installer wrote file path",    "/installed.lua", m7.writes[1].path)
check("installer made 1 dir",         1,                #m7.dirs)
check("installer made dir path",      "/lib",           m7.dirs[1])

-- ---------- helper files inherit observed env ----------
files = {
  ["/helper.lua"] = {
    content = [[
      local f = fs.open("/from_helper.lua", "w")
      f.write("helper")
      f.close()
    ]],
  },
}
local s10 = observe.start()
local fn10 = assert(load([[dofile("/helper.lua")]], "installer", "t", s10.env))
fn10()
local m10 = s10:finish()
check("dofile helper write captured", 1,                  #m10.writes)
check("dofile helper write path",     "/from_helper.lua", m10.writes[1].path)

-- ---------- shell.getRunningProgram can be virtualized ----------
_G.shell = { getRunningProgram = function() return "/bin/allay.lua" end }
local s11 = observe.start({ running_program = "vim_installer.lua" })
check("shell running program override", "vim_installer.lua",
  s11.env.shell.getRunningProgram())
_G.shell = nil

-- ---------- http fetches are recorded ----------
files = {}
local http_bodies = { ["https://example.com/payload.lua"] = "payload" }
_G.http = {
  get = function(url)
    return {
      readAll = function() return http_bodies[url] end,
      getResponseCode = function() return 200 end,
      close = function() end,
    }
  end,
}
local s12 = observe.start()
local fn12 = assert(load([[
  local r = http.get("https://example.com/payload.lua")
  local body = r.readAll()
  r.close()
  local f = fs.open("/downloaded.lua", "w")
  f.write(body)
  f.close()
]], "installer", "t", s12.env))
fn12()
local m12 = s12:finish()
check("http fetch captured", 1, #m12.fetches)
check("http fetch url", "https://example.com/payload.lua", m12.fetches[1].url)
check("http fetch sha", "sha:7", m12.fetches[1].sha256)
check("http fetched write captured", "/downloaded.lua", m12.writes[1].path)
_G.http = nil

-- ---------- package global is available even when CraftOS omits it ----------
local original_package = _G.package
_G.package = nil
files = {}
local s15 = observe.start()
local fn15 = assert(load([[
  local old_path = package.path
  package.path = "basalt;" .. old_path
  package.loaded.log = nil
  local f = fs.open("/package-path.txt", "w")
  f.write(package.path)
  f.close()
]], "installer", "t", s15.env))
fn15()
local m15 = s15:finish()
check("package proxy write captured", "/package-path.txt", m15.writes[1].path)
check("package proxy path content", "sha:7", m15.writes[1].sha256)
_G.package = original_package

-- ---------- shell.run local scripts inherit observed env ----------
files = {
  ["/child.lua"] = {
    content = [[
      local dest = ...
      local f = fs.open(dest, "w")
      f.write(shell.getRunningProgram())
      f.close()
    ]],
  },
}
_G.shell = { getRunningProgram = function() return "/parent.lua" end }
local s13 = observe.start({ running_program = "/installer.lua" })
local fn13 = assert(load([[shell.run("/child.lua", "/child-output.lua")]],
  "installer", "t", s13.env))
fn13()
local m13 = s13:finish()
check("shell.run captured", "/child.lua", m13.shell_runs[1].command)
check("shell.run child write", "/child-output.lua", m13.writes[1].path)
check("shell.run child running program", "sha:10", m13.writes[1].sha256)
_G.shell = nil

-- ---------- shell.run wget downloads through observed fs/http ----------
files = {}
http_bodies = { ["https://example.com/app.lua"] = "appbody" }
_G.http = {
  get = function(url)
    return {
      readAll = function() return http_bodies[url] end,
      getResponseCode = function() return 200 end,
      close = function() end,
    }
  end,
}
_G.shell = { getRunningProgram = function() return "/parent.lua" end }
local s14 = observe.start()
local fn14 = assert(load([[shell.run("wget", "https://example.com/app.lua", "/app.lua")]],
  "installer", "t", s14.env))
fn14()
local m14 = s14:finish()
check("wget shell run captured", "wget", m14.shell_runs[1].command)
check("wget fetch captured", "https://example.com/app.lua", m14.fetches[1].url)
check("wget write captured", "/app.lua", m14.writes[1].path)
_G.http = nil
_G.shell = nil

-- ---------- dedupe writes to same path ----------
files = {}
local s8 = observe.start()
local w1 = s8.fs.open("/x", "w"); w1.write("first");  w1.close()
local w2 = s8.fs.open("/x", "w"); w2.write("second"); w2.close()
local m8 = s8:finish()
check("dedupe same-path writes",      1,        #m8.writes)
check("dedupe content reflects last", "sha:6",  m8.writes[1].sha256)

-- ---------- append mode ----------
files = { ["/y"] = { content = "AAA" } }
local s9 = observe.start()
local fa = s9.fs.open("/y", "a"); fa.write("BBB"); fa.close()
local m9 = s9:finish()
check("append captured as write",     1,       #m9.writes)
check("append mode preserved",        "a",     m9.writes[1].mode)
check("append final content hashed",  "sha:6", m9.writes[1].sha256)

if failed > 0 then
  print(string.format("\nobserve: %d/%d passed (%d FAILED)", total - failed, total, failed))
  os.exit(1)
else
  print(string.format("\nobserve: %d/%d tests passed", total, total))
end
