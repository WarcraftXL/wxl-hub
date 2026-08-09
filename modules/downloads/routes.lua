local page     = require("core.ui.page")
local jobs     = require("core.jobs")
local install  = require("core.extensions.install")
local upgrade  = require("core.extensions.upgrade")
local notify   = require("core.notify")
local mediator = require("core.base.mediator")

return function(router, mod, ctx)
  local view = mod.view

  --- The half of the page that changes. Everything here is read fresh; nothing is cached between
  --- polls, because the whole point of the poll is that it may have changed.
  local function live()
    local running = jobs.running()
    local head = running[1]

    return view.render("live", {
      running  = running,
      head     = head and jobs.view(head) or nil,
      -- nil, not zero, until two samples exist. A rate needs an interval, and one reading is not an
      -- interval; printing 0 B/s for the first frame reads as a stalled download.
      now_rate = head and #jobs.speed_series(head) > 0 and jobs.rate(jobs.speed(head)) or nil,
      peak     = head and jobs.peak(head) > 0 and jobs.rate(jobs.peak(head)) or nil,
      queue    = #running > 1 and running or nil,
      pending  = upgrade.pending(),
      online   = page.online(),
      recent   = jobs.recent(8),
      job_view = jobs.view,
      rate     = jobs.rate,
      ago      = require("core.notify").ago,
    })
  end

  router:get("/downloads", function(req, res)
    if req.htmx then return res:html(live()) end
    res:html(page.render(view.render("downloads", {
      live  = live(),
      trail = { { "Home", "/" }, { "Downloads" } },
    }), { title = "Downloads", active = "downloads" }))
  end)

  -- What the page polls. Same fragment the page was built around, so there is one renderer for both.
  router:get("/downloads/live", function(req, res)
    res:html(live())
  end)

  local function accept(id)
    local row = mediator.ask("catalogue.get", id)
    local client = mediator.ask("client.inspect")
    if not client or not client.ok then
      return nil, "no usable client is set for this profile"
    end
    return install.start(row, client.path)
  end

  router:post("/downloads/accept/:id", function(req, res)
    local job, why = accept(req.params.id)
    if not job then
      notify.raise {
        kind = "install", ref = req.params.id, level = "bad",
        title = "Could not update " .. req.params.id, body = why, href = "/downloads",
      }
    end
    res:html(live())
  end)

  router:post("/downloads/accept-all", function(req, res)
    for _, p in ipairs(upgrade.pending()) do
      if p.usable then accept(p.id) end
    end
    res:html(live())
  end)
end
