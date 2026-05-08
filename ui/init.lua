-- ui: terminal output helpers for CC programs.
--
-- A small set of routines every CLI ends up writing -- centralized so they
-- behave the same everywhere and Just Work outside CC: the color helpers
-- fall back to plain text when term/colors aren't available, so tests and
-- non-CC environments still see the right strings.
--
-- Provides:
--   ui.color(name, text)   -- write text in a color, restoring the previous one
--   ui.ok / info / warn / fail (msg)  -- print msg in the conventional color
--   ui.confirm(prompt, opts)          -- [Y/n] yes-flag-honoring confirm
--   ui.with_spinner(label, work)      -- run work() with a live spinner
--                                        beside `label`. Spinner stays animated
--                                        even when work() blocks on HTTP, by
--                                        running the two in parallel.

local M = {}

M.VERSION = "1.0.0"

-- ---------------------------------------------------------------------------
-- Color
-- ---------------------------------------------------------------------------

local function has_term_color()
  return _G.term and _G.colors and _G.term.setTextColor
end

function M.color(name, text)
  if has_term_color() then
    local prev = _G.term.getTextColor and _G.term.getTextColor()
    _G.term.setTextColor(_G.colors[name] or _G.colors.white)
    io.write(text)
    if prev then _G.term.setTextColor(prev) end
  else
    io.write(text)
  end
end

function M.ok(msg)   M.color("green",  msg .. "\n") end
function M.info(msg) M.color("white",  msg .. "\n") end
function M.warn(msg) M.color("yellow", msg .. "\n") end
function M.fail(msg) M.color("red",    msg .. "\n") end

-- ---------------------------------------------------------------------------
-- Confirm prompt
-- ---------------------------------------------------------------------------

-- ui.confirm("Continue?", { yes_flag = true })
-- Returns true if the user accepts (or yes_flag is set), false otherwise.
function M.confirm(prompt, opts)
  opts = opts or {}
  if opts.yes_flag then return true end
  io.write(prompt .. " [Y/n]: ")
  io.flush()
  local response = io.read("*l") or ""
  response = response:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return response == "" or response == "y" or response == "yes"
end

-- ---------------------------------------------------------------------------
-- Spinner
-- ---------------------------------------------------------------------------

local SPINNER_CHARS = { "|", "/", "-", "\\" }
local SPINNER_TICK  = 0.1  -- seconds between frames

-- Render the current spinner state to the terminal. Uses \r so we always
-- overwrite the same physical line. Falls back gracefully if term APIs
-- aren't available.
local function draw_spinner(char, label)
  if has_term_color() and _G.term.clearLine then
    -- Pull the cursor home, clear the line, write fresh. Avoids leftover
    -- characters when label length shrinks between frames.
    local _, y = _G.term.getCursorPos()
    _G.term.setCursorPos(1, y)
    _G.term.clearLine()
    io.write(char .. " " .. label)
  else
    io.write("\r" .. char .. " " .. label)
  end
  io.flush()
end

local function clear_spinner_line()
  if has_term_color() and _G.term.clearLine then
    local _, y = _G.term.getCursorPos()
    _G.term.setCursorPos(1, y)
    _G.term.clearLine()
  else
    io.write("\r")
    io.flush()
  end
end

-- Run `work()` while a spinner ticks beside `label`. The spinner advances
-- every SPINNER_TICK seconds independently of work(), so even a stalled
-- HTTP fetch keeps the animation alive (it doesn't fool you into thinking
-- the program is doing useful work, but it does prove the program hasn't
-- crashed).
--
-- Implementation: two coroutines, scheduled by parallel.waitForAny. The
-- first runs work() and stores its results. The second loops on
-- os.sleep(SPINNER_TICK), redrawing the spinner each tick, until the work
-- coroutine signals completion via a shared flag. When parallel.waitForAny
-- returns (the work coroutine ended), we clear the spinner line and pass
-- the captured results back to the caller.
--
-- If `parallel` or `os.sleep` isn't available (running outside CC, e.g.
-- in unit tests), fall back to running work() directly with no animation.
function M.with_spinner(label, work)
  if not _G.parallel or not _G.os or not _G.os.sleep then
    return work()
  end

  local results = nil
  local done = false

  _G.parallel.waitForAny(
    function()
      results = table.pack(work())
      done = true
    end,
    function()
      local i = 1
      while not done do
        draw_spinner(SPINNER_CHARS[i], label)
        i = i % #SPINNER_CHARS + 1
        _G.os.sleep(SPINNER_TICK)
      end
    end
  )

  clear_spinner_line()
  if results then
    return table.unpack(results, 1, results.n)
  end
end

return M
