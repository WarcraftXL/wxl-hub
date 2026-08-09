-- Template helpers, registered once on core.view and available in every template.
local view = require("core.base.view")

local M = {}

local function hue(id)
  local h = 0
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 360 end
  return h
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

function M.install()
  -- Page artwork by page id. A helper rather than a value threaded through every route: which
  -- picture a header wears is presentation, and no handler should have to carry it.
  -- Normalised here so the config can stay a bare URL in the common case and only grow a table when
  -- a picture actually needs mirroring.
  view.helper("pageimage", function(id)
    local v = require("core.ui.page").config.images[id]
    if type(v) == "string" then return { src = v } end
    return v
  end)

  -- A stable colour per id, so a card keeps its identity across sorts, filters and restarts.
  view.helper("markstyle", function(id)
    local h = hue(id)
    return "background:linear-gradient(145deg,hsl(" .. h .. " 30% 34%),hsl("
        .. ((h + 35) % 360) .. " 26% 22%))"
  end)

  view.helper("accent", function(id)
    local h = hue(id)
    return "--accent:linear-gradient(90deg,hsl(" .. h .. " 42% 46%),hsl("
        .. ((h + 35) % 360) .. " 38% 34%))"
  end)

  view.helper("initial", function(id)
    return (id:gsub("^wxl%-", "")):sub(1, 1):upper()
  end)

  view.helper("since", function(date)
    local _, m, d = tostring(date):match("(%d+)-(%d+)-(%d+)")
    if not m then return tostring(date) end
    return MONTHS[tonumber(m)] .. " " .. tonumber(d)
  end)
end

return M
