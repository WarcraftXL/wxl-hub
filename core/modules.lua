--[[
  Module discovery and mounting.

  A module is a directory under modules/ containing module.lua. The loader reads the declaration,
  applies the module's migrations, lets it register routes, and adds it to the navigation. Adding a
  feature is dropping a folder in; nothing here holds a list of what exists.

  Load order is by the `order` a module declares, then by id. Never by directory order, which is
  whatever the filesystem felt like and would make navigation shuffle between machines.

  A module that fails to load is recorded and skipped. One broken third-party tool must not stop the
  hub from starting, and the failure has to be visible rather than silently absent.
]]

local uv       = require("uv")
local migrate  = require("core.migrate")
local view     = require("core.view")
local mediator = require("core.mediator")

local M = { loaded = {}, failed = {} }

local ROOT = "modules"

local function scan(dir)
  local out = {}
  local req = uv.fs_scandir(dir)
  if not req then return out end
  while true do
    local name, kind = uv.fs_scandir_next(req)
    if not name then break end
    if kind == "directory" or uv.fs_stat(dir .. "/" .. name).type == "directory" then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function load_one(id)
  local ok, decl = pcall(dofile, ROOT .. "/" .. id .. "/module.lua")
  if not ok or type(decl) ~= "table" then
    return nil, "module.lua did not return a table: " .. tostring(decl)
  end

  decl.id    = decl.id or id
  decl.dir   = ROOT .. "/" .. id
  decl.order = decl.order or 100
  decl.view  = view.for_module(decl.id)

  if decl.id ~= id then
    return nil, ("declares id %q but lives in modules/%s"):format(decl.id, id)
  end
  return decl
end

--- Which declared tools are missing, so a module can be shown as unavailable with a reason instead
--- of failing in the middle of a job.
local function missing_tools(decl, available)
  local missing = {}
  for _, tool in ipairs(decl.requires_tools or {}) do
    if not available[tool] then missing[#missing + 1] = tool end
  end
  return missing
end

--- Discover, migrate and mount every module.
--
-- `ctx` is handed to each module's routes function: the shared services it is allowed to use.
function M.load(app, ctx)
  M.loaded, M.failed, M.parked = {}, {}, {}
  -- Cleared first: a reload must not leave a provider pointing at code that no longer exists.
  mediator.reset()
  local tools = (ctx and ctx.tools) or {}

  local found = {}
  for _, id in ipairs(scan(ROOT)) do
    local decl, err = load_one(id)
    -- `parked = true` in module.lua takes a module out entirely: no routes, no migrations, no
    -- mediator contributions, so anything that asked it for something simply goes unanswered and the
    -- pages that showed it stop showing it. The alternative is deleting the folder, which throws
    -- away work that is only waiting.
    if decl and decl.parked then
      M.parked[#M.parked + 1] = decl
    elseif decl then
      found[#found + 1] = decl
    else
      M.failed[#M.failed + 1] = { id = id, error = err }
    end
  end

  table.sort(found, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
  end)

  for _, decl in ipairs(found) do
    local ok, err = xpcall(function()
      -- By convention, not declaration: a module owns modules/<id>/migrations/ if it has one.
      decl.migrations = migrate.run(decl.dir .. "/migrations")

      decl.missing_tools = missing_tools(decl, tools)
      decl.available = #decl.missing_tools == 0

      local routes = dofile(decl.dir .. "/routes.lua")
      assert(type(routes) == "function",
             "routes.lua must return a function(router, module, ctx)")
      routes(app.router, decl, ctx)
    end, debug.traceback)

    if ok then
      M.loaded[#M.loaded + 1] = decl
    else
      M.failed[#M.failed + 1] = { id = decl.id, error = err }
    end
  end

  return M.loaded, M.failed
end

--- Navigation entries, in declared order.
--
-- `dev` controls whether developer-only modules appear. `online` hides the ones whose content comes
-- from the network: a store with nothing to show is worse than no store, and an entry that only
-- leads to an error is not navigation.
function M.nav(active, dev, online)
  local out = {}
  for _, m in ipairs(M.loaded) do
    local hidden = (m.dev_only and not dev) or (m.requires_network and not online)
    if m.nav and not hidden then
      out[#out + 1] = {
        label = m.nav.label or m.name or m.id,
        href  = m.nav.href or m.mount or ("/" .. m.id),
        on    = (active == m.id),
        id    = m.id,
      }
    end
  end
  return out
end

function M.get(id)
  for _, m in ipairs(M.loaded) do if m.id == id then return m end end
end

--- Which module a path belongs to. Longest mount wins, so "/store/x" is the store's and not the
--- home module's, whose mount is "/".
function M.owning(path)
  local best
  for _, m in ipairs(M.loaded) do
    local mount = m.mount
    if mount and (path == mount or mount == "/" and path == "/"
                  or (mount ~= "/" and path:sub(1, #mount + 1) == mount .. "/")) then
      if not best or #mount > #best.mount then best = m end
    end
  end
  return best
end

return M
