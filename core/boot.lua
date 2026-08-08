--[[
  Startup fetch, off the event loop.

  WinHTTP blocks its thread. Doing the boot fetch inline would freeze the server before it ever
  answered, so the work runs on libuv's threadpool (`uv.new_work`) while the loop serves the splash
  screen. Threadpool workers get their own Lua state and can only hand back primitives, so the result
  crosses the boundary as one JSON string.

  With the cache warm this whole thing resolves in microseconds and the splash is a flash. The point
  is the cold path: first run, expired cache, or no network.
]]

local uv    = require("uv")
local json  = require("deps.lua.json")
local cache = require("core.cache")
local news  = require("core.news")

local TOPIC     = "wxl-modules"
local CORE_REPO = "WarcraftXL/wxl-core"

-- The shape of the payload is part of the key. A cached copy written by an older build decodes
-- without error and then quietly comes up short, which reads as "nobody published anything" rather
-- than as a stale cache. Bump this whenever `job` changes what it returns.
local KEY = "boot.2"

local M = {
  state   = "loading",   -- loading | ready | offline
  -- Where the data came from: network (fetched this session), cache (fresh, no fetch needed) or
  -- stale (the fetch failed and an expired copy was used). Only the last one warrants a warning.
  source  = nil,
  steps   = {},
  -- Every tagged repository, flattened. `listings` holds only those that publish a manifest, keyed
  -- by full_name.
  repos    = nil,
  listings = nil,
  age      = nil,

  started  = 0,
  KEY      = KEY,

  -- Bumped every time the data is replaced. Anything that folds the payload into its own shape (the
  -- catalogue, for one) compares this to what it last built from, so a refresh is not something each
  -- consumer has to be told about individually.
  generation = 0,
}

