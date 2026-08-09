--[[
  The tools kept on the workspace's front page.

  The overview used to list every category and every tool it holds, which is a catalogue. A catalogue
  is the right thing to read once and the wrong thing to open every morning: the rail already answers
  "what exists", and what the front page owes you is the four things you actually run.

  Stored as a list of tool ids in one setting rather than in a table of its own. It is a short ordered
  list belonging to whoever is using the hub, which is what settings already are, and a migration for
  it would be a table with one column.

  Ids are assumed unique across the whole workspace, not merely within a category. The rail already
  relies on that to know which entry to light up, so it is stated here rather than left implied.
]]

local mediator = require("core.base.mediator")

local M = {}

local KEY = "workspace_favourites"

function M.ids()
  local out = {}
  for id in tostring(mediator.ask("setting.get", KEY) or ""):gmatch("[^,]+") do
    out[#out + 1] = id
  end
  return out
end

local function save(ids)
  mediator.ask("setting.set", KEY, table.concat(ids, ","))
end

function M.add(id)
  local ids = M.ids()
  for _, x in ipairs(ids) do if x == id then return end end
  ids[#ids + 1] = id
  save(ids)
end

function M.remove(id)
  local out = {}
  for _, x in ipairs(M.ids()) do if x ~= id then out[#out + 1] = x end end
  save(out)
end

--- Flatten the categories into tool id -> the card that would be drawn for it.
local function index(cats)
  local by_id = {}
  for _, c in ipairs(cats) do
    for _, t in ipairs(c.tools) do
      by_id[t.id] = {
        id = t.id, name = t.name, path = t.path, writes = t.writes,
        -- Carried from the category, because a card on its own has to say where it came from and a
        -- tool never repeats what its family already knows.
        category = c.name, icon = c.icon,
      }
    end
  end
  return by_id
end

--- The favourites, in the order they were added.
--
-- An id whose tool is no longer contributed is dropped rather than drawn: a module can be removed
-- between two launches, and a card leading nowhere is worse than one card fewer. Same for a tool that
-- has lost its route, which is what a planned entry is.
function M.cards(cats)
  local by_id, out = index(cats), {}
  for _, id in ipairs(M.ids()) do
    local card = by_id[id]
    if card and card.path then out[#out + 1] = card end
  end
  return out
end

--- Everything not already kept, by category, for the picker.
--
-- Planned tools are listed and cannot be chosen. Hiding them would make the picker disagree with the
-- rail about what the workspace is going to be, and the answer to "why is DB2 to DBC not in here" is
-- worth one greyed line.
function M.available(cats)
  local chosen = {}
  for _, id in ipairs(M.ids()) do chosen[id] = true end

  local out = {}
  for _, c in ipairs(cats) do
    local mine = {}
    for _, t in ipairs(c.tools) do
      if not chosen[t.id] then
        mine[#mine + 1] = { id = t.id, name = t.name, path = t.path, writes = t.writes }
      end
    end
    if #mine > 0 then
      out[#out + 1] = { id = c.id, name = c.name, icon = c.icon, tools = mine }
    end
  end
  return out
end

return M
