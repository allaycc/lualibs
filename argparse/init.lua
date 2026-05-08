-- argparse: a small command-line argument parser for CC programs.
--
-- Supports subcommands, positionals, flags (--yes), and options with values
-- (--source=foo or --source foo). Generates help text. Returns parsed args
-- as a table or prints help and exits on error.

local M = {}

M.VERSION = "1.0.0"

-- ---------------------------------------------------------------------------
-- Parser construction
-- ---------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

function M.new(name, summary)
  local p = setmetatable({}, Parser)
  p.name = name or "program"
  p.summary = summary or ""
  p.positionals = {}     -- { {name, required, help, default}, ... }
  p.flags = {}           -- name -> { help, short }
  p.options = {}         -- name -> { help, short, default }
  p.subcommands = {}     -- name -> Parser
  p.subcommand_help = {} -- name -> short description
  return p
end

-- Add a positional argument.
function Parser:positional(name, opts)
  opts = opts or {}
  table.insert(self.positionals, {
    name = name,
    required = opts.required ~= false,
    help = opts.help or "",
    default = opts.default,
    rest = opts.rest == true,  -- collect all remaining args into a list
  })
  return self
end

-- Add a boolean flag (--name or -short).
function Parser:flag(name, opts)
  opts = opts or {}
  self.flags[name] = {
    help = opts.help or "",
    short = opts.short,
  }
  return self
end

-- Add an option that takes a value (--name=value or --name value).
function Parser:option(name, opts)
  opts = opts or {}
  self.options[name] = {
    help = opts.help or "",
    short = opts.short,
    default = opts.default,
    required = opts.required == true,
  }
  return self
end

-- Add a subcommand. The returned parser is configured the same way.
function Parser:subcommand(name, summary)
  local sub = M.new(self.name .. " " .. name, summary or "")
  self.subcommands[name] = sub
  self.subcommand_help[name] = summary or ""
  return sub
end

-- ---------------------------------------------------------------------------
-- Help text generation
-- ---------------------------------------------------------------------------

function Parser:format_help()
  local lines = {}
  if self.summary ~= "" then
    table.insert(lines, self.summary)
    table.insert(lines, "")
  end

  local usage_parts = { "Usage:", self.name }
  if next(self.subcommands) then
    table.insert(usage_parts, "<command>")
    table.insert(usage_parts, "[options]")
  else
    if next(self.flags) or next(self.options) then
      table.insert(usage_parts, "[options]")
    end
    for _, p in ipairs(self.positionals) do
      if p.required then
        table.insert(usage_parts, "<" .. p.name .. ">")
      else
        table.insert(usage_parts, "[" .. p.name .. "]")
      end
    end
  end
  table.insert(lines, table.concat(usage_parts, " "))

  if next(self.subcommands) then
    table.insert(lines, "")
    table.insert(lines, "Commands:")
    local names = {}
    for n, _ in pairs(self.subcommand_help) do table.insert(names, n) end
    table.sort(names)
    for _, n in ipairs(names) do
      table.insert(lines, string.format("  %-12s %s", n, self.subcommand_help[n]))
    end
  end

  if #self.positionals > 0 and not next(self.subcommands) then
    table.insert(lines, "")
    table.insert(lines, "Arguments:")
    for _, p in ipairs(self.positionals) do
      table.insert(lines, string.format("  %-12s %s", p.name, p.help))
    end
  end

  if next(self.flags) or next(self.options) then
    table.insert(lines, "")
    table.insert(lines, "Options:")
    local names = {}
    for n, _ in pairs(self.flags) do table.insert(names, {n, "flag"}) end
    for n, _ in pairs(self.options) do table.insert(names, {n, "option"}) end
    table.sort(names, function(a, b) return a[1] < b[1] end)
    for _, entry in ipairs(names) do
      local name, kind = entry[1], entry[2]
      local item = kind == "flag" and self.flags[name] or self.options[name]
      local short = item.short and ("-" .. item.short .. ", ") or "    "
      local arg = kind == "option" and " <value>" or ""
      table.insert(lines, string.format("  %s--%s%s", short, name, arg))
      if item.help ~= "" then
        table.insert(lines, "      " .. item.help)
      end
    end
  end

  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Parsing
-- ---------------------------------------------------------------------------

