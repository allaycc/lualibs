package.path = package.path .. ";../?/init.lua;../?.lua"

-- ui only writes to stdout; we capture writes by stubbing io.write/io.flush
-- and io.read. No CC term/colors stubbed -- that exercises the
-- non-CC fallback branch (color() just writes plain text, with_spinner
-- runs work() inline without animation).
local captured = {}
local orig_write = io.write
local orig_flush = io.flush
io.write = function(s) table.insert(captured, tostring(s)) end
io.flush = function() end

local function read_capture()
  local s = table.concat(captured)
  captured = {}
  return s
end

local read_queue = {}
io.read = function() return table.remove(read_queue, 1) end

local ui = require("ui")

local total, failed = 0, 0
local function check(name, expected, actual)
  total = total + 1
  if expected == actual then
    -- Restore real write so the report itself prints normally.
    io.write = orig_write
    print("[PASS] " .. name)
    io.write = function(s) table.insert(captured, tostring(s)) end
  else
    failed = failed + 1
    io.write = orig_write
    print("[FAIL] " .. name)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
    io.write = function(s) table.insert(captured, tostring(s)) end
  end
end

-- ---------------------------------------------------------------------------
-- color / ok / info / warn / fail
-- ---------------------------------------------------------------------------
ui.color("green", "hello")
check("color writes plain text without term", "hello", read_capture())

ui.ok("yay")
check("ok appends newline", "yay\n", read_capture())
ui.warn("oops")
check("warn appends newline", "oops\n", read_capture())

-- ---------------------------------------------------------------------------
-- confirm
-- ---------------------------------------------------------------------------
read_queue = {""}
local r = ui.confirm("Continue?")
check("confirm: empty defaults yes", true, r)
read_capture()

read_queue = {"y"}
r = ui.confirm("Continue?")
check("confirm: y is yes", true, r)
read_capture()

read_queue = {"n"}
r = ui.confirm("Continue?")
check("confirm: n is no", false, r)
read_capture()

read_queue = {"NO"}
r = ui.confirm("Continue?")
check("confirm: NO normalized to no", false, r)
read_capture()

read_queue = {"never"}  -- yes_flag short-circuits before read
r = ui.confirm("Continue?", { yes_flag = true })
check("confirm: yes_flag bypasses prompt", true, r)
check("confirm: yes_flag wrote nothing", "", read_capture())

-- ---------------------------------------------------------------------------
-- with_spinner: outside CC (no parallel), runs work() inline.
-- ---------------------------------------------------------------------------
local result = ui.with_spinner("test", function() return 42 end)
check("with_spinner: returns work's value (no parallel fallback)", 42, result)

local r1, r2 = ui.with_spinner("multi", function() return "a", "b" end)
check("with_spinner: multiple returns r1", "a", r1)
check("with_spinner: multiple returns r2", "b", r2)

-- Restore.
io.write = orig_write
io.flush = orig_flush

print()
print(string.format("ui: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
