--[[
  The hub's database handle.

  Schema changes are .sql files applied by core.migrate; nothing here knows about them. See
  core/migrations/ and modules/<id>/migrations/.
]]

local sqlite = require("ffi.sqlite")

local M = {}

local handle

--- Open (or create) the database.
function M.open(path, deps_dir)
  sqlite.setup(deps_dir or "deps/sqlite")
  handle = sqlite.open(path)
  -- Off by default in SQLite, and per-connection rather than stored in the file. Without it every
  -- REFERENCES clause in the migrations is a comment: deleting a parent row would leave its children
  -- behind, pointing at nothing.
  handle:exec("PRAGMA foreign_keys = ON")
  return M
end

function M.handle()
  return assert(handle, "core.db: open() has not been called")
end

-- Thin pass-throughs, so a module never has to reach for the handle itself.
function M.row(...)     return M.handle():row(...) end
function M.rows(...)    return M.handle():rows(...) end
function M.run(...)     return M.handle():run(...) end
function M.scalar(...)  return M.handle():scalar(...) end
function M.exec(...)    return M.handle():exec(...) end

function M.transaction(fn)
  return M.handle():transaction(fn)
end

function M.close()
  if handle then handle:close(); handle = nil end
end

return M
