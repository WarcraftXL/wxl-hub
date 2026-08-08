--[[
  Parse and validate wxl.json (docs/03-contrats.md).

  Two rules shape everything here:

  1. The manifest is what makes a repository exist in the store. Without one there is no id, no
     version and no statement of what installing it would do, so there is nothing honest to put on a
     card. `from_repo` still exists, as the base a parsed record is filled in over: it holds
     everything GitHub already knows, so the manifest only has to carry what GitHub cannot.

  2. Validation never raises on author input. It returns a record plus a list of problems, because
     the store has to show a broken manifest *as broken* rather than vanish the repo.
]]

local json = require("deps.lua.json")

local M = {}

local SEMVER = "^(%d+)%.(%d+)%.(%d+)"

-- How a module says where its compiled binary lives.
--   release  a GitHub release asset, chosen at install time
--   shipped  a file committed in the repository, at deploy.path
--   source   built locally against a wxl-core checkout; the hub cannot do this for you
local DEPLOY_MODES = { release = true, shipped = true, source = true }

-- Paths in a listing are resolved against raw.githubusercontent by the hub itself. Anything that
-- could escape the repo, or point at a host the author controls, is refused: this content renders in
-- the WebView that holds the hub's token.
--
-- Named dangers, not a character allowlist. An ASCII-only allowlist would reject `téléchargement.jpg`
-- and every other accented filename, which is most of them outside English. Non-ASCII is not
-- what makes a path unsafe. UTF-8 is fine here because `asset_url` percent-encodes on the way out.
local function safe_path(p)
  if type(p) ~= "string" or p == "" then return nil, "not a string" end
  if p:match("^%a[%w+.-]*://")      then return nil, "must be a repo-relative path, not a URL" end
  if p:match("^//")                 then return nil, "must be a repo-relative path, not a URL" end
  if p:match("^[/\\]")              then return nil, "must be relative" end
  if p:match("^%a:")                then return nil, "must not be an absolute Windows path" end
  if p:find("\\", 1, true)          then return nil, "use forward slashes" end
  if p:find("%c")                   then return nil, "must not contain control characters" end
  -- Segment-wise, so `a..b.png` stays legal while `a/../b.png` does not.
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then return nil, "must not contain a '..' segment" end
  end
  -- `?` and `#` would cut the generated URL short and turn the rest into a query or fragment.
  if p:find("[?#]")                 then return nil, "must not contain '?' or '#'" end
  return p
end

--- Percent-encode a repo path for use in a URL, leaving separators intact.
function M.encode_path(p)
  return (p:gsub("[^%w%-%._~/]", function(c) return ("%%%02X"):format(c:byte()) end))
end

--- Absolute raw.githubusercontent URL for a path the manifest declared.
--
-- The hub builds this; the manifest never supplies a URL. That is the whole reason a listing cannot
-- phone home.
function M.asset_url(rec, path)
  if not path then return nil end
  return ("https://raw.githubusercontent.com/%s/%s/%s")
    :format(rec.repo, rec.ref or "main", M.encode_path(path))
end

local function is_semver(v)
  return type(v) == "string" and v:match(SEMVER) ~= nil
end

--- Compare two semver strings. Returns -1, 0 or 1. Pre-release tags are ignored.
function M.compare(a, b)
  local am, an, ap = tostring(a):match(SEMVER)
  local bm, bn, bp = tostring(b):match(SEMVER)
  if not am or not bm then return 0 end
  for i, pair in ipairs { { am, bm }, { an, bn }, { ap, bp } } do
    local x, y = tonumber(pair[1]), tonumber(pair[2])
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

--- Does `version` satisfy a requirement like ">=1.0.0", "1.2.3" or "*"?
function M.satisfies(version, req)
  if req == nil or req == "*" then return true end
  local op, want = tostring(req):match("^%s*([<>=]*)%s*(.+)$")
  local c = M.compare(version, want)
  if op == "" or op == "=" then return c == 0 end
  if op == ">=" then return c >= 0 end
  if op == ">"  then return c > 0 end
  if op == "<=" then return c <= 0 end
  if op == "<"  then return c < 0 end
  return false
end

--- Build a record from GitHub repository metadata, with no manifest present.
function M.from_repo(repo)
  return {
    id       = repo.name,
    repo     = repo.full_name,
    owner    = repo.owner,
    official = (repo.full_name or ""):match("^WarcraftXL/") ~= nil,
    ref      = repo.default_branch or "main",
    listing  = {
      title       = repo.name,
      tagline     = repo.description,
      description = nil,
      categories  = {},
    },
    extension = nil,
    problems  = { { level = "info", field = "wxl.json", message = "no manifest in this repository" } },
    complete  = false,
  }
end

