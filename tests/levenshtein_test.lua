package.path = package.path .. ";../?/init.lua;../?.lua"

local lev = require("levenshtein")

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

-- Basics.
check("identical strings -> 0", 0, lev.distance("hello", "hello"))
check("empty vs empty -> 0", 0, lev.distance("", ""))
check("empty vs string -> length", 5, lev.distance("", "hello"))
check("string vs empty -> length", 5, lev.distance("hello", ""))

-- Single-edit cases.
check("one insertion", 1, lev.distance("cat", "cats"))
check("one deletion", 1, lev.distance("cats", "cat"))
check("one substitution", 1, lev.distance("cat", "bat"))

-- Classic textbook example.
check("kitten -> sitting = 3", 3, lev.distance("kitten", "sitting"))
check("sunday -> saturday = 3", 3, lev.distance("sunday", "saturday"))

-- Symmetric.
check("symmetric a/b", lev.distance("foo", "bars"), lev.distance("bars", "foo"))

-- Callable as a function.
check("callable form", 1, lev("a", "b"))

-- Suggest helper.
local commands = { "install", "remove", "update", "list", "search" }
local hit = lev.suggest("instal", commands)
check("suggest: typo -> install", "install", hit)

local _, miss_d = lev.suggest("install", commands)
check("suggest: exact match returns 0", 0, miss_d)

local far = lev.suggest("xyzzy", commands)
check("suggest: too far -> nil", nil, far)

local custom_max = lev.suggest("xyzzy", commands, 10)
check("suggest: with high max -> first candidate within range",
  type(custom_max), "string")

-- Type errors.
local ok = pcall(lev.distance, 42, "x")
check("non-string arg errors", false, ok)

print()
print(string.format("levenshtein: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
