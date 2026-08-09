--[[
  Starting the client.

  The hub is a launcher, and this is the part that earns the word. It runs Wow.exe from the folder
  the profile points at, with that folder as the working directory, because that is what the core
  resolves `Extensions\` against.

  Detached on purpose: the game outlives the hub. Closing the window must not take the client with
  it, and the hub has no business staying alive to babysit a process it does not own.
]]

local uv     = require("uv")
local client = require("core.game.client")

local M = {}

local function rmtree(dir)
  local scan = uv.fs_scandir(dir)
  if not scan then return 0 end
  local n = 0
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then break end
    local p = dir .. "/" .. name
    if kind == "directory" then n = n + rmtree(p)
    else if uv.fs_unlink(p) then n = n + 1 end end
  end
  uv.fs_rmdir(dir)
  return n
end

--- Delete the client's own cache folder.
--
-- Not ours and not the hub's: this is the client's `Cache/`, which the game rebuilds on the next
-- start. Clearing it is the standard cure for a client that has gone strange after a data change,
-- which is exactly what installing an extension is.
function M.clear_client_cache(path)
  local dir = path .. "/Cache"
  if not uv.fs_stat(dir) then return 0 end
  return rmtree(dir)
end

--- Start the client. Returns a table describing what happened, never raising.
--
-- opts.clear_cache -> wipe Cache/ first
function M.start(path, opts)
  opts = opts or {}

  local report = client.inspect(path)
  if not report.ok then
    return { ok = false, why = "this profile has no usable client set" }
  end

  local cleared
  if opts.clear_cache then
    cleared = M.clear_client_cache(report.path)
  end

  local handle, err = uv.spawn(report.path .. "/Wow.exe", {
    cwd      = report.path,
    -- Without this the client dies with the hub, which is the opposite of launching it.
    detached = true,
    -- Nothing is read back, and an inherited console would keep a handle open on a process we are
    -- about to stop watching.
    stdio    = { nil, nil, nil },
  }, function() end)

  if not handle then
    return { ok = false, why = "the client would not start: " .. tostring(err) }
  end

  -- Released immediately: keeping a reference would tie the game's lifetime to this loop.
  uv.unref(handle)

  return { ok = true, cleared = cleared, path = report.path }
end

return M
