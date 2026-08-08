--[[
  What is installed, against what the catalogue now says.

  Nothing here downloads or decides. It compares two lists and reports the difference, so both the
  download centre and the automatic path work from the same answer rather than each computing its
  own and disagreeing about what is pending.

  A pending update is not a promise that it will install: the catalogue row still has to be
  installable, which is checked when the job starts and not assumed here.
]]

local db       = require("core.db")
local manifest = require("core.manifest")
local mediator = require("core.mediator")

local M = {}

--- Everything installed that the catalogue offers a newer version of.
--
-- Rows the catalogue has never heard of are skipped rather than reported: a module installed from a
-- repository that has since dropped its manifest is not out of date, it is unlisted, and telling
-- someone to update something the store cannot show them is a dead end.
function M.pending()
  local out = {}
  for _, row in ipairs(db.rows("SELECT * FROM installed ORDER BY id")) do
    local listed = mediator.ask("catalogue.get", row.id)
    local ext = listed and listed.rec and listed.rec.extension
    if ext and ext.version and manifest.compare(ext.version, row.version) > 0 then
      out[#out + 1] = {
        id      = row.id,
        from    = row.version,
        to      = ext.version,
        title   = listed.rec.listing.title or row.id,
        owner   = listed.owner,
        usable  = listed.rec.installable == true,
        why_not = listed.rec.why_not,
      }
    end
  end
  return out
end

--- The one line the bell and the badge need, without building the whole list twice.
function M.count()
  return #M.pending()
end

return M
