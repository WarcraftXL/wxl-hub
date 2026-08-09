--[[
  What the user last opened.

  It lives in core rather than in a module because it spans them: the store records a listing, the
  workspace will record a tool, and the home page shows both. A module writes to it through `record`
  and never reads another module's rows directly.

  `icon` holds a name from core/ui/icons.lua, never markup. A row is data that outlives the build
  that wrote it, and a stored `<svg>` would still be the old drawing after the set is restyled.

  Backed by SQLite, so the list survives a restart, which is the only reason it is worth having.
]]

local db = require("core.base.db")

local M = {}

-- Schema lives in core/migrations/002_history.sql.

local KEEP = 24

--- Record a visit. Re-visiting moves an entry to the front rather than duplicating it.
function M.record(entry)
  db.run([[INSERT INTO history (href, kind, ref, title, subtitle, icon, seen_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(href) DO UPDATE SET
             title = excluded.title, subtitle = excluded.subtitle,
             icon = excluded.icon, seen_at = excluded.seen_at]],
         entry.href, entry.kind, entry.ref, entry.title, entry.subtitle, entry.icon, os.time())

  -- Trimmed on write: a table that only ever grows is a slow leak nobody notices.
  db.run([[DELETE FROM history WHERE href NOT IN
             (SELECT href FROM history ORDER BY seen_at DESC LIMIT ?)]], KEEP)
end

local function ago(seconds)
  if seconds < 90 then return "just now" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  if seconds < 172800 then return "yesterday" end
  return math.floor(seconds / 86400) .. "d ago"
end

function M.recent(limit)
  local now = os.time()
  local rows = db.rows("SELECT * FROM history ORDER BY seen_at DESC LIMIT ?", limit or 8)
  for _, r in ipairs(rows) do
    r.when = ago(now - r.seen_at)
    r.id = r.ref or r.title
  end
  return rows
end

function M.clear()
  db.run("DELETE FROM history")
end

return M
