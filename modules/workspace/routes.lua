--[[
  The workspace: the shell, the target, and the two collection points the rail is built from.

  What this module does not hold is a list of tools. `workspace.category` and `workspace.tool` are
  slots; the categories below are the ones this module happens to own, contributed through the same
  door a separate module uses. That is the whole design: bringing a family of tools back is dropping
  a folder into modules/, not editing this file. modules/runiclab/ is the proof, and it is thirty
  lines with no routes at all.

  A tool with no `path` is drawn but not linked. Six cards that each opened onto "not built yet" is
  what this rail replaced, and a planned entry you can see but not click costs nobody their place.

  `writes = true` is not decoration either. It is what the runner will read to force a tool through
  plan, then apply, then a restorable record. A tool that never declares it will not be handed the
  means to write, so the rule is true by construction rather than by everyone remembering it.
]]

local mediator = require("core.base.mediator")

local shell  = dofile("modules/workspace/models/shell.lua")
local target = dofile("modules/workspace/models/target.lua")
local fav    = dofile("modules/workspace/models/favourites.lua")
local deploy = dofile("modules/workspace/models/deploy.lua")

-- `icon` is a Lucide name, resolved against the set vendored in core/ui/icons.lua. Naming it rather
-- than drawing it is what lets a category keep its picture when the set is restyled, and what makes
-- the name searchable upstream.
local CATEGORIES = {
  { id = "client",      name = "Client",      icon = "wrench",   order = 5,
    blurb = "Get a client ready, and keep it that way." },

  { id = "assets",      name = "Assets",      icon = "files",    order = 10,
    blurb = "Read any file the client reads." },

  { id = "terrain",     name = "Terrain",     icon = "mountain", order = 20,
    blurb = "Split, rebuild and check map tiles." },

  { id = "data",        name = "Data",        icon = "database", order = 30,
    blurb = "Move modern tables into what the client and the server read." },

  { id = "package",     name = "Package",     icon = "package",  order = 60,
    blurb = "Turn a working tree into something the store can list." },

  { id = "diagnostics", name = "Diagnostics", icon = "activity", order = 90,
    blurb = "What the hub sees of itself." },
}

local TOOLS = {
  { category = "client", id = "deploy", name = "Deploy framework", order = 10, writes = true,
    path = "/workspace/client/deploy" },

  { category = "assets", id = "chunks",  name = "Chunk Inspector", order = 10 },
  { category = "assets", id = "texture", name = "Texture Preview", order = 20 },
  { category = "assets", id = "model",   name = "Model Viewer",    order = 30 },

  { category = "terrain", id = "adtsplit", name = "ADT Split",  order = 10, writes = true },
  { category = "terrain", id = "wdl",      name = "WDL Regen",  order = 20, writes = true },

  { category = "data", id = "db2dbc", name = "DB2 to DBC", order = 10, writes = true },

  { category = "package", id = "release",  name = "Build Release", order = 10 },
  { category = "package", id = "manifest", name = "Manifest Check", order = 20 },

  { category = "diagnostics", id = "wiring", name = "Wiring", order = 10,
    path = "/workspace/diagnostics/wiring" },
}

return function(router, mod, ctx)
  local view = mod.view

  for _, c in ipairs(CATEGORIES) do mediator.contribute("workspace.category", c) end
  for _, t in ipairs(TOOLS)      do mediator.contribute("workspace.tool", t) end

  deploy.install()

  local function status()
    return view.render("status", { t = target.get(), short = target.short })
  end

  local function favourites()
    return view.render("favourites", { cards = fav.cards(shell.categories(nil)) })
  end

  router:get("/workspace", function(req, res)
    res:html(shell.render(view.render("overview", {
      status     = status(),
      favourites = favourites(),
    }), { title = "Dev Workspace" }))
  end)

  -- The grid and the picker swap each other out under one id, so neither has to know where on the
  -- page it was rendered.
  router:get("/workspace/favourites", function(req, res)
    res:html(favourites())
  end)

  router:get("/workspace/favourites/pick", function(req, res)
    res:html(view.render("favpick", { cats = fav.available(shell.categories(nil)) }))
  end)

  router:post("/workspace/favourites/:id", function(req, res)
    fav.add(req.params.id)
    res:html(favourites())
  end)

  router:post("/workspace/favourites/:id/remove", function(req, res)
    fav.remove(req.params.id)
    res:html(favourites())
  end)

  -- Answers with the block it replaces, plus the strip in the bar, which is the same fact said in the
  -- two places it has to be true at once.
  router:post("/workspace/target", function(req, res)
    target.set(req.form.value)
    res:html(status() .. shell.strip(true))
  end)

  router:get("/workspace/client/deploy", function(req, res)
    res:html(shell.render(view.render("deploy", { t = target.get(), short = target.short }),
                          { title = "Deploy framework", tool = "deploy" }))
  end)

  -- Answers with the job element alone, which polls itself through /jobs/:id like every other
  -- transfer in the app. The page around it is not re-rendered: what it says about the client only
  -- becomes true when the job lands, and the element asks for it then.
  router:post("/workspace/client/deploy", function(req, res)
    local r = mediator.ask("client.deploy", target.get().path,
                           { url = "/workspace/client/state", target = "#dstate" }) or {}
    if not r.job then
      return res:html(view.render("core:job", { job = { state = "failed", error = r.error } }))
    end
    res:html(view.render("core:job", { job = require("core.jobs").view(r.job) }))
  end)

  router:get("/workspace/client/state", function(req, res)
    res:html(view.render("deploy_state", { t = target.get() }))
  end)

  router:get("/workspace/diagnostics/wiring", function(req, res)
    local modules = require("core.modules")
    res:html(shell.render(view.render("wiring", {
      inventory = mediator.inventory(),
      loaded    = modules.loaded,
      failed    = modules.failed,
    }), { title = "Wiring", tool = "wiring" }))
  end)
end
