-- argparse tests.
package.path = package.path .. ";../?/init.lua;../?.lua"
local argparse = require("argparse")

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

-- Basic flag.
local p = argparse.new("test")
p:flag("yes", { short = "y" })

local r = p:parse({"--yes"})
check("long flag", true, r.flags.yes)

r = p:parse({"-y"})
check("short flag", true, r.flags.yes)

r = p:parse({})
check("absent flag", nil, r.flags.yes)

-- Option with value.
p = argparse.new("test")
p:option("source", { short = "s" })

r = p:parse({"--source=alfaoz/foo"})
check("option =value", "alfaoz/foo", r.options.source)

r = p:parse({"--source", "alfaoz/foo"})
check("option space value", "alfaoz/foo", r.options.source)

r = p:parse({"-s", "x"})
check("short option", "x", r.options.source)

r = p:parse({"-sx"})
check("short option clustered", "x", r.options.source)

-- Positional.
p = argparse.new("test")
p:positional("name")

r = p:parse({"foo"})
check("positional", "foo", r.name)

local _, err = p:parse({})
check("missing required positional", true, err ~= nil and err:find("missing") ~= nil)

-- Optional positional with default.
p = argparse.new("test")
p:positional("name", { required = false, default = "world" })

r = p:parse({})
check("default positional", "world", r.name)

-- Mix of flags + options + positionals.
p = argparse.new("test")
p:flag("yes")
p:option("source")
p:positional("package")

r = p:parse({"--source=x", "--yes", "foo"})
check("mixed positional", "foo", r.package)
check("mixed flag", true, r.flags.yes)
check("mixed option", "x", r.options.source)

-- Subcommand.
p = argparse.new("allay")
local install = p:subcommand("install", "Install a package")
install:positional("package")
install:flag("yes")

r = p:parse({"install", "secure-rednet", "--yes"})
check("subcommand selected", "install", r.command)
check("subcommand positional", "secure-rednet", r.package)
check("subcommand flag", true, r.flags.yes)

-- Unknown option.
p = argparse.new("test")
local _, err2 = p:parse({"--unknown"})
check("unknown option errors", true, err2 ~= nil and err2:find("unknown") ~= nil)

-- Help flag.
p = argparse.new("test")
r = p:parse({"--help"})
check("--help captured", true, r.flags.help)

r = p:parse({"-h"})
check("-h captured", true, r.flags.help)

-- "Rest" positional.
p = argparse.new("test")
p:positional("files", { rest = true, required = false })

r = p:parse({"a", "b", "c"})
check("rest positional", 3, #r.files)
check("rest values", "b", r.files[2])

-- "--" separator.
p = argparse.new("test")
p:positional("first")
p:positional("second", { required = false })

r = p:parse({"--", "--source", "foo"})
check("after -- not flag", "--source", r.first)

-- format_help doesn't crash.
p = argparse.new("test", "test summary")
p:flag("yes")
p:option("source")
p:positional("pkg")
local help = p:format_help()
check("help non-empty", true, #help > 0)
check("help mentions usage", true, help:find("Usage") ~= nil)

print()
print(string.format("argparse: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
