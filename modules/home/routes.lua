--[[
  The home page owns its layout and a slot called "home.section". Everything between the
  announcements and the support banner is contributed by whoever wants to be there; this file has no
  idea which modules those are, and works unchanged when none of them are installed.

  News and the support text come from wxl-core's own manifest, so editing them is a commit there
  rather than a build here. When that manifest could not be fetched the user is offline, and there is
  nothing here worth showing: no news, no catalogue, no store. The library is, so we go there.
]]

local page     = require("core.ui.page")
local history  = require("core.history")
local news     = require("core.extensions.news")
local mediator = require("core.base.mediator")
local modules  = require("core.modules")

local function take(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i] end
  return out
end

--- Where to send someone with no feed. The library first, then whatever else is mounted; a hub with
--- neither is a hub with nothing to say, and says so.
local function fallback()
  if modules.get("library") then return "/library" end
  for _, m in ipairs(modules.loaded) do
    if m.id ~= "home" and m.mount then return m.mount end
  end
end

return function(router, mod, ctx)
  local view = mod.view

  router:get("/", function(req, res)
    if not page.online() or not news.live() then
      local to = fallback()
      if to then return res:redirect(to) end
      return res:html(page.notice {
        title = "Nothing to show yet",
        text  = "The hub could not reach wxl-core, and no other module is installed. Check your "
             .. "connection, or install something from a local archive.",
        code  = "offline",
      })
    end

    local feed = news.feed()

    -- Kept only while something still answers at that address. History outlives the modules that
    -- wrote it, and a list of links into a page that no longer exists is worse than a short list.
    local seen = {}
    for _, h in ipairs(history.recent(12)) do
      if #seen < 4 and modules.owning(h.href) then seen[#seen + 1] = h end
    end

    res:html(page.render(view.render("home", {
      featured = feed.featured,
      news     = take(feed.items, 2),
      sections = mediator.render("home.section"),
      history  = seen,
      support  = news.support(),
      links    = news.links(),
    }), { active = "home" }))
  end)

  -- Gated here rather than by the network guard in core.app: this module is mounted at "/", so path
  -- ownership cannot tell "/news" apart from routes core registers at the root.
  router:get("/news", function(req, res)
    if not page.online() or not news.live() then
      local to = fallback()
      if to then return res:redirect(to) end
      return res:html(page.notice {
        title = "Offline",
        text  = "Announcements are published by wxl-core and read over the network.",
        code  = "offline",
      })
    end

    res:html(page.render(view.render("news", {
      items = news.feed().all,
      trail = { { "Home", "/" }, { "Announcements" } },
    }), { title = "Announcements", active = "home" }))
  end)
end
