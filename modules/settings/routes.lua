--[[
  The preferences interface.

  It owns the rail and its own pages, and nothing else. Which profile is active, and every value read
  against it, belongs to the profiles module and arrives through the mediator. The Profiles page in
  the rail is not this module's: it is contributed to `settings.section`, the same way the store and
  the tools module fill the home page.

  Any module can add a page here by contributing to that point. This file will not learn about it.
]]

local page     = require("core.ui.page")
local client   = require("core.game.client")
local mediator = require("core.base.mediator")
local cache    = require("core.base.cache")
local boot     = require("core.extensions.boot")
local migrate  = require("core.base.migrate")
local modules  = require("core.modules")
local release  = require("core.release")

local function human_bytes(n)
  if n < 1024 then return n .. " B" end
  if n < 1048576 then return ("%.1f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1048576)
end

local function cache_summary()
  local rows = cache.summary()

  -- "Last refresh" is the *newest* entry, so this tracks the smallest age. Keeping the largest
  -- describes the oldest thing in the cache instead, and one forgotten row from yesterday then has
  -- the page reporting nothing fetched in a day while the catalogue came in a minute ago.
  local bytes, newest, oldest, expired = 0, nil, nil, 0
  for _, r in ipairs(rows) do
    bytes = bytes + (r.bytes or 0)
    if not newest or r.age < newest then newest = r.age end
    if not oldest or r.age > oldest then oldest = r.age end
    if r.expired == 1 then expired = expired + 1 end
  end

  -- The same wording the notification panel uses, from the same function, so two places in the app
  -- do not describe the same interval differently.
  local ago = require("core.notify").ago
  return {
    entries = #rows,
    size    = human_bytes(bytes),
    age     = newest and ago(os.time() - newest) or "never fetched",
    stalest = oldest and ago(os.time() - oldest) or nil,
    expired = expired,
    ttl     = math.floor(cache.DEFAULT_TTL / 60) .. " minutes",
  }
end

return function(router, mod, ctx)
  local view = mod.view

  local function path_of(key) return mediator.ask("setting.get", key) or "" end

  -- The client is inspected here because this is where the client page lives. What the path *is*
  -- comes from whoever owns settings values, which is not this module.
  mediator.provide("client.inspect", function()
    return client.inspect(path_of("client_path"))
  end)

  -- This module's own pages, in the same shape a contributed one has, so the rail cannot tell them
  -- apart and neither can anything else.
  local OWN = {
    { id = "about", label = "About", group = "Setup", order = 10, render = function()
        return view.render("sec_about", {
          version   = release.version,
          build     = release.build,
          installed = release.installed,
        })
      end },

    { id = "client", label = "Client", group = "Setup", order = 20, render = function()
        local path = path_of("client_path")
        return view.render("sec_client", {
          s           = { client_path = path },
          client      = client.inspect(path),
          clear_cache = mediator.ask("setting.bool", "clear_cache") == true,
        })
      end },

    { id = "developer", label = "Developer", group = "Advanced", order = 30, render = function()
        return view.render("sec_developer", {
          s         = { core_path = path_of("core_path") },
          developer = mediator.ask("setting.bool", "developer") == true,
          python    = ctx.tools and ctx.tools.python or nil,
        })
      end },

    { id = "storage", label = "Storage", group = "Advanced", order = 40, render = function()
        return view.render("sec_storage", { cache = cache_summary(), updates = migrate.applied() })
      end },

    { id = "diagnostics", label = "Diagnostics", group = "Advanced", order = 50, render = function()
        return view.render("sec_diagnostics", {
          loaded = modules.loaded, failed = modules.failed, wiring = mediator.inventory(),
        })
      end },
  }

  --- Every page in the rail: this module's, plus whatever any other module contributed.
  local function sections()
    local all = {}
    for _, s in ipairs(OWN) do all[#all + 1] = s end
    for _, s in ipairs(mediator.collect("settings.section")) do all[#all + 1] = s end
    table.sort(all, function(a, b)
      if a.order ~= b.order then return a.order < b.order end
      return tostring(a.id) < tostring(b.id)
    end)
    return all
  end

  local function section(list, id)
    for _, s in ipairs(list) do if s.id == id then return s end end
  end

  --- Navigating to a page. htmx gets the rail and the page together, because moving the highlight
  --- is half of what the click was for.
  local function respond(res, req, list, entry)
    local shell = { sections = list, active = entry.id, body = entry.render() }
    if req.htmx then return res:html(view.render("prefs", shell)) end
    shell.trail = { { "Home", "/" }, { "Settings" } }
    res:html(page.render(view.render("settings", shell),
                         { title = "Settings", active = "settings" }))
  end

  router:get("/settings", function(req, res)
    res:redirect("/settings/" .. sections()[1].id)
  end)

  router:get("/settings/:section", function(req, res)
    local list  = sections()
    local entry = section(list, req.params.section)
    if not entry then return res:redirect("/settings/" .. list[1].id) end
    respond(res, req, list, entry)
  end)

  -- A field whose value changes what the page says about it asks for its page back; the rest are
  -- content to be told the write landed.
  router:post("/settings/value/:key", function(req, res)
    mediator.ask("setting.set", req.params.key, req.form.value or "")
    local entry = section(sections(), req.query.section or "")
    if entry then return res:html(entry.render()) end
    res:html('<span class="ok">saved</span>')
  end)

  router:post("/settings/toggle/:key", function(req, res)
    local key = req.params.key
    local on  = mediator.ask("setting.toggle", key)
    -- Developer mode decides what the top bar shows, so swapping the switch alone would leave the
    -- navigation contradicting it until the next page load.
    if key == "developer" then
      return res:hx_redirect(req.query.back or "/settings/developer")
    end
    res:html(view.render("core:switch", { key = key, on = on }))
  end)

  router:post("/settings/cache/clear", function(req, res)
    cache.forget(boot.KEY)
    res:html('<span class="ok">cleared, restart to refetch</span>')
  end)

end
