--[[
  Which build this is, and where its neighbours live.

  Two identities, deliberately separate. The **build** is a stamp, unique per build because it names
  the folder the bundle unpacks into; two builds must never share a cache. The **version** is the
  release this build calls itself, which is what a person reads and what the launcher compares.

  Running from the repository there is no VERSION file, which is exactly the test for it: `installed`
  is what tells the launcher there is nothing here to manage.
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
M.version = slurp("RELEASE") or "dev"

--- True when running from a tree the executable unpacked, rather than from a checkout.
M.installed = M.build ~= nil

local root = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP") or "."):gsub("\\", "/")

M.hub = root .. "/WarcraftXL/hub"

--- Where the application binary lives, as opposed to the launcher the user keeps wherever they put
--- it. A fixed path is the point: the launcher has to be able to write over it without asking anyone
--- where it went, and the only process that could be holding it is the one being replaced.
M.bin     = M.hub .. "/bin"
M.hub_exe = M.bin .. "/hub.exe"
M.hub_ver = M.bin .. "/hub.version"

--- Which of the two this process is.
--
-- Decided by where the executable sits rather than by a flag, because a flag can be lost by whoever
-- creates the shortcut and an environment variable is inherited by every child the hub ever spawns,
-- the game client included. A checkout is always the application: there is no launcher to be.
function M.role()
  if not M.installed then return "hub" end
  local exe = (uv.exepath():gsub("\\", "/"):lower())
  return exe == M.hub_exe:lower() and "hub" or "launcher"
end

--- Where we are actually running from, with separators normalised so it can be compared to the paths
--- above.
function M.live()
  return (uv.cwd():gsub("\\", "/"))
end

--- The database, and the log.
--
-- Both sit beside the version folders rather than inside one. The folders are a cache the next build
-- replaces; these two are the user's, and a log split across them is the launcher's half of a
-- startup filed separately from the application's.
function M.db()  return M.installed and (M.hub .. "/hub.db")  or "hub.db"  end
function M.log() return M.installed and (M.hub .. "/hub.log") or "hub.log" end

--- Where the window was left. Beside the two above, and a file rather than a row in the database:
--- the window belongs to the thread that has no database, and this is a fact about this screen and
--- this machine rather than anything a profile owns.
function M.window() return M.installed and (M.hub .. "/window") or "window" end

return M
