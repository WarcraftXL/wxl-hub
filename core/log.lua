--[[
  The log file, for a program that has no console to print to.

  The shipped binary is a GUI-subsystem PE, so `print` writes into nothing. That would be a detail if
  the application ran in one Lua state, and it does not: the window owns one, the HTTP server owns
  another on its own thread, and every job worker gets a fresh one. Redirecting `print` in the state
  that happens to boot leaves the two that do the actual work writing into the void, which is why a
  hub that died on a click left a log containing one line.

  So this is installed per state rather than once. Each carries a tag, because two states writing to
  one file interleave and a line nobody can attribute is barely better than no line.

  Opened for append, never truncated. A crash is followed by a relaunch within seconds, and a log
  that starts empty on every launch destroys the evidence for the run anyone actually wants to read.
]]

local M = {}

-- Past this, the file is rolled once. Nothing rotates on a schedule: the only moment it can grow is
-- a write, and the only moment worth checking is a fresh launch.
local MAX = 1024 * 1024

local handle

local function roll(path)
  local fd = io.open(path, "rb")
  if not fd then return end
  local size = fd:seek("end")
  fd:close()
  if size and size > MAX then
    os.remove(path .. ".1")
    os.rename(path, path .. ".1")
  end
end

--- Point `print` at a file for this Lua state. Safe to call again; the first call wins.
function M.install(path, tag)
  if handle then return true end
  roll(path)
  handle = io.open(path, "a")
  if not handle then return false end

  local prefix = ("%-6s"):format(tag or "?")
  local write, concat, date = handle.write, table.concat, os.date

  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    write(handle, date("%H:%M:%S "), prefix, " ", concat(parts, "\t"), "\n")
    -- Flushed per line and not per buffer. A buffered line is exactly the line that is lost when the
    -- process dies, and the process dying is the case this file exists for.
    handle:flush()
  end
  return true
end

--- Mark the start of a run, so appended sessions can be told apart at a glance.
function M.banner(text)
  print(("%s  %s  %s"):format(("="):rep(12), text, ("="):rep(12)))
end

return M
