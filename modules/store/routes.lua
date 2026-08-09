local catalogue = dofile("modules/store/models/catalogue.lua")
local page      = require("core.ui.page")
local history   = require("core.history")
local manifest  = require("core.extensions.manifest")
local markdown  = require("core.base.markdown")
local mediator  = require("core.base.mediator")
local install   = require("core.extensions.install")
local jobs      = require("core.jobs")

local function urlencode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

--- Builds a /store URL from the active filters plus one override.
--
-- Clicking the facet that is already active clears it, which is what makes the sidebar a set of
-- toggles rather than a one-way trip. `keep = true` opts out, for sort.
local function make_href(f)
  return function(over)
    over = over or {}
    local merged = { q = f.q, cat = f.cat, author = f.author, src = f.src, sort = f.sort }
    for k, v in pairs(over) do
      if k ~= "keep" then
        -- Spelled out rather than `cond and nil or v`: that idiom cannot produce nil, because nil is
        -- falsy and the `or` branch always wins. Toggling off would silently never happen.
        if not over.keep and merged[k] == v then merged[k] = nil else merged[k] = v end
      end
    end
    local parts = {}
    for _, k in ipairs { "q", "cat", "author", "src", "sort" } do
      if merged[k] and merged[k] ~= "" then parts[#parts + 1] = k .. "=" .. urlencode(merged[k]) end
    end
    return #parts == 0 and "/store" or ("/store?" .. table.concat(parts, "&"))
  end
end

-- `sort` is left nil when the user has not chosen one, so the default never shows up in the URL.
local function filters_from(req)
  local q = req.query
  return { q = q.q, cat = q.cat, author = q.author, src = q.src, sort = q.sort }
end

local function take(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i] end
  return out
end

local function label_for(key)
  for _, s in ipairs(catalogue.sorts) do if s.key == key then return s.label end end
  return catalogue.sorts[1].label
end

return function(router, mod, ctx)
  local view = mod.view

  -- The catalogue is a fold over the boot payload, and the boot resolves after the modules have
  -- loaded. Building on first use rather than at load time removes the ordering question entirely:
  -- no route can run before the splash gate opens, and the splash gate waits on the boot.
  --
  -- Keyed on the boot's generation rather than a flag, so a refresh while the window is open is
  -- picked up on the next page without the boot having to know this module exists.
  local built_from, tagged = -1, 0
  local function cat()
    if ctx.boot and ctx.boot.state ~= "loading" and ctx.boot.generation ~= built_from then
      built_from = ctx.boot.generation
      local listed, skipped = catalogue.build(ctx.boot.repos, ctx.boot.listings)
      tagged = listed + skipped
      print(("  catalogue: %d listed of %d tagged"):format(listed, tagged))
    end
    return catalogue
  end

  -- What the store can answer for anyone who asks. No other module knows this file exists.
  mediator.provide("catalogue.stats", function() return cat().stats() end)
  mediator.provide("catalogue.get",   function(id) return cat().get(id) end)
  mediator.provide("catalogue.top",   function(n) return take(cat().sorted(), n or 10) end)
  -- Read at the moment it is asked for, not carried over from the boot. The footer is on every page
  -- for the whole session, so a number frozen at startup is wrong within minutes and stays wrong.
  mediator.provide("catalogue.age",   function()
    local age = ctx.boot and ctx.boot.age_now and ctx.boot.age_now()
    if not age then return "live" end
    if age < 90 then return "just now" end
    if age < 5400 then return math.floor(age / 60) .. "m old" end
    return math.floor(age / 3600) .. "h old"
  end)

  local function rail(sort)
    sort = sort or catalogue.DEFAULT_SORT
    return view.render("rail", {
      modules = take(cat().sorted(sort), 10),
      total   = #cat().modules,
      sorts   = catalogue.sorts,
      sort    = sort,
      heading = label_for(sort),
    })
  end

  -- A section on the home page. Home does not know it is the store that filled this in.
  mediator.contribute("home.section", { id = "store", order = 20, render = function() return rail() end })

  local function body(f)
    return view.render("storebody", {
      f = f, facets = cat().facets(), results = cat().query(f),
      sorts = catalogue.sorts, href = make_href(f), default_sort = catalogue.DEFAULT_SORT,
    })
  end

  router:get("/store", function(req, res)
    local f = filters_from(req)
    if req.htmx then return res:html(body(f)) end

    local facets = cat().facets()
    res:html(page.render(view.render("store", {
      f = f, facets = facets, results = cat().query(f), sorts = catalogue.sorts,
      href = make_href(f), trail = { { "Home", "/" }, { "Store" } },
      default_sort = catalogue.DEFAULT_SORT,
      total = #cat().modules, tagged = tagged, authors = #facets.authors,
    }), { title = "Store", active = "store" }))
  end)

  -- The home rail sorts in place. It lives here because the markup does.
  router:get("/store/rail", function(req, res)
    res:html(rail(req.query.sort))
  end)

  router:get("/store/:id", function(req, res)
    local row = cat().get(req.params.id)
    if not row then
      return res:html(page.notice {
        title = "No such module",
        text  = "Nothing in the catalogue answers to that name. It may have dropped its manifest, "
             .. "or the repository may no longer carry the topic.",
        code  = req.params.id,
      })
    end

    local rec = row.rec

    history.record {
      kind = "module", ref = row.id, href = "/store/" .. row.id,
      title = rec.listing.title, subtitle = row.owner or "unknown author",
    }

    -- Rendered once per module per session. `false` rather than nil so a module with no description
    -- is not re-rendered on every visit.
    if row.html == nil then
      row.html = row.description and markdown.render(row.description) or false
    end

    local shots = {}
    for _, g in ipairs(rec.listing.gallery or {}) do
      shots[#shots + 1] = manifest.asset_url(rec, g)
    end

    res:html(page.render(view.render("listing", {
      rec = rec, ext = rec.extension or {},
      installed = mediator.ask("library.installed", row.id),
      cover = manifest.asset_url(rec, rec.listing.cover),
      shots = shots,
      body_html = row.html or "<p><em>No description file.</em></p>",
      log = (ctx.boot and ctx.boot.steps) or {},
      trail = { { "Home", "/" }, { "Store", "/store" }, { rec.listing.title } },
    }), {
      title = rec.listing.title, active = "store", untrusted = true,
    }))
  end)

  -- Answers with the same progress fragment the poll endpoint returns, including for a refusal: one
  -- element, one shape, whatever happened.
  router:post("/store/:id/install", function(req, res)
    local function refuse(why)
      res:html(view.render("core:job", { job = { state = "failed", error = why } }))
    end

    local client = mediator.ask("client.inspect")
    if not client or not client.ok then
      return refuse("No usable client is set for this profile. Settings has the details.")
    end

    local job, why = install.start(cat().get(req.params.id), client.path)
    if not job then return refuse(why) end

    mediator.emit("module.installing", req.params.id)
    res:html(view.render("core:job", { job = jobs.view(job) }))
  end)
end
