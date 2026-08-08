--[[
  Profiles: who the settings belong to.

  This module owns the identity every scoped value is read against. The preferences interface is a
  separate concern and lives in its own module: keeping both here would mean core has to ask this
  one by name to draw the startup question, and core knowing a module by name is what the mediator
  exists to prevent.

  Nothing here knows the settings module exists. It offers its page as a contribution and lets
  whoever owns the settings rail place it.
]]

local page     = require("core.page")
local mediator = require("core.mediator")
local style    = require("core.style")

local profiles = dofile("modules/profiles/models/profiles.lua")

return function(router, mod, ctx)
  local view = mod.view

  -- ------------------------------------------------------------ capabilities ---
  -- The values API. Named `setting.*` rather than after this module: what a caller wants is a
  -- setting, and which module keeps it is exactly what it should not have to know.
  mediator.provide("setting.get",    profiles.get)
  mediator.provide("setting.set",    profiles.set)
  mediator.provide("setting.bool",   profiles.bool)
  mediator.provide("setting.toggle", profiles.toggle)

  mediator.provide("profile.active",   profiles.active)
  mediator.provide("profile.list",     profiles.profiles)
  mediator.provide("profile.activate", profiles.activate)
  mediator.provide("profile.name",     function()
    local p = profiles.active()
    return p and p.name or nil
  end)

  -- ------------------------------------------------------------- the section ---
  local function data(problem)
    return {
      s           = profiles.all(),
      autolaunch  = profiles.bool("autolaunch"),
      ask_profile = profiles.bool("ask_profile"),
      profile     = profiles.active(),
      profiles    = profiles.profiles(),
      problem     = problem,
    }
  end

  local function section(problem)
    return view.render("sec_profiles", data(problem))
  end

  mediator.contribute("settings.section", {
    id = "profiles", label = "Profiles", group = "Setup", order = 10,
    render = function() return section() end,
  })

  --- Actions redraw the section in place and say what happened in a toast. The rail is left alone:
  --- nothing navigated, and pushing a message into the section would shove the form under the
  --- cursor that just used it.
  local function redraw(res, problem)
    res:html(section() .. (problem and page.toast("bad", problem, nil) or ""))
  end

  router:post("/profiles/new", function(req, res)
    local made, why = profiles.create(req.form.name)
    if made then profiles.activate(made.id) end
    redraw(res, why)
  end)

  router:post("/profiles/:id/rename", function(req, res)
    local _, why = profiles.rename(tonumber(req.params.id), req.form.name)
    redraw(res, why)
  end)

  -- Switching redraws the section and repaints the name in the bar out of band. Not a redirect:
  -- sending the browser to the page this section is shown on would mean knowing where another
  -- module chose to mount it, which is the coupling this module was split out to remove.
  router:post("/profiles/:id/activate", function(req, res)
    profiles.activate(tonumber(req.params.id))
    mediator.emit("profile.changed")
    res:html(section() .. page.profile_chip()
             .. page.toast("good", profiles.active().name, "now the active profile"))
  end)

  router:post("/profiles/:id/delete", function(req, res)
    local _, why = profiles.remove(tonumber(req.params.id))
    if why then return redraw(res, why) end
    mediator.emit("profile.changed")
    res:html(section() .. page.profile_chip() .. page.toast("good", "Profile deleted", nil))
  end)

  -- ------------------------------------------------------------ the startup ---
  -- Session state, not a column: "I already chose" is true of this run of the app, and writing it
  -- down would make the next launch skip the question it was told to ask.
  local chosen = false

  --- Core asks every module whether it needs an answer before the app opens. It never learns what
  --- the question is, or that profiles are the ones asking.
  mediator.provide("startup.gate", function(path)
    if chosen or path:find("^/profiles/use/") then return nil end
    if not profiles.bool("ask_profile") then return nil end

    local list = profiles.profiles()
    if #list < 2 then return nil end            -- one profile is not a choice

    local active = profiles.active()
    return view.render("chooseprofile", {
      stylesheet = style.href,
      csp        = page.CSP_PLAIN,
      profiles   = list,
      active     = active and active.id or nil,
    })
  end)

  router:post("/profiles/use/:id", function(req, res)
    chosen = true
    profiles.activate(tonumber(req.params.id))
    if req.form.remember == "1" then profiles.set("ask_profile", "0") end
    res:hx_redirect("/")
  end)
end