-- Where the worker writes what it is doing. The splash reads it; nothing else does.
local PROGRESS = ((os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("[/\\]+$", ""))
                 .. "/wxl-boot.progress"

local function step(s)
  M.steps[#M.steps + 1] = s
  print("  " .. s)
end

-- Runs in a threadpool Lua state: no upvalues, no shared globals, primitives in and out.
local function job(topic, core_repo, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path
  local http     = require("ffi.winhttp")
  local json     = require("deps.lua.json")
  local manifest = require("core.manifest")

  local RAW = "https://raw.githubusercontent.com/"

  local out = { steps = {}, listings = {} }

  -- Two audiences. `steps` is the log, handed back at the end and printed for whoever is reading
  -- the console. The file is for the splash, which needs to know what is happening *now* and cannot
  -- wait for the work to finish to be told.
  local function say(text)
    local fd = io.open(progress_path, "wb")
    if fd then fd:write(text); fd:close() end
  end

  local function note(s) out.steps[#out.steps + 1] = s end

  local ok, err = pcall(function()
    say("Asking GitHub which repositories carry the topic")
    local s = http.get("https://api.github.com/search/repositories?q=topic:" .. topic
                       .. "&per_page=100",
                       { headers = { "User-Agent: wxl-hub", "Accept: application/vnd.github+json" } })
    note("topic:" .. topic .. " " .. s.status)
    out.search = s.status == 200 and s.body or nil

    if out.search then
      local items, found = json.decode(out.search).items or {}, 0
      for i, r in ipairs(items) do
        say(("Reading manifests, %d of %d"):format(i, #items))
        -- Not every repository is on `main`: the default branch has to come from the search result
        -- or a third of the catalogue answers 404.
        local ref = r.default_branch or "main"
        local m = http.get(RAW .. r.full_name .. "/" .. ref .. "/wxl.json")
        if m.status == 200 then
          found = found + 1
          local entry = { manifest = m.body }

          -- The description path is author input that turns into a URL, so it goes through the same
          -- validator the store uses rather than being trusted as written.
          local rec = manifest.parse(m.body, { name = r.name, full_name = r.full_name,
                                               default_branch = ref })
          local url = manifest.asset_url(rec, rec.listing.description)
          if url then
            local d = http.get(url)
            entry.description = d.status == 200 and d.body or nil
          end

          out.listings[r.full_name] = entry
        end
      end
      -- Descriptions are pulled here rather than when a listing opens because they scale with the
      -- number of *listed* modules, not with the topic: a repository without a manifest is not in
      -- the store and has nothing to describe. Past a few dozen listings, move this to the detail
      -- route.
      note(("%d of %d repositories publish a manifest"):format(found, #items))
    end

    -- wxl-core publishes the news, the support banner and the links at its own repository root, so
    -- editing any of them is a commit there rather than a new build of the hub.
    say("Reading the announcements from wxl-core")
    local c = http.get(RAW .. core_repo .. "/main/wxl.json")
    note("wxl-core/wxl.json " .. c.status)
    out.core = c.status == 200 and c.body or nil
  end)

  if not ok then out.error = tostring(err) end
  return json.encode(out)
end

--- Flatten the search result into the fields a listing is built from. Field names match what
--- `manifest.parse` expects of its repo argument.
local function repo_list(body)
  local ok, doc = pcall(json.decode, body)
  if not ok or type(doc) ~= "table" or type(doc.items) ~= "table" then return {} end
  local out = {}
  for _, r in ipairs(doc.items) do
    out[#out + 1] = {
      name           = r.name,
      full_name      = r.full_name,
      default_branch = r.default_branch or "main",
      owner          = r.owner and r.owner.login or nil,
      description    = r.description,
      stars          = r.stargazers_count or 0,
      updated        = (r.updated_at or ""):sub(1, 10),
    }
  end
  return out
end

local function adopt(payload_json, from_cache)
  local ok, out = pcall(json.decode, payload_json)
  if not ok or type(out) ~= "table" then
    M.state = "offline"
    step("payload unreadable")
    return
  end

  -- The steps travel inside the payload, so replaying them on a cache hit prints a fetch that did
  -- not happen. They are still worth showing, since they say what the cached copy is made of, but
  -- they have to be introduced as history rather than as news.
  local recorded = out.steps or {}
  if from_cache and #recorded > 0 then step("what that fetch had found:") end
  for _, s in ipairs(recorded) do step(s) end
  if out.error then step("error: " .. out.error) end

  if out.search then
    M.repos = repo_list(out.search)
    -- An empty table encodes as a JSON array, so this comes back as a list rather than a map when
    -- nothing published. Either way the lookups below miss, which is the right answer.
    M.listings = type(out.listings) == "table" and out.listings or {}
  end

  if out.core then
    local took, why = news.set(out.core)
    step(took and ("core manifest: " .. why .. " news item(s)")
              or ("core manifest ignored: " .. tostring(why)))
  end

  -- Reaching the topic search at all proves there is a network, even in the case where nobody
  -- publishes a manifest yet and the store comes back empty.
  M.state = ((M.repos and #M.repos > 0) or news.live()) and "ready" or "offline"
  M.generation = M.generation + 1
  if from_cache then step("served from cache") end
end

--- Milliseconds since the boot began.
function M.elapsed()
  uv.update_time()
  return uv.now() - M.started
end

--- The data has landed. Nothing is held back for effect: the splash lasts exactly as long as the
--- work does, which on a warm cache is a single frame.
function M.ready()
  return M.state ~= "loading"
end

--- What the worker is doing right now, for the splash.
--
-- Read from a file rather than returned by the worker, because the worker returns once and the
-- splash needs an answer every time it asks. The last completed step is the fallback for the
-- moments before the fetch starts.
function M.phase()
  local fd = io.open(PROGRESS, "rb")
  if fd then
    local text = fd:read("*a")
    fd:close()
    if text and text ~= "" then return text end
  end
  return M.steps[#M.steps] or "Starting up"
end

--- Is the cached copy past its life? True also when there is none.
function M.due()
  return cache.get(KEY) == nil
end

--- How old the data on screen is, right now.
--
-- `M.age` is what it was when it was adopted, which is what decided whether to warn about it. This
-- is what it is at the moment of asking, which is the only version worth showing anyone: the other
-- one freezes at boot and still claims the same number an hour later.
function M.age_now()
  return cache.age(KEY)
end

--- Fetch again while the window is open, without disturbing what is on screen.
--
-- Nothing about this touches `state`. The splash is gated on `state`, so a refresh that reset it
-- would throw the user back to the loading screen every half hour; and a refresh that fails must
-- leave the good data standing rather than declare the hub offline. Only a payload that actually
-- carries a search result replaces anything.
function M.refresh()
  if M.refreshing then return false end
  M.refreshing = true

  local work
  work = uv.new_work(job, function(payload)
    M.refreshing = false
    os.remove(PROGRESS)
    if not payload or payload == "" then return end

    local ok, out = pcall(json.decode, payload)
    if not ok or type(out) ~= "table" or not out.search then
      step("refresh failed, keeping what we had")
      return
    end

    cache.put(KEY, payload, cache.DEFAULT_TTL)
    adopt(payload, false)
    M.age, M.source = 0, "network"
  end)
  uv.queue_work(work, TOPIC, CORE_REPO, PROGRESS)
  return true
end

--- Kick off the boot. Returns immediately; `M.state` flips when it lands.
function M.start(ttl)
  ttl = ttl or cache.DEFAULT_TTL
  uv.update_time()
  M.started = uv.now()

  os.remove(PROGRESS)

  local fresh, age = cache.get(KEY)
  if fresh then
    M.age, M.source = age, "cache"
    step(("cache hit (%ds old)"):format(age))
    adopt(fresh, true)
    return
  end

  local staleValue, _, staleAge = cache.stale(KEY)
  step("cache miss, fetching")

  local work
  work = uv.new_work(job, function(payload)
    if payload and payload ~= "" then
      cache.put(KEY, payload, ttl)
      adopt(payload, false)
      if M.state == "ready" then M.age, M.source = 0, "network" end
    end

    -- Nothing usable came back. Falling back to an expired copy is better than an empty hub, but the
    -- user has to be told: this is the one case where the hub knowingly shows data it cannot vouch
    -- for, and presenting it silently as current would be a lie.
    if M.state ~= "ready" and staleValue then
      step("network unreachable, using the expired copy")
      adopt(staleValue, true)
      M.age, M.source = staleAge, "stale"
      M.state = "ready"
    elseif M.state ~= "ready" then
      M.source = nil
      M.state = "offline"
    end

    os.remove(PROGRESS)
  end)
  uv.queue_work(work, TOPIC, CORE_REPO, PROGRESS)
end

return M
