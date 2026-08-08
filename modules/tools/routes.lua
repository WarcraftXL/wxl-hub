local tools    = dofile("modules/tools/models/tools.lua")
local page     = require("core.page")
local history  = require("core.history")
local mediator = require("core.mediator")

local function find(id)
  for _, t in ipairs(tools.tools) do if t.id == id then return t end end
end

local function take(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i] end
  return out
end

return function(router, mod, ctx)
  local view = mod.view

  mediator.provide("tools.list", function(n) return take(tools.tools, n or #tools.tools) end)
  mediator.provide("tools.get", find)

  mediator.contribute("home.section", {
    id = "tools", order = 40,
    render = function()
      return view.render("home_section", { tools = take(tools.tools, 4) })
    end,
  })

  router:get("/tools", function(req, res)
    res:html(page.render(view.render("tools", {
      tools = tools.tools,
      available = mod.available,
      missing = mod.missing_tools,
      trail = { { "Home", "/" }, { "Tools" } },
    }), { title = "Tools", active = "tools" }))
  end)

  router:get("/tools/:id", function(req, res)
    local t = find(req.params.id)
    if not t then
      return res:html(page.notice {
        title = "No such tool",
        text  = "Nothing is registered under /tools/" .. req.params.id .. ".",
      })
    end

    history.record {
      kind = "tool", ref = t.id, href = "/tools/" .. t.id,
      title = t.name, subtitle = t.blurb, icon = t.icon,
    }

    res:html(page.notice {
      title = "This one is still being surveyed",
      text  = t.name .. " arrives with milestone M3, once the job runner can spawn the converters "
           .. "and stream their progress. Until then the store and the module listings are the "
           .. "parts that work.",
      code  = "Not built yet",
    })
  end)
end
