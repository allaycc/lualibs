-- log: leveled logger for CC programs.
--
-- Levels: DEBUG (0), INFO (1), WARN (2), ERROR (3).
-- The active level is read from CC's settings API (key "log.level"); falls
-- back to INFO. Each level has its own output color when running in CC.

local M = {}

M.VERSION = "1.0.0"

M.LEVELS = {
  DEBUG = 0,
  INFO  = 1,
  WARN  = 2,
  ERROR = 3,
}

local LEVEL_NAMES = {
  [0] = "DEBUG",
  [1] = "INFO",
  [2] = "WARN",
  [3] = "ERROR",
}

local LEVEL_COLORS
if colors then
  LEVEL_COLORS = {
    [0] = colors.lightGray,
    [1] = colors.white,
    [2] = colors.yellow,
    [3] = colors.red,
  }
end

local current_level = nil
local prefix = nil

-- Read the active level from CC settings, or fall back.
local function active_level()
  if current_level ~= nil then return current_level end
  if settings and settings.get then
    local v = settings.get("log.level")
    if type(v) == "number" then return v end
    if type(v) == "string" then
      local key = v:upper()
      if M.LEVELS[key] then return M.LEVELS[key] end
    end
  end
  return M.LEVELS.INFO
end

function M.set_level(level)
  if type(level) == "string" then
    level = M.LEVELS[level:upper()]
  end
  assert(type(level) == "number", "log.set_level: level must be number or name")
  current_level = level
  if settings and settings.set and settings.save then
    settings.set("log.level", level)
    settings.save()
  end
end

function M.get_level()
  return active_level()
end

-- Set a prefix that's prepended to every line. Useful for per-module loggers.
function M.set_prefix(p)
  prefix = p
end

local function emit(level, msg)
  if level < active_level() then return end

  local line = msg
  if prefix then
    line = "[" .. prefix .. "] " .. line
  end

  if term and term.setTextColor and LEVEL_COLORS then
    local prev = term.getTextColor and term.getTextColor()
    term.setTextColor(LEVEL_COLORS[level] or colors.white)
    print(line)
    if prev then term.setTextColor(prev) end
  elseif level == M.LEVELS.ERROR and printError then
    printError(line)
  else
    print(line)
  end
end

function M.debug(msg) emit(M.LEVELS.DEBUG, msg) end
function M.info(msg)  emit(M.LEVELS.INFO,  msg) end
function M.warn(msg)  emit(M.LEVELS.WARN,  msg) end
function M.error(msg) emit(M.LEVELS.ERROR, msg) end

-- Format-and-emit conveniences.
function M.debugf(fmt, ...) M.debug(string.format(fmt, ...)) end
function M.infof(fmt, ...)  M.info(string.format(fmt, ...))  end
function M.warnf(fmt, ...)  M.warn(string.format(fmt, ...))  end
function M.errorf(fmt, ...) M.error(string.format(fmt, ...)) end

return M
