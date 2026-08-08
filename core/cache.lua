--[[
  Time-to-live cache on SQLite.

  Every remote thing the hub reads goes through here: the store index, listings, descriptions, and
  later whatever the heavier tools produce. Two properties matter more than speed.

  A stale entry is kept, not deleted. `get` refuses to return it and `stale` will, so when the
  network is down the hub shows yesterday's catalogue with a note instead of an empty page. Deleting on expiry
  would throw away the only copy at exactly the moment it is needed.

  The stored ETag rides along, so a refresh after expiry usually costs a 304 and no body.
]]

local M = {}

-- Half an hour. Long enough that opening the hub twice in a row does not re-fetch, short enough that
-- a manifest pushed a moment ago shows up without anyone clearing anything.
M.DEFAULT_TTL = 30 * 60

-- Schema lives in core/migrations/001_cache.sql.

local db

function M.init(handle)
  db = handle
  return M
end

--- Fresh value, or nil. Second return is its age in seconds.
function M.get(key)
  local row = db:row("SELECT value, fetched_at, ttl FROM cache WHERE key = ?", key)
  if not row then return nil end
  local age = os.time() - row.fetched_at
  if age > row.ttl then return nil, age end
  return row.value, age
end

--- Value regardless of age, for the offline path. Second return says whether it is past its TTL.
function M.stale(key)
  local row = db:row("SELECT value, fetched_at, ttl FROM cache WHERE key = ?", key)
  if not row then return nil end
  local age = os.time() - row.fetched_at
  return row.value, age > row.ttl, age
end

--- How old the stored copy is right now, in seconds, whatever its life. nil when there is none.
--
-- Asked for rather than remembered: an age recorded when something was read is only true for the
-- instant it was read, and a screen showing it an hour later is confidently wrong.
function M.age(key)
  local row = db:row("SELECT fetched_at FROM cache WHERE key = ?", key)
  return row and (os.time() - row.fetched_at) or nil
end

function M.etag(key)
  local row = db:row("SELECT etag FROM cache WHERE key = ?", key)
  return row and row.etag or nil
end

function M.put(key, value, ttl, etag)
  db:run([[INSERT INTO cache (key, value, etag, fetched_at, ttl) VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET
             value = excluded.value, etag = excluded.etag,
             fetched_at = excluded.fetched_at, ttl = excluded.ttl]],
         key, value, etag, os.time(), ttl or M.DEFAULT_TTL)
end

--- Refresh the timestamp without rewriting the body, for a 304.
function M.touch(key, ttl)
  db:run("UPDATE cache SET fetched_at = ?, ttl = ? WHERE key = ?",
         os.time(), ttl or M.DEFAULT_TTL, key)
end

function M.forget(key)
  db:run("DELETE FROM cache WHERE key = ?", key)
end

--- Drop everything already past its TTL. Housekeeping, not correctness: nothing depends on it
--- having run.
function M.sweep()
  return db:run("DELETE FROM cache WHERE ? - fetched_at > ttl * 4", os.time())
end

function M.summary()
  return db:rows([[SELECT key, length(value) AS bytes, ? - fetched_at AS age, ttl,
                          (? - fetched_at > ttl) AS expired
                   FROM cache ORDER BY fetched_at DESC]], os.time(), os.time())
end

return M
