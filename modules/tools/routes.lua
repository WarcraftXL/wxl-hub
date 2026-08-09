--[[
  Tools, reduced to its entry in the navigation.

  The pipeline this page hosted is moving into the launcher itself. Listing six cards that each open
  onto "not built yet" said less than one honest dead end, so every path under the mount answers with
  that dead end instead.

  The entry stays in the bar rather than the module being parked, because a module that is parked
  disappears from the navigation entirely and the work stops being visible to the one person it is
  queued for. Behind developer mode, so nobody else meets it.
]]

local page = require("core.ui.page")

local NOT_BUILT = {
  title = "Tools are being rebuilt",
  text  = "The asset pipeline is moving into the launcher itself. Until it lands there is nothing "
       .. "here to drive, and the store and the module listings are the parts that work.",
  code  = "Not built yet",
}

return function(router)
  local function dead_end(req, res) res:html(page.notice(NOT_BUILT)) end

  router:get("/tools", dead_end)
  -- Named, because the router's splat is `*name` and a bare star is matched as a literal.
  router:get("/tools/*rest", dead_end)
end
