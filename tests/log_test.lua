-- log tests. Output is captured via a temporary print override.
package.path = package.path .. ";../?/init.lua;../?.lua"
local log = require("log")

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

-- Capture print output.
local captured
local original_print = print
local function capture(fn)
  captured = {}
  _G.print = function(s) table.insert(captured, s) end
  fn()
  _G.print = original_print
  return captured
end

-- Levels.
check("DEBUG is 0", 0, log.LEVELS.DEBUG)
check("INFO is 1",  1, log.LEVELS.INFO)
check("WARN is 2",  2, log.LEVELS.WARN)
check("ERROR is 3", 3, log.LEVELS.ERROR)

-- set_level by name.
log.set_level("DEBUG")
check("set_level DEBUG", 0, log.get_level())

log.set_level("ERROR")
check("set_level ERROR", 3, log.get_level())

-- Output filtering by level.
log.set_level(log.LEVELS.INFO)

local out = capture(function()
  log.debug("d")  -- below INFO, suppressed
  log.info("i")
  log.warn("w")
  log.error("e")
end)
check("debug suppressed at INFO level", 3, #out)
check("info emitted", "i", out[1])
check("warn emitted", "w", out[2])

-- Prefix.
log.set_prefix("test")
out = capture(function() log.info("hello") end)
check("prefix applied", "[test] hello", out[1])
log.set_prefix(nil)

-- Format helpers.
out = capture(function() log.infof("hello %s, count=%d", "world", 42) end)
check("infof formatted", "hello world, count=42", out[1])

print()
print(string.format("log: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