--- Parse and validate a manifest. `repo` is the GitHub metadata it belongs to.
--
-- Never raises: returns a record whose `problems` list carries everything wrong with it.
function M.parse(text, repo)
  repo = repo or {}
  local rec = M.from_repo(repo)
  rec.problems = {}

  local ok, doc = pcall(json.decode, text)
  if not ok or type(doc) ~= "table" then
    rec.problems[#rec.problems + 1] =
      { level = "error", field = "wxl.json", message = "not valid JSON" }
    return rec
  end

  local function problem(level, field, message)
    rec.problems[#rec.problems + 1] = { level = level, field = field, message = message }
  end

  if doc.manifest ~= 1 then
    problem("error", "manifest", "unsupported manifest version: " .. tostring(doc.manifest))
  end

  -- extension --------------------------------------------------------------
  local e = doc.extension
  if type(e) ~= "table" then
    problem("error", "extension", "missing")
  else
    if type(e.id) ~= "string" or e.id == "" then
      problem("error", "extension.id", "missing")
    elseif repo.name and e.id ~= repo.name then
      -- Not fatal: an author may rename the repo. But the id is what everything else keys on, so a
      -- silent mismatch would make dependencies point at nothing.
      problem("warn", "extension.id",
              ("does not match the repository name (%s)"):format(repo.name))
    end

    if not is_semver(e.version) then
      problem("error", "extension.version", "must be semver, got " .. tostring(e.version))
    end
    if type(e.abi) ~= "string" then
      problem("error", "extension.abi", "missing, so the hub cannot tell if this loads")
    end
    if type(e.entry) ~= "string" or not e.entry:match("%.dll$") then
      problem("error", "extension.entry", "must name the module's .dll")
    end

    for _, p in ipairs(e.assets or {}) do
      local _, why = safe_path(p)
      if why then problem("error", "extension.assets", ("%q: %s"):format(tostring(p), why)) end
    end

    for id, range in pairs(e.requires or {}) do
      if type(range) ~= "string" then
        problem("error", "extension.requires", ("%s: range must be a string"):format(id))
      end
    end

    for i, h in ipairs(e.hooks or {}) do
      if type(h) ~= "table" or type(h.target) ~= "string" then
        problem("error", ("extension.hooks[%d]"):format(i), "needs a target")
      elseif h.priority ~= nil and type(h.priority) ~= "number" then
        problem("error", ("extension.hooks[%d].priority"):format(i), "must be a number")
      end
    end

    rec.extension = e
  end

  -- listing ----------------------------------------------------------------
  local l = doc.listing or {}
  if type(l) ~= "table" then
    problem("error", "listing", "must be an object")
    l = {}
  end

  local listing = {
    title      = type(l.title) == "string" and l.title or rec.listing.title,
    tagline    = type(l.tagline) == "string" and l.tagline or rec.listing.tagline,
    categories = type(l.categories) == "table" and l.categories or {},
    accent     = type(l.accent) == "string" and l.accent:match("^#%x%x%x%x%x%x$") or nil,
    gallery    = {},
  }

  -- `description` names a Markdown file in the repo; it is not the text itself. That keeps index.json
  -- small (the body is fetched only when a listing is opened) and lets authors point at the README
  -- they already maintain. It buys no safety on its own, since the rendering rules do that, so the
  -- file is escaped and allowlisted exactly like an inline string would have been.
  local desc = l.description
  if desc == nil then
    listing.description = "README.md"
  else
    local p, why = safe_path(desc)
    if p and p:lower():match("%.md$") then
      listing.description = p
    else
      problem("error", "listing.description",
              why or "must name a .md file in the repository")
    end
  end

  if l.cover then
    local p, why = safe_path(l.cover)
    if p then listing.cover = p else problem("error", "listing.cover", why) end
  end
  for i, g in ipairs(l.gallery or {}) do
    local p, why = safe_path(g)
    if p then listing.gallery[#listing.gallery + 1] = p
    else problem("error", ("listing.gallery[%d]"):format(i), why) end
  end
  if l.accent and not listing.accent then
    problem("warn", "listing.accent", "must be #rrggbb")
  end

  rec.listing   = listing
  rec.license   = doc.license
  rec.signature = doc.signature

  -- deploy -----------------------------------------------------------------
  -- Where the built binary comes from. Absent is not an error: a repository carries a listing long
  -- before it has anything to ship, and refusing the manifest over it would hide the module instead
  -- of the gap.
  local d = doc.deploy
  if d ~= nil then
    if type(d) ~= "table" then
      problem("error", "deploy", "must be an object")
    elseif not DEPLOY_MODES[d.mode] then
      problem("error", "deploy.mode",
              "must be release, shipped or source, got " .. tostring(d.mode))
    else
      local deploy = { mode = d.mode }
      if d.mode == "shipped" then
        -- Same path rules as a listing asset: repo-relative, no URL, no climbing out.
        local p, why = safe_path(d.path)
        if p then deploy.path = p else problem("error", "deploy.path", why or "missing") end
      elseif d.mode == "release" then
        if d.match ~= nil and type(d.match) ~= "string" then
          problem("error", "deploy.match", "must be a string like \"*.zip\"")
        else
          deploy.match = d.match
        end
      end
      rec.deploy = deploy
    end
  end

  local errors = 0
  for _, p in ipairs(rec.problems) do
    if p.level == "error" then errors = errors + 1 end
  end
  rec.complete = errors == 0 and rec.extension ~= nil

  -- Installable is narrower than complete: it also needs somewhere to fetch a binary from, in a mode
  -- this machine can carry out. `source` builds against a local wxl-core checkout and belongs to the
  -- developer flow, not to a one-click install.
  if not rec.complete then
    rec.why_not = "the manifest has errors"
  elseif not rec.deploy then
    rec.why_not = "this manifest does not say where its binary comes from"
  elseif rec.deploy.mode == "source" then
    rec.why_not = "this module is built from source, against a local wxl-core"
  end
  rec.installable = rec.why_not == nil

  return rec
end

--- Is this extension loadable against the running SDK?
function M.abi_ok(rec, host_abi)
  if not rec.extension or not rec.extension.abi then return false, "no ABI declared" end
  if rec.extension.abi ~= host_abi then
    return false, ("built for ABI %s, this hub speaks %s"):format(rec.extension.abi, host_abi)
  end
  return true
end

return M