local function find_short(parser, ch)
  for n, f in pairs(parser.flags) do
    if f.short == ch then return n, "flag" end
  end
  for n, o in pairs(parser.options) do
    if o.short == ch then return n, "option" end
  end
  return nil
end

-- Parse a list of args. Returns either a table of parsed values or
-- (nil, error_message). The "command" key in the returned table is the
-- subcommand name if any.
function Parser:parse(argv)
  argv = argv or {}
  local result = {
    flags = {},
    options = {},
    positionals = {},
  }
  local positional_idx = 1
  local i = 1

  -- If a subcommand is the first non-flag arg, dispatch.
  if next(self.subcommands) then
    -- Find the first non-flag arg.
    for j, a in ipairs(argv) do
      if a:sub(1, 1) ~= "-" then
        if self.subcommands[a] then
          local sub = self.subcommands[a]
          local rest = {}
          for k = 1, j - 1 do table.insert(rest, argv[k]) end
          for k = j + 1, #argv do table.insert(rest, argv[k]) end
          local sub_result, err = sub:parse(rest)
          if err then return nil, err end
          sub_result.command = a
          return sub_result
        else
          return nil, "unknown command: " .. a
        end
      elseif a == "--help" or a == "-h" then
        result.flags.help = true
        return result
      end
    end
    -- No subcommand given.
    return result
  end

  while i <= #argv do
    local a = argv[i]
    if a == "--" then
      -- Everything after is positional.
      for j = i + 1, #argv do
        result.positionals[positional_idx] = argv[j]
        positional_idx = positional_idx + 1
      end
      break
    elseif a:sub(1, 2) == "--" then
      -- Long option/flag.
      local rest = a:sub(3)
      local eq = rest:find("=")
      local name, value
      if eq then
        name = rest:sub(1, eq - 1)
        value = rest:sub(eq + 1)
      else
        name = rest
      end

      if name == "help" then
        result.flags.help = true
      elseif self.flags[name] then
        if value then
          return nil, "flag does not take a value: --" .. name
        end
        result.flags[name] = true
      elseif self.options[name] then
        if not value then
          i = i + 1
          value = argv[i]
          if not value then
            return nil, "option requires a value: --" .. name
          end
        end
        result.options[name] = value
      else
        return nil, "unknown option: --" .. name
      end
    elseif a:sub(1, 1) == "-" and #a > 1 then
      -- Short option(s).
      local j = 2
      while j <= #a do
        local ch = a:sub(j, j)
        if ch == "h" then
          result.flags.help = true
          j = j + 1
        else
          local name, kind = find_short(self, ch)
          if not name then
            return nil, "unknown short option: -" .. ch
          end
          if kind == "flag" then
            result.flags[name] = true
            j = j + 1
          else
            -- Option with value: rest of cluster or next arg.
            local rest = a:sub(j + 1)
            if rest ~= "" then
              result.options[name] = rest
              break
            else
              i = i + 1
              local v = argv[i]
              if not v then
                return nil, "option requires a value: -" .. ch
              end
              result.options[name] = v
              break
            end
          end
        end
      end
    else
      -- Positional.
      result.positionals[positional_idx] = a
      positional_idx = positional_idx + 1
    end
    i = i + 1
  end

  -- Map positionals onto declared names.
  for idx, decl in ipairs(self.positionals) do
    if decl.rest then
      local rest = {}
      for k = idx, positional_idx - 1 do
        table.insert(rest, result.positionals[k])
      end
      result[decl.name] = rest
      break
    else
      local v = result.positionals[idx]
      if v == nil and decl.required and not result.flags.help then
        return nil, "missing argument: " .. decl.name
      end
      result[decl.name] = v or decl.default
    end
  end

  -- Defaults for options.
  for name, opt in pairs(self.options) do
    if result.options[name] == nil and opt.default ~= nil then
      result.options[name] = opt.default
    end
    if opt.required and result.options[name] == nil and not result.flags.help then
      return nil, "missing required option: --" .. name
    end
  end

  return result
end

-- Parse and exit on error or --help. Convenience for top-level use.
function Parser:parse_or_exit(argv)
  local result, err = self:parse(argv)
  if err then
    io.stderr:write("error: " .. err .. "\n\n")
    print(self:format_help())
    os.exit(1)
  end
  if result.flags.help then
    print(self:format_help())
    os.exit(0)
  end
  return result
end

return M
