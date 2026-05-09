-- Run every test file in this directory.
local tests = {
  "hash_test",
  "pathkit_test",
  "log_test",
  "httpkit_test",
  "argparse_test",
  "levenshtein_test",
  "ui_test",
  "scout_test",
  "observe_test",
}

local total_pass, total_fail = 0, 0

for _, name in ipairs(tests) do
  print("=== " .. name .. " ===")
  local ok, err = pcall(function()
    -- shell out so each test starts with a fresh global env.
    local cmd = string.format("lua %s.lua", name)
    local h = io.popen(cmd .. " 2>&1")
    local out = h:read("*a")
    local exit = h:close()
    io.write(out)
    -- count "tests passed" line
    local pass, total = out:match("(%d+)/(%d+) tests passed")
    if pass and total then
      total_pass = total_pass + tonumber(pass)
      total_fail = total_fail + (tonumber(total) - tonumber(pass))
    end
    if not exit then
      total_fail = total_fail + 1
    end
  end)
  if not ok then
    print("[ERR] " .. tostring(err))
    total_fail = total_fail + 1
  end
  print()
end

print("=========================================")
print(string.format("ALL TESTS: %d passed, %d failed", total_pass, total_fail))
if total_fail > 0 then os.exit(1) end
