--[[
  The mediator: how modules reach each other without knowing each other.

  A module never reaches another by path. `dofile("modules/store/models/catalogue.lua")` is a hard
  dependency in both directions: remove the store and its consumers raise, add a module and every
  consumer has to learn its file layout. A module system where modules import each other by path is
  a folder convention, not a module system.

  Three shapes, and the difference between them matters:

    provide / ask       one answer. "Who can tell me the catalogue stats?" Returns nil when nobody
                        can, so the caller degrades instead of failing.

    contribute / collect  many answers. The home page owns a slot called "home.section"; the store
                        and the tools module each drop a section into it. Home renders what it
                        collected and never learns who filled it.

    on / emit           notifications. Nobody waits for a result and nobody may fail the emitter.

  Everything is cleared before modules load, so a reload cannot leave a provider pointing at code
  that no longer exists.
]]

local M = {}

local providers = {}
local points    = {}
local listeners = {}

function M.reset()
  providers, points, listeners = {}, {}, {}
end

-- ------------------------------------------------------------ one answer ---

--- Register the answer to `name`. Registering twice is a mistake worth hearing about: two modules
--- claiming the same capability means whichever loaded last silently wins.
function M.provide(name, fn)
  if providers[name] then
    print(("mediator: %q provided twice; the later registration wins"):format(name))
  end
  providers[name] = fn
end

function M.has(name)
  return providers[name] ~= nil
end

--- Ask for `name`. Returns nil when nothing provides it. Callers are expected to handle that
--- rather than assume a module is installed.
function M.ask(name, ...)
  local fn = providers[name]
  if not fn then return nil end
  local ok, result = pcall(fn, ...)
  if not ok then
    print(("mediator: provider %q failed: %s"):format(name, tostring(result)))
    return nil
  end
  return result
end

--- Ask, falling back to a default. Reads better than `ask(...) or default` where the default is
--- itself a table literal.
function M.ask_or(name, default, ...)
  local v = M.ask(name, ...)
  if v == nil then return default end
  return v
end

-- ---------------------------------------------------------- many answers ---

--- Add an entry to a collection point. `entry.order` sorts it; `entry.id` identifies it.
function M.contribute(point, entry)
  points[point] = points[point] or {}
  entry.order = entry.order or 100
  table.insert(points[point], entry)
end

--- Everything contributed to `point`, in order. Always a table, possibly empty.
function M.collect(point)
  local list = points[point] or {}
  table.sort(list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return tostring(a.id) < tostring(b.id)
  end)
  return list
end

--- Collect and render, dropping anything that raises. One broken contribution must not take the
--- page with it, because the rest of the screen is still worth showing.
function M.render(point, ...)
  local out = {}
  for _, entry in ipairs(M.collect(point)) do
    if entry.render then
      local ok, html = pcall(entry.render, ...)
      if ok and html then
        out[#out + 1] = html
      elseif not ok then
        print(("mediator: contribution %q to %q failed: %s")
          :format(tostring(entry.id), point, tostring(html)))
      end
    end
  end
  return table.concat(out, "\n")
end

-- --------------------------------------------------------- notifications ---

function M.on(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

function M.emit(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then
      print(("mediator: listener for %q failed: %s"):format(event, tostring(err)))
    end
  end
end

--- What is registered, for the settings page: the wiring should be inspectable rather than implied.
function M.inventory()
  local out = { provides = {}, points = {}, events = {} }
  for name in pairs(providers) do out.provides[#out.provides + 1] = name end
  for point, list in pairs(points) do
    out.points[#out.points + 1] = { name = point, count = #list }
  end
  for event, list in pairs(listeners) do
    out.events[#out.events + 1] = { name = event, count = #list }
  end
  table.sort(out.provides)
  table.sort(out.points, function(a, b) return a.name < b.name end)
  table.sort(out.events, function(a, b) return a.name < b.name end)
  return out
end

return M
