--[[
  Which build this is, and where its neighbours live.

  Two identities, deliberately separate. The **build** is the executable's stamp, unique per build
  because it names the folder the bundle unpacks into; two builds must never share a cache. The
  **payload** is the version of the Lua tree currently running, which the updater can move without
  the executable changing. In a shipped tree they are written by the same build; in an updated tree
  the build still describes the container and the payload no longer describes what shipped in it.

  Running from the repository there is no VERSION file, which is exactly the test for it: nothing
  here should be doing anything during development, and `M.installed` is what says so.
]]

local uv = require("uv")

local M = {}

local function slurp(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local s = (fd:read("*l") or ""):gsub("%s+$", "")
  fd:close()
  return s ~= "" and s or nil
end

M.build   = slurp("VERSION")
M.payload = slurp("PAYLOAD") or "dev"

--- True when running from a tree the executable unpacked, which is the only case the updater applies
--- to. From a checkout there is nothing to replace and no folder to replace it in.
M.installed = M.build ~= nil

local root = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP") or "."):gsub("\\", "/")

M.hub     = root .. "/WarcraftXL/hub"
M.updates = M.hub .. "/updates"

--- The tree the executable itself unpacked, which is the base every update is built on top of and
--- the one the bootstrap falls back to.
M.shipped = M.build and (M.hub .. "/" .. M.build) or nil

--- Where we are actually running from, with separators normalised so it can be compared to the
--- paths above.
function M.live()
  return (uv.cwd():gsub("\\", "/"))
end

--- The database.
--
-- Beside the version folders rather than inside one, because it is the user's data and the folders
-- are a cache. Kept in a version folder it would be discarded by the next build: profiles, client
-- paths and the ledger of what is installed where would all come back empty after an update, and
-- the old copy would be sitting in a folder named after a build nobody can identify.
--
-- From a checkout it stays local, which is what makes a development database something you can
-- delete by hand without touching whatever the installed hub is using.
function M.db()
  return M.installed and (M.hub .. "/hub.db") or "hub.db"
end

return M
