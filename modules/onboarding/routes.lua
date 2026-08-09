--[[
  First run: the three questions asked once, before the hub opens.

  Its own module because the screen is its own concern, not a feature of any of the things it asks
  about. It touches identity, a filesystem path, a preference and an install, and it was living
  inside the module that owns the first of those four. That module then had to hold the other three
  as well, and the one slot core offered for a startup question had to serve two unrelated ones.

  Nothing here knows who keeps the settings or who owns profiles. It asks for capabilities by name
  and does without the ones nobody provides, which is what lets the form live outside every module
  it questions.
]]

local page     = require("core.ui.page")
local mediator = require("core.base.mediator")
local style    = require("core.ui.style")
local client   = require("core.game.client")

local deploy = dofile("modules/onboarding/models/deploy.lua")

return function(router, mod, ctx)
  local view = mod.view

  local function get(key)        return mediator.ask("setting.get", key) end
  local function set(key, value) return mediator.ask("setting.set", key, value) end

  --- The client folder as it stands, which is what both the field and the verdict render from.
  local function verdict()
    return view.render("welcome_client", { client = client.inspect(get("client_path")) })
  end

  -- --------------------------------------------------------------- the question ---
  mediator.contribute("startup.question", {
    id = "first-run", order = 10,

    -- The stretch of the URL space this screen answers on. Core lets these through so the form can
    -- reach its own handlers instead of being served to itself.
    owns = "/welcome/",

    render = function()
      -- Nowhere to write the answers down means a form that comes back at every launch, which is a
      -- worse first impression than never asking at all.
      if not mediator.has("setting.set") then return nil end
      if mediator.ask("setting.bool", "onboarded") then return nil end

      local where = get("client_path")
      return view.render("welcome", {
        stylesheet  = style.href,
        csp         = page.CSP_PLAIN,
        name        = mediator.ask_or("profile.name", ""),
        client_path = where,
        client      = client.inspect(where),
        developer   = mediator.ask("setting.bool", "developer"),
      })
    end,
  })

  -- ------------------------------------------------------------------ the fields ---
  -- Each one saves on its own. The button at the end records that the question was asked, not the
  -- answers, so closing the window half way through keeps whatever was already filled in.

  -- Answers with a word rather than with 204. The field saves while you type, so it has to show that
  -- it did, and a name that was refused has to say so: silence reads as saved, and the profile
  -- quietly keeps the old one.
  router:post("/welcome/name", function(req, res)
    local why = mediator.ask("profile.rename", req.form.value)
    res:html(('<span id="wsaid" class="wsaid %s">%s</span>')
             :format(why and "bad" or "ok", why or "Saved"))
  end)

  router:post("/welcome/client", function(req, res)
    set("client_path", req.form.value or "")
    res:html(verdict())
  end)

  -- Its own switch rather than the shared one, which posts to a settings route that core would hold
  -- back until this screen is done with. One element is a smaller price than a partial that has to
  -- know it is being shown before the app exists.
  router:post("/welcome/dev", function(req, res)
    local on = mediator.ask("setting.toggle", "developer")
    res:html(('<a class="switch %s" role="button" tabindex="0" hx-post="/welcome/dev" '
              .. 'hx-swap="outerHTML"></a>'):format(on and "on" or ""))
  end)

  -- Fetches the framework and applies it. Answers with the job element, which polls itself through
  -- /jobs/:id like every other transfer in the app.
  router:post("/welcome/patch", function(req, res)
    local job, why = deploy.start(get("client_path"))
    if not job then
      return res:html(view.render("core:job", { job = { state = "failed", error = why } }))
    end
    res:html(view.render("core:job", { job = require("core.jobs").view(job) }))
  end)

  -- Asked for by id from inside the job element once the install lands: the lines above it were
  -- written before any of it was true.
  router:get("/welcome/verdict", function(req, res)
    res:html(verdict())
  end)

  router:post("/welcome/done", function(req, res)
    set("onboarded", "1")
    res:hx_redirect("/")
  end)
end
