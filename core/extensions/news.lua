--[[
  The core manifest: news, support and the links the hub shows.

  Published by wxl-core itself, at the root of its repository, and fetched like any other manifest.
  That is the point: changing the Discord invite, retiring an announcement or rewording the support
  banner is a commit to wxl-core, not a new build of the hub.

  There is no built-in copy to fall back on, deliberately. Shipping a seed would mean an offline hub
  shows announcements that may be months stale and presents them as current, which is worse than
  showing nothing. When there is no document, `live()` is false and the home page steps aside for the
  library: what the user installed still works, and that is what an offline session is for.
]]

local json = require("deps.lua.json")

local M = {}

local doc = nil

--- Adopt a fetched document. Anything malformed leaves the previous one in place: a broken commit to
--- wxl-core must not empty the home page of every hub that fetches it.
function M.set(text)
  if type(text) ~= "string" or text == "" then return false, "empty" end
  local ok, parsed = pcall(json.decode, text)
  if not ok or type(parsed) ~= "table" then return false, "not valid JSON" end
  if parsed.kind ~= "core" then return false, "not a core manifest" end

  parsed.news    = type(parsed.news) == "table" and parsed.news or {}
  parsed.support = parsed.support or {}
  parsed.links   = parsed.links or {}
  parsed.core    = parsed.core or {}
  doc = parsed
  return true, #parsed.news
end

--- Is there a document at all? Everything that reads the feed has to check this first.
function M.live()
  return doc ~= nil
end

local function expired(entry, today)
  return entry.expires ~= nil and entry.expires < today
end

--- The feed, newest first, with expired entries dropped and the featured one separated out.
--
-- Sorted here rather than trusting the file's order: appending to the end of the array is the
-- natural way to add news, and it would otherwise put the newest item last.
function M.feed()
  if not doc then return { featured = nil, items = {}, all = {} } end

  local today = os.date("%Y-%m-%d")
  local items = {}
  for _, n in ipairs(doc.news) do
    if not expired(n, today) then items[#items + 1] = n end
  end
  table.sort(items, function(a, b) return (a.date or "") > (b.date or "") end)

  local featured, rest = nil, {}
  for _, n in ipairs(items) do
    if n.featured and not featured then featured = n else rest[#rest + 1] = n end
  end
  if not featured then featured = table.remove(rest, 1) end

  return { featured = featured, items = rest, all = items }
end

function M.support() return doc and doc.support or {} end
function M.links()   return doc and doc.links or {} end
function M.core()    return doc and doc.core or {} end

return M
