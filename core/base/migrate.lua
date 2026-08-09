--[[
  Migrations as .sql files, tracked by an `updates` table.

  SQL lives in .sql files so it reads and diffs as SQL, adding a migration is dropping a file in,
  and what has run is a list of names rather than a version integer nobody can decode.

  Files are applied in filename order, so they are named `001_thing.sql`. Each is one transaction: a
  file that fails leaves nothing behind and stays unapplied.

  Applied files are recorded with a hash. Editing one that has already run is a mistake, because
  there is no way to make an existing database match it, so the mismatch is reported rather than
  silently ignored or blindly re-run.
]]

local uv   = require("uv")
local ossl = require("openssl")

local M = {}

local db

local BOOTSTRAP = [[
CREATE TABLE IF NOT EXISTS updates (
  path       TEXT PRIMARY KEY,
  hash       TEXT NOT NULL,
  applied_at INTEGER NOT NULL,
  ms         INTEGER NOT NULL
)]]

function M.init(handle)
  db = handle
  db:exec(BOOTSTRAP)
  return M
end

local function read(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local body = fd:read("*a")
  fd:close()
  return body
end

local function sql_files(dir)
  local out = {}
  local req = uv.fs_scandir(dir)
  if not req then return out end
  while true do
    local name = uv.fs_scandir_next(req)
    if not name then break end
    if name:match("%.sql$") then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

--- Apply every pending file in `dir`. Returns a list of { path, status, ms }.
--
-- status is "applied", "skipped" (already recorded, hash matches) or "changed" (recorded but the
-- file on disk no longer matches what ran).
function M.run(dir)
  assert(db, "core.migrate: init() has not been called")
  local results = {}

  for _, name in ipairs(sql_files(dir)) do
    local path = dir .. "/" .. name
    local body = read(path)
    if body then
      local hash = ossl.digest.digest("sha256", body)
      local row  = db:row("SELECT hash FROM updates WHERE path = ?", path)

      if row and row.hash == hash then
        results[#results + 1] = { path = path, status = "skipped" }

      elseif row then
        results[#results + 1] = { path = path, status = "changed" }
        print("migration edited after it ran: " .. path)

      else
        -- hrtime rather than uv.now: the loop's clock only moves when the loop does, so a migration
        -- run during startup would be timed against whenever the last tick happened to be.
        local started = uv.hrtime()
        db:transaction(function() db:exec(body) end)
        local ms = math.floor((uv.hrtime() - started) / 1e6)

        db:run([[INSERT INTO updates (path, hash, applied_at, ms) VALUES (?, ?, ?, ?)]],
               path, hash, os.time(), ms)
        results[#results + 1] = { path = path, status = "applied", ms = ms }
      end
    end
  end

  return results
end

--- Everything applied so far, newest first, for the settings page.
function M.applied()
  return db:rows("SELECT path, applied_at, ms FROM updates ORDER BY applied_at DESC, path")
end

return M
