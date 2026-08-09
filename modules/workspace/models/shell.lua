--[[
  The workspace shell, assembled.

  Two pieces of chrome and one call. The pieces are built here rather than in core because both are
  made of things only this module knows about: what a category is, what a tool is, and what the
  target means. core.ui.page carries them through without looking inside, which is what lets a second
  shell exist without core growing a second set of concepts.

  Both pieces are marked out of band exactly when the document they are going into is already on
  screen. Asked of core rather than passed in by every handler, because a handler has no reason to
  know how the answer travels.
]]

local mediator = require("core.base.mediator")
local page     = require("core.ui.page")
local view     = require("core.base.view")

local target = dofile("modules/workspace/models/target.lua")

local M = {}

--- Every category that has tools, with its tools, in order.
--
-- Shared by the rail and by the overview: the rail is navigation, collapsed until you reach for it,
-- and the overview is the map. Two readings of one list, so they cannot disagree about what exists.
function M.categories(active)
  local tools = mediator.collect("workspace.tool")
  local cats  = {}

  for _, c in ipairs(mediator.collect("workspace.category")) do
    local mine, on = {}, false

    for _, t in ipairs(tools) do
      if t.category == c.id then
        local here = (t.id == active)
        on = on or here
        mine[#mine + 1] = { id = t.id, name = t.name, path = t.path, writes = t.writes, on = here }
      end
    end

    -- Copied, never annotated. The entries belong to whoever contributed them and outlive the
    -- request; writing this page's highlight into one would leave it lit on the next page too.
    if #mine > 0 then
      cats[#cats + 1] = {
        id = c.id, name = c.name, icon = c.icon, blurb = c.blurb, tools = mine, on = on,
      }
    end
  end

  return cats
end

--- The rail. `active` is the id of the tool being shown, or "overview".
function M.rail(active)
  return view.render("workrail",
                     { cats = M.categories(active), active = active, oob = page.boosted() })
end

--- The strip in the bar that names what is being operated on.
--
-- `oob` is forced by the one caller that changes the target without navigating: a plain post carries
-- no boosting header, so the shell would answer it with a strip nobody swaps in.
function M.strip(oob)
  if oob == nil then oob = page.boosted() end
  return view.render("worktarget", { t = target.get(), short = target.short, oob = oob })
end

--- Render `body` inside the workspace shell.
--
-- opts: title, tool (the rail entry to light up)
function M.render(body, opts)
  opts = opts or {}
  return page.render(body, {
    title  = opts.title,
    active = "workspace",
    layout = "layout_work",
    chrome = { rail = M.rail(opts.tool or "overview"), target = M.strip() },
  })
end

return M
