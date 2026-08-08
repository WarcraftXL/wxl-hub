--[[
  The notification centre.

  What earns a bell is an event you were not looking at when it happened: an install that failed
  while you were on another page, an update that appeared during the boot fetch. Anything you are
  watching already reports itself where you are watching it, and does not belong here as well.

  A notice about something already noticed replaces it rather than stacking. Five failures of one
  install is one problem, and a bell that counts them is a bell people stop reading.
]]

local db = require("core.db")

local M = {}

local KEEP = 100

--- Raise a notice. `ref` scopes the replacement: same kind and same ref, same notice.
function M.raise(n)
  db.transaction(function()
    if n.ref then
      db.run("DELETE FROM notification WHERE kind = ? AND ref = ?", n.kind, n.ref)
    end
    db.run([[INSERT INTO notification (kind, ref, level, title, body, href, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)]],
           n.kind, n.ref, n.level or "info", n.title, n.body, n.href, os.time())

    -- Trimmed here rather than swept on a timer: the only moment the list can grow is this one.
    db.run([[DELETE FROM notification WHERE id NOT IN
             (SELECT id FROM notification ORDER BY created_at DESC, id DESC LIMIT ?)]], KEEP)
  end)
end

--- Raise it unless the very same notice is already there, read or not.
--
-- For notices that are restated rather than new: the update check runs at every launch and finds the
-- same pending version each time, and re-raising would mark it unread again on every start until the
-- user gave in.
function M.raise_once(n)
  local seen = db.row([[SELECT id FROM notification
                        WHERE kind = ? AND ref IS ? AND title = ? AND body IS ?]],
                      n.kind, n.ref, n.title, n.body)
  if seen then return false end
  M.raise(n)
  return true
end

function M.unread()
  local row = db.row("SELECT COUNT(*) AS n FROM notification WHERE read_at IS NULL")
  return row and row.n or 0
end

function M.recent(n)
  return db.rows([[SELECT * FROM notification ORDER BY created_at DESC, id DESC LIMIT ?]], n or 12)
end

--- Marks everything read. Called when the panel is opened, because that is what reading is.
function M.mark_read()
  db.run("UPDATE notification SET read_at = ? WHERE read_at IS NULL", os.time())
end

function M.clear()
  db.run("DELETE FROM notification")
end

--- Drop one, so the rest can be kept. Dismissing is the opposite of clearing: it is how a list stays
--- useful without being emptied every time one line in it stops mattering.
function M.dismiss(id)
  db.run("DELETE FROM notification WHERE id = ?", tonumber(id))
end

--- How long ago, in the shortest form that is still true.
function M.ago(at)
  local d = os.time() - (at or 0)
  if d < 60 then return "just now" end
  if d < 5400 then return math.floor(d / 60) .. "m ago" end
  if d < 172800 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

return M
