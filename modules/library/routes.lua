local page     = require("core.ui.page")
local db       = require("core.base.db")
local install  = require("core.extensions.install")
local upgrade  = require("core.extensions.upgrade")
local mediator = require("core.base.mediator")

return function(router, mod, ctx)
  local view = mod.view

  -- What the store needs to know to stop offering an Install button for something already here.
  mediator.provide("library.installed", function(id)
    return db.row("SELECT id, version, enabled FROM installed WHERE id = ?", id)
  end)

  local function body()
    local list = db.rows("SELECT * FROM installed ORDER BY enabled DESC, id")

    local pending = {}
    for _, p in ipairs(upgrade.pending()) do pending[p.id] = p end

    local enabled = 0
    for _, r in ipairs(list) do
      if r.enabled == 1 then enabled = enabled + 1 end

      -- Enriched only if a catalogue is installed. Without the store module the page still lists
      -- what is deployed, it just has no tagline to show. `listed` is the other half of that: a
      -- module whose repository has dropped its manifest still runs, and saying so beats a blank.
      local meta = mediator.ask("catalogue.get", r.id)
      r.tagline = meta and meta.tagline or nil
      r.owner   = meta and meta.owner or nil
      r.listed  = meta ~= nil
      r.update  = pending[r.id]
    end

    return view.render("library", {
      installed  = list,
      enabled    = enabled,
      can_browse = mediator.has("catalogue.stats"),
      online     = page.online(),
      trail      = { { "Home", "/" }, { "Library" } },
    })
  end

  router:get("/library", function(req, res)
    if req.htmx then return res:html(body()) end
    res:html(page.render(body(), { title = "Library", active = "library" }))
  end)

  -- The rename on disk is what actually enables or disables the module; the column only records it.
  -- The disk goes first: writing the column and failing to rename leaves a switch claiming something
  -- the core disagrees with, and the core loads whatever it finds.
  router:post("/library/:id/toggle", function(req, res)
    local id  = req.params.id
    local row = db.row("SELECT enabled FROM installed WHERE id = ?", id)
    if not row then return res:html(body() .. page.toast("bad", id, "not installed")) end

    local want   = row.enabled ~= 1
    local client = mediator.ask("client.inspect")
    local done, why = install.set_enabled(id, want, client and client.path)
    if not done then
      return res:html(body() .. page.toast("bad", "Could not " ..
        (want and "enable " or "disable ") .. id, why))
    end

    db.run("UPDATE installed SET enabled = ? WHERE id = ?", want and 1 or 0, id)
    mediator.emit("library.changed", id)
    res:html(body() .. page.toast("info", id, want and "enabled, the core will load it next launch"
                                              or "disabled, the core will skip it next launch"))
  end)

  router:post("/library/:id/update", function(req, res)
    local client = mediator.ask("client.inspect")
    if not client or not client.ok then
      return res:html(body() .. page.toast("bad", "Cannot update " .. req.params.id,
                                           "no usable client is set for this profile"))
    end
    local job, why = install.start(mediator.ask("catalogue.get", req.params.id), client.path)
    if not job then
      return res:html(body() .. page.toast("bad", "Cannot update " .. req.params.id, why))
    end
    -- The row itself does not report progress: the download centre is where a running job lives,
    -- and duplicating a progress bar into every list is how two of them end up disagreeing.
    res:html(body() .. page.toast("info", "Updating " .. req.params.id, "follow it in Downloads"))
  end)

  router:post("/library/:id/remove", function(req, res)
    local client = mediator.ask("client.inspect")
    local gone, detail = install.remove(req.params.id, client and client.path)

    local toast
    if not gone then
      toast = page.toast("bad", "Could not remove " .. req.params.id,
                         detail or "it could not be removed")
    elseif detail and #detail > 0 then
      -- Not a failure, and not silence either: files that no longer match what the hub wrote were
      -- edited afterwards, so they stay and the user is told which ones.
      toast = page.toast("info", req.params.id .. " removed",
                         ("%d file(s) you had edited were left in place: %s")
                         :format(#detail, table.concat(detail, ", ")))
    else
      toast = page.toast("good", req.params.id .. " removed", nil)
    end

    mediator.emit("library.changed", req.params.id)
    res:html(body() .. toast)
  end)
end
