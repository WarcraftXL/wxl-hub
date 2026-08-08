--[[
  The module catalogue.

  Every row comes from GitHub: the repository list from `topic:wxl-modules`, everything else from
  that repository's own wxl.json. There is no seed and no synthetic figure in here.

  A tagged repository with no manifest is not listed. Without one there is no id, no version and no
  statement of what installing it would do, so its card could only be a name and a guess. A manifest
  that parses but is wrong *is* listed, carrying its problems, because hiding a broken listing hides
  it from its author too.

  Facets are derived, never declared: a hand-kept category list drifts the first time an author
  invents one.
]]

local manifest = require("core.manifest")

-- `by_id` is the same rows again, keyed. Every page asks after a specific module: the library once
-- per installed row, the update check once per row again. Answering those by walking the list makes
-- the cost of a page grow with the size of the catalogue for no reason.
local M = { modules = {}, by_id = {} }

M.sorts = {
  { key = "stars",   label = "Most starred" },
  { key = "updated", label = "Recently updated" },
  { key = "name",    label = "Name" },
}

M.DEFAULT_SORT = "stars"

--- Rebuild from a boot payload. `repos` is the flattened search result; `listings` maps full_name to
--- `{ manifest = text, description = text }` and holds only the repositories that publish one.
---
--- Returns how many were listed and how many tagged repositories were passed over.
function M.build(repos, listings)
  M.modules, M.by_id, listings = {}, {}, listings or {}
  local skipped = 0

  for _, r in ipairs(repos or {}) do
    local entry = listings[r.full_name]
    -- Two owners can publish the same repository name and /store/:id keys on that name, so the first
    -- one listed wins. Counted as skipped rather than silently shadowed.
    if not entry or M.by_id[r.name] then
      skipped = skipped + 1
    else
      local rec = manifest.parse(entry.manifest, r)
      local row = {
        id          = rec.id,
        owner       = rec.owner,
        repo        = rec.repo,
        ref         = rec.ref,
        official    = rec.official,
        stars       = r.stars or 0,
        updated     = r.updated or "",
        tagline     = rec.listing.tagline,
        categories  = rec.listing.categories or {},
        complete    = rec.complete,
        installable = rec.installable,
        why_not     = rec.why_not,
        problems    = rec.problems,
        description = entry.description,
        rec         = rec,
      }
      M.modules[#M.modules + 1] = row
      -- Keyed on the repository name rather than on the manifest's id, because that is what
      -- /store/:id carries and what decided the clash above.
      M.by_id[r.name] = row
    end
  end

  return #M.modules, skipped
end

function M.get(id)
  return M.by_id[id]
end

-- Every comparator falls through to the id. Most repositories sit at zero stars and share an update
-- date, and without a tiebreak the order would shuffle between two renders of the same page.
local CMP = {
  stars   = function(a, b)
    if a.stars ~= b.stars then return a.stars > b.stars end
    return a.id < b.id
  end,
  updated = function(a, b)
    if a.updated ~= b.updated then return a.updated > b.updated end
    return a.id < b.id
  end,
  name    = function(a, b) return a.id < b.id end,
}

function M.sorted(key)
  local list = {}
  for i, v in ipairs(M.modules) do list[i] = v end
  table.sort(list, CMP[key] or CMP[M.DEFAULT_SORT])
  return list
end

function M.facets()
  local cats, authors, src = {}, {}, { official = 0, community = 0 }
  for _, x in ipairs(M.modules) do
    for _, c in ipairs(x.categories or {}) do cats[c] = (cats[c] or 0) + 1 end
    authors[x.owner] = (authors[x.owner] or 0) + 1
    if x.official then src.official = src.official + 1 else src.community = src.community + 1 end
  end
  local function rank(t)
    local out = {}
    for k, n in pairs(t) do out[#out + 1] = { key = k, n = n } end
    table.sort(out, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.key < b.key
    end)
    return out
  end
  return { categories = rank(cats), authors = rank(authors), source = src }
end

local function matches(x, f)
  if f.cat then
    local hit = false
    for _, c in ipairs(x.categories or {}) do if c == f.cat then hit = true; break end end
    if not hit then return false end
  end
  if f.author and x.owner ~= f.author then return false end
  if f.src == "official" and not x.official then return false end
  if f.src == "community" and x.official then return false end
  if f.q and f.q ~= "" then
    local hay = (x.id .. " " .. (x.owner or "") .. " " .. (x.tagline or "")):lower()
    if not hay:find(f.q:lower(), 1, true) then return false end
  end
  return true
end

--- Filter, then sort. `f` = { q, cat, author, src, sort }.
function M.query(f)
  f = f or {}
  local out = {}
  for _, x in ipairs(M.sorted(f.sort)) do
    if matches(x, f) then out[#out + 1] = x end
  end
  return out
end

function M.stats()
  local authors = {}
  for _, x in ipairs(M.modules) do authors[x.owner or "?"] = true end
  local n = 0
  for _ in pairs(authors) do n = n + 1 end
  return { modules = #M.modules, authors = n }
end

return M
