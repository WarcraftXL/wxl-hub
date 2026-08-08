--[[
  Installing and removing an extension.

  The core loads `Extensions\<id>\<id>.dll`, resolved against the folder holding Wow.exe, and the
  DLL must carry its folder's name. That single sentence dictates everything below: what a valid
  archive is, where files land, and why an install that cannot produce that one file is refused
  before it touches anything.

  Nothing is written onto a live install. The download is unpacked into a sibling folder, checked,
  and only then swapped in. An install that fails half way leaves the previous one exactly as it was.
]]

local uv    = require("uv")
local jobs  = require("core.jobs")
local db    = require("core.db")

local M = {}

-- Runs in a threadpool Lua state. No upvalues: this function is dumped and reloaded somewhere else,
-- and anything it closes over would arrive as nil. Every helper it needs is therefore inside it.
local function worker(args_json, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path

  local json  = require("deps.lua.json")
  local http  = require("ffi.winhttp")
  local miniz = require("miniz")
  local uv    = require("uv")
  local ossl  = require("openssl")

  local a = json.decode(args_json)

  -- Throttled, because the download reports every 64 KB and that is roughly a thousand rewrites a
  -- second on a fast line. The reader is on another thread with no lock between them, so each extra
  -- rewrite is another chance to be caught mid-write; a phase change always gets through.
  local last_write, last_phase = 0, nil
  local function note(phase, done, total)
    local ms = tonumber(uv.hrtime() / 1e6)
    if phase == last_phase and ms - last_write < 100 then return end
    last_write, last_phase = ms, phase

    local fd = io.open(progress_path, "wb")
    if fd then
      fd:write(("%s\n%d\n%d\n"):format(phase, math.floor(done or 0), math.floor(total or 0)))
      fd:close()
    end
  end

  local function rmtree(dir)
    local scan = uv.fs_scandir(dir)
    if not scan then return end
    while true do
      local name, kind = uv.fs_scandir_next(scan)
      if not name then break end
      local p = dir .. "/" .. name
      if kind == "directory" then rmtree(p) else uv.fs_unlink(p) end
    end
    uv.fs_rmdir(dir)
  end

  local function mkdirs(dir)
    local so_far = ""
    for part in dir:gmatch("[^/\\]+") do
      so_far = so_far == "" and part or (so_far .. "/" .. part)
      -- The first segment of an absolute Windows path is the drive, which cannot be created.
      if not so_far:match("^%a:$") then uv.fs_mkdir(so_far, tonumber("755", 8)) end
    end
  end

  -- A glob, not a regex: only '*' is a wildcard and everything else is literal, which is what an
  -- author writing "*.zip" expects.
  local function glob(g)
    return "^" .. g:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  end

  local ok, out = pcall(function()
    local result = { id = a.id }

    -- 1. where the bytes are ------------------------------------------------
    local url
    if a.mode == "release" then
      note("looking up the latest release", 0, 0)
      local r = http.get("https://api.github.com/repos/" .. a.repo .. "/releases?per_page=20",
        { headers = { "User-Agent: wxl-hub", "Accept: application/vnd.github+json" } })
      if r.status ~= 200 then
        error(("GitHub answered %d for the release list"):format(r.status))
      end

      local chosen
      for _, rel in ipairs(json.decode(r.body)) do
        if not rel.draft and not rel.prerelease then chosen = rel; break end
      end
      if not chosen then error("this repository has published no release yet") end
      result.version = tostring(chosen.tag_name or ""):gsub("^v", "")

      local want, asset = a.match and glob(a.match) or nil, nil
      for _, x in ipairs(chosen.assets or {}) do
        if not want or x.name:match(want) then asset = x; break end
      end
      if not asset then
        error(a.match
              and ("no asset in %s matches %s"):format(tostring(chosen.tag_name), a.match)
              or  ("release %s carries no asset"):format(tostring(chosen.tag_name)))
      end
      url = asset.browser_download_url
      result.source = ("%s from %s"):format(asset.name, tostring(chosen.tag_name))
    else
      url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(a.repo, a.ref, a.path)
      result.version = a.version
      result.source = a.path
    end

    -- 2. down it comes ------------------------------------------------------
    local blob = a.temp .. "/wxl-install-" .. a.id .. ".bin"
    note("downloading", 0, 0)
    local got = http.download(url, blob, {
      headers  = { "User-Agent: wxl-hub" },
      on_chunk = function(done, total) note("downloading", done, total) end,
    })
    if got.status ~= 200 then error(("the download answered %d"):format(got.status)) end
    result.etag = got.etag

    -- 3. unpack beside the destination, never onto it -----------------------
    local ext   = a.client .. "/Extensions"
    local final = ext .. "/" .. a.id
    local stage = ext .. "/" .. a.id .. ".wxl-new"
    mkdirs(ext)
    rmtree(stage)
    mkdirs(stage)

    note("unpacking", 0, 0)
    local written = {}

    local probe = io.open(blob, "rb")
    local magic = probe and probe:read(4) or nil
    if probe then probe:close() end

    if magic == "PK\3\4" then
      local zip = miniz.new_reader(blob)
      if not zip then error("the download is not a readable archive") end

      -- Zip names are not normalised. An archive built on Windows writes backslashes, and one built
      -- from a GitHub tree wraps everything in a single top folder. Both have to go, or the DLL
      -- lands one level below where the core looks for it.
      local names, prefix = {}, nil
      for i = 1, zip:get_num_files() do
        if not zip:is_directory(i) then
          local name = zip:get_filename(i):gsub("\\", "/")
          names[i] = name
          local head = name:match("^([^/]+)/")
          if not head then prefix = false
          elseif prefix == nil then prefix = head
          elseif prefix ~= head then prefix = false end
        end
      end
      local strip = type(prefix) == "string" and prefix or nil

      for i, name in pairs(names) do
        local rel = strip and name:sub(#strip + 2) or name
        if rel ~= "" then
          local dest = stage .. "/" .. rel
          mkdirs(dest:match("^(.*)/[^/]*$") or stage)
          local data = zip:extract(i)
          local w = io.open(dest, "wb")
          if not w then error("cannot write " .. dest) end
          w:write(data)
          w:close()
          written[#written + 1] = { path = rel, sha256 = ossl.digest.digest("sha256", data) }
        end
      end
    else
      -- A bare DLL. The core requires it to carry its folder's name, so that is what it is called
      -- here whatever the asset happened to be called.
      local fd = io.open(blob, "rb")
      if not fd then error("the download went missing before it could be read") end
      local data = fd:read("*a")
      fd:close()

      local rel = a.id .. ".dll"
      local w = io.open(stage .. "/" .. rel, "wb")
      if not w then error("cannot write into " .. stage) end
      w:write(data)
      w:close()
      written[#written + 1] = { path = rel, sha256 = ossl.digest.digest("sha256", data) }
    end

    -- 4. it has to be loadable before it replaces anything ------------------
    local dll, found = a.id .. ".dll", false
    for _, f in ipairs(written) do
      if f.path:lower() == dll:lower() then found = true end
    end
    if not found then
      rmtree(stage)
      error(("this package holds no %s, which is the name the core loads"):format(dll))
    end

    -- 5. swap ---------------------------------------------------------------
    note("installing", 0, 0)
    rmtree(final)
    local moved, why = uv.fs_rename(stage, final)
    if not moved then
      rmtree(stage)
      error("could not put it in place: " .. tostring(why))
    end

    os.remove(blob)
    result.files = written
    return result
  end)

  if not ok then
    -- Everything raised above is written for the person who clicked Install, so the "file:line: "
    -- Lua prepends is noise in front of it. Only this file's own frames are stripped: an error
    -- surfacing from the HTTP or zip layer keeps its position, because that one is a bug report.
    return json.encode { error = (tostring(out):gsub("^%.?[%w/\\]*install%.lua:%d+: ", "")) }
  end
  return json.encode(out)
end

local function scratch()
  return (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("[/\\]+$", "")
end

--- Queue an install. `row` is a catalogue row; `client` the validated client folder.
--
-- Returns the job, or nil plus a reason. Refusing here rather than inside the worker keeps the
-- reasons a user can act on out of the thread that cannot explain itself.
function M.start(row, client)
  if not row then return nil, "no such module" end
  if not row.rec.installable then return nil, row.rec.why_not or "this module cannot be installed" end
  if not client or client == "" then return nil, "no client folder is set for this profile" end

  local running = jobs.busy(row.id)
  if running then return nil, "already installing" end

  local deploy = row.rec.deploy
  return jobs.start {
    kind  = "install",
    ref   = row.id,
    label = row.rec.listing.title or row.id,
    work  = worker,
    args  = {
      id      = row.id,
      repo    = row.repo,
      ref     = row.ref,
      mode    = deploy.mode,
      path    = deploy.path,
      match   = deploy.match,
      version = row.rec.extension and row.rec.extension.version or "0.0.0",
      client  = client,
      temp    = scratch(),
    },
    on_done = function(job)
      local r = job.result
      db.transaction(function()
        db.run([[INSERT INTO installed (id, version, abi, repo, source, etag, enabled, installed_at)
                 VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                 ON CONFLICT(id) DO UPDATE SET
                   version = excluded.version, abi = excluded.abi, repo = excluded.repo,
                   source = excluded.source, etag = excluded.etag,
                   installed_at = excluded.installed_at]],
               r.id, r.version or "0.0.0",
               row.rec.extension and row.rec.extension.abi or nil,
               row.repo, r.source, r.etag, os.time())

        -- Rewritten wholesale rather than merged: the previous version's file list describes files
        -- that are no longer there, and keeping them would make the next uninstall reach for them.
        db.run("DELETE FROM deployed WHERE id = ?", r.id)
        for _, f in ipairs(r.files or {}) do
          db.run("INSERT INTO deployed (id, path, sha256) VALUES (?, ?, ?)", r.id, f.path, f.sha256)
        end
      end)
    end,

    -- The page that started this already shows the outcome. This is for the person who navigated
    -- away while it ran, which is most of them once a download takes more than a moment.
    on_settle = function(job)
      local notify = require("core.notify")
      if job.state == "done" then
        notify.raise {
          kind = "install", ref = row.id, level = "good",
          title = (job.label or row.id) .. " installed",
          body  = "version " .. tostring(job.result and job.result.version or "?"),
          href  = "/library",
        }
      else
        notify.raise {
          kind = "install", ref = row.id, level = "bad",
          title = "Could not install " .. (job.label or row.id),
          body  = job.error,
          href  = "/store/" .. row.id,
        }
      end
    end,
  }
end

--- Where an extension's folder is, enabled or not.
--
-- The core skips any folder whose name starts with a dot (runtime/Extensions.cpp), so a leading dot
-- is how a module is turned off. That is the whole mechanism: no flag file, no manifest to rewrite,
-- and nothing for the core to learn. A database column alone would have been a lie, since the core
-- loads whatever it finds.
local function folders(client, id)
  local ext = client .. "/Extensions"
  return ext .. "/" .. id, ext .. "/." .. id
end

--- Turn an installed module on or off on disk. Returns true, or nil plus a reason.
function M.set_enabled(id, on, client)
  if not client or client == "" then return nil, "no client folder is set for this profile" end

  local live, off = folders(client, id)
  local from, to  = (on and off or live), (on and live or off)

  if uv.fs_stat(to) and not uv.fs_stat(from) then return true end   -- already how it was asked for
  if not uv.fs_stat(from) then
    return nil, "its folder is not in the client, so there is nothing to " .. (on and "enable" or "disable")
  end

  local moved, why = uv.fs_rename(from, to)
  if not moved then return nil, tostring(why) end
  return true
end

--- Which of the two names the module is actually under, or nil if it is under neither.
function M.state_on_disk(id, client)
  if not client or client == "" then return nil end
  local live, off = folders(client, id)
  if uv.fs_stat(live) then return true end
  if uv.fs_stat(off) then return false end
  return nil
end

--- Remove an install, and only what the hub put there.
--
-- Files whose hash no longer matches the ledger were edited after the fact, so they are left alone
-- and reported rather than deleted. An edited config is the user's, wherever it sits.
function M.remove(id, client)
  local row = db.row("SELECT id FROM installed WHERE id = ?", id)
  if not row then return nil, "not installed" end
  if not client or client == "" then return nil, "no client folder is set for this profile" end

  local ossl = require("openssl")
  -- A disabled module lives under a dotted name, and uninstalling one has to reach it there.
  local live, off = folders(client, id)
  local dir  = uv.fs_stat(live) and live or off
  local kept = {}

  for _, f in ipairs(db.rows("SELECT path, sha256 FROM deployed WHERE id = ?", id)) do
    local full = dir .. "/" .. f.path
    local fd = io.open(full, "rb")
    if fd then
      local data = fd:read("*a")
      fd:close()
      if f.sha256 and ossl.digest.digest("sha256", data) ~= f.sha256 then
        kept[#kept + 1] = f.path
      else
        uv.fs_unlink(full)
      end
    end
  end

  -- Only ever removed when empty, so anything the ledger did not know about survives along with the
  -- folder holding it.
  local function prune(path)
    local scan = uv.fs_scandir(path)
    if not scan then return end
    local names = {}
    while true do
      local name, kind = uv.fs_scandir_next(scan)
      if not name then break end
      names[#names + 1] = { name = name, kind = kind }
    end
    for _, e in ipairs(names) do
      if e.kind == "directory" then prune(path .. "/" .. e.name) end
    end
    uv.fs_rmdir(path)
  end
  prune(dir)

  db.transaction(function()
    db.run("DELETE FROM deployed WHERE id = ?", id)
    db.run("DELETE FROM installed WHERE id = ?", id)
  end)

  return true, kept
end

return M
