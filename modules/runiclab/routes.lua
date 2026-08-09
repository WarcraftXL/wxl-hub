--[[
  Runic-Lab, as a category in the workspace rail.

  This file exists to be small. It registers no route, imports nothing from the workspace, and knows
  nothing about how a rail is drawn. It names two slots and drops entries into them, and that is the
  entire contract for putting a family of tools into the workspace.

  Which is the point worth proving here rather than describing: the generators people actually ask
  for come back by adding a folder, and they leave by removing it.
]]

local mediator = require("core.base.mediator")

return function(router, mod, ctx)
  mediator.contribute("workspace.category", {
    id = "runic-lab", name = "Runic-Lab", icon = "flask-conical", order = 40,
    blurb = "Backports, the way RunicLab did them.",
  })

  -- No `path` on any of them yet, so the rail draws them without linking anywhere. `writes` is
  -- declared now rather than when they are built: it is a fact about what the tool is for, and the
  -- rail marks it so the answer to "will this touch my client" arrives before the click.
  mediator.contribute("workspace.tool", {
    category = "runic-lab", id = "mount-backport", name = "Mount Backport",
    order = 10, writes = true,
  })
  mediator.contribute("workspace.tool", {
    category = "runic-lab", id = "creature-backport", name = "Creature Backport",
    order = 20, writes = true,
  })
  mediator.contribute("workspace.tool", {
    category = "runic-lab", id = "spell-visuals", name = "Spell Visuals",
    order = 30, writes = true,
  })
end
