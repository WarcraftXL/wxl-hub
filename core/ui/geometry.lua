--[[
  Where the window was, so it opens there again.

  The one habit that separates an application from a page in a frame: a page opens where the browser
  puts it, software opens where you left it. Nothing else in the hub needed this, which is why it
  went unnoticed for so long.

  A file rather than a row in `setting`. The window is the main thread's, and the main thread is the
  one with no database: the connection is opened on the server thread and is not shared. It is also
  not the kind of thing a profile owns, since a second profile does not deserve a second window.

  Saved on the way past rather than on the way out. There is no close hook to hang this on: the
  message loop returns after the window has already been destroyed, and asking a destroyed window
  where it was answers nothing. So the page reports whenever it is in a position to know something
  changed, and a run that ends by being killed still leaves the last thing it saw.
]]

local release = require("core.release")

local M = {}

-- Anything smaller is a window nobody meant to leave behind, and restoring it would hand someone a
-- hub they have to fix before they can use it.
local MIN_W, MIN_H = 900, 600

--- What was written down last time, or nil.
function M.read()
  local fd = io.open(release.window(), "r")
  if not fd then return nil end
  local line = fd:read("*l") or ""
  fd:close()

  local x, y, w, h, max = line:match("^(-?%d+) (-?%d+) (%d+) (%d+) ([01])$")
  if not x then return nil end

  w, h = tonumber(w), tonumber(h)
  if w < MIN_W or h < MIN_H then return nil end

  return { x = tonumber(x), y = tonumber(y), w = w, h = h, maximised = max == "1" }
end

--- Remember `g`. Returns whether anything was written.
--
-- The comparison is the point: this is called on every navigation and on every resize that settles,
-- and a file rewritten on each of those is a file being written for no reason most of the time.
local last

function M.write(g)
  if not g or g.w < MIN_W or g.h < MIN_H then return false end

  local line = ("%d %d %d %d %d"):format(g.x, g.y, g.w, g.h, g.maximised and 1 or 0)
  if line == last then return false end

  local fd = io.open(release.window(), "w")
  if not fd then return false end
  fd:write(line, "\n")
  fd:close()
  last = line
  return true
end

return M
