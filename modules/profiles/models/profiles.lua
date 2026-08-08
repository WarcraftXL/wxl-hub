--[[
  Settings, per profile where that means something.

  A profile holds the client you launch and the paths that go with it. Everything else describes
  this machine and this user, follows them across profiles, and lives in the flat `setting` table.
  Which side a key sits on is declared once, in `scoped`, so no caller has to know: `get("developer")`
  and `get("client_path")` read the same to everyone above this file.

  At least one profile always exists. The migration creates it and `remove` refuses to delete the
  last one, so nothing below has to handle the case where a scoped value has nowhere to live.

  Defaults live here and are never written on read: a value the user has not chosen must stay
  unchosen, so that changing a default later actually reaches the people who never touched it.
]]

local db = require("core.db")

local M = {}

M.scoped = {
  client_path = true,
  core_path   = true,
  autolaunch  = true,
  clear_cache = true,
}

M.defaults = {
  active_profile = "1",
  -- Off. It adds the author-facing half of the app to the navigation, which is noise for everyone
  -- who came to install modules rather than write them.
  developer      = "0",
  -- Cleared by the first-run form once it has been answered. Global rather than per profile: it is
  -- a fact about this installation, and a second profile is not a second first run.
  onboarded      = "0",
  -- Ask which profile to use at startup. Off once someone has said "remember my choice", and
  -- turned back on from the profiles page when they change their mind.
  ask_profile    = "1",
  client_path    = "",
  core_path      = "",
  autolaunch     = "1",
  -- Wiping the client's own Cache/ before launch. Off by default: it is a repair, not a routine,
  -- and it costs the client a slower first load every single time.
  clear_cache    = "0",
}

local NAME_MAX = 40

-- ------------------------------------------------------------------ profiles ----

--- The active profile. Falls back to the lowest id, so an `active_profile` left pointing at a
--- deleted row resolves to something real instead of stranding every scoped value.
function M.active()
  local row = db.row("SELECT value FROM setting WHERE key = 'active_profile'")
  return db.row("SELECT id, name FROM profile WHERE id = ?", tonumber(row and row.value) or 0)
      or db.row("SELECT id, name FROM profile ORDER BY id LIMIT 1")
end

function M.profiles()
  return db.rows("SELECT id, name FROM profile ORDER BY name")
end

function M.activate(id)
  db.run([[INSERT INTO setting (key, value) VALUES ('active_profile', ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value]], tostring(id))
end

local function clean(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil, "a profile needs a name" end
  if #name > NAME_MAX then return nil, "at most " .. NAME_MAX .. " characters" end
  return name
end

--- Returns the new row, or nil plus a message fit to show the user.
--
-- The clash is looked up rather than left to the UNIQUE constraint: a driver that reports a
-- constraint failure as a return value instead of an error would otherwise read as success.
function M.create(name)
  local clean_name, why = clean(name)
  if not clean_name then return nil, why end
  if db.row("SELECT id FROM profile WHERE name = ?", clean_name) then
    return nil, "that name is taken"
  end
  db.run("INSERT INTO profile (name) VALUES (?)", clean_name)
  return db.row("SELECT id, name FROM profile WHERE name = ?", clean_name)
end

function M.rename(id, name)
  local clean_name, why = clean(name)
  if not clean_name then return nil, why end
  if db.row("SELECT id FROM profile WHERE name = ? AND id <> ?", clean_name, id) then
    return nil, "that name is taken"
  end
  db.run("UPDATE profile SET name = ? WHERE id = ?", clean_name, id)
  return clean_name
end

function M.remove(id)
  local row = db.row("SELECT COUNT(*) AS n FROM profile")
  if (row and row.n or 0) <= 1 then return nil, "the last profile cannot be deleted" end

  db.run("DELETE FROM profile WHERE id = ?", id)
  -- Its settings go with it, through the foreign key core.db enables. Re-pinning the pointer is
  -- what `active` would resolve to anyway, written down so the next profile created does not
  -- silently inherit the deleted one's slot.
  M.activate(M.active().id)
  return true
end

-- ------------------------------------------------------------------ values ----

local function profile_id()
  local p = M.active()
  return p and p.id
end

function M.get(key)
  local row
  if M.scoped[key] then
    row = db.row("SELECT value FROM profile_setting WHERE profile_id = ? AND key = ?",
                 profile_id(), key)
  else
    row = db.row("SELECT value FROM setting WHERE key = ?", key)
  end
  -- An empty string is a chosen value, not an absent one, so this tests the row rather than truth.
  if row then return row.value end
  return M.defaults[key]
end

function M.set(key, value)
  value = tostring(value)
  if M.scoped[key] then
    db.run([[INSERT INTO profile_setting (profile_id, key, value) VALUES (?, ?, ?)
             ON CONFLICT(profile_id, key) DO UPDATE SET value = excluded.value]],
           profile_id(), key, value)
  else
    db.run([[INSERT INTO setting (key, value) VALUES (?, ?)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value]], key, value)
  end
end

function M.bool(key)
  return M.get(key) == "1"
end

--- Flips a boolean and returns its new state.
function M.toggle(key)
  local now = not M.bool(key)
  M.set(key, now and "1" or "0")
  return now
end

function M.all()
  local out = {}
  for k in pairs(M.defaults) do out[k] = M.get(k) end
  return out
end

return M
