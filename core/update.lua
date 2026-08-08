--[[
  Updating the hub itself.

  Only the Lua tree moves. The executable is never rewritten, nothing downloaded is ever executed,
  and everything is written under %LOCALAPPDATA%, which the user can always write to. That is not an
  optimisation for download size, it is the whole design: replacing a running executable needs write
  access wherever it was put, and an unsigned binary that fetches and launches another binary is the
  exact shape antivirus heuristics exist to catch.

  What the executable does carry, and this cannot, is luvi and the three native libraries. A payload
  that needs a newer one of those says so in REQUIRES and the bootstrap refuses it, which turns the
  one case this scheme cannot serve into a message instead of a crash.

  An update is built in a sibling folder and only named in `USE` once it is complete. The bootstrap
  reads `USE` on the next launch. Nothing is ever written onto the tree currently running.
]]

local uv       = require("uv")
local jobs     = require("core.jobs")
local release  = require("core.release")
local manifest = require("core.manifest")

local M = {}

-- Runs in a threadpool Lua state. No upvalues: the function is dumped and reloaded elsewhere, so
-- everything it needs is defined inside it.
local function worker(args_json, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path

  local json  = require("deps.lua.json")
  local http  = require("ffi.winhttp")
  local miniz = require("miniz")
  local uv    = require("uv")

  local a = json.decode(args_json)

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
    local acc = ""
    for part in dir:gmatch("[^/\\]+") do
      acc = acc == "" and part or (acc .. "/" .. part)
      if not acc:match("^%a:$") then uv.fs_mkdir(acc, tonumber("755", 8)) end
    end
  end

  -- Everything the payload does not carry, taken from the tree the executable unpacked. The two
  -- folders are copied whole rather than by a list of file names, so adding a library to one of
  -- them does not need this function to be taught about it. A whole new folder would, and that is
  -- precisely the change REQUIRES exists to gate.
  local function carry(from, to, rel)
    local st = uv.fs_stat(from .. "/" .. rel)
    if not st then return 0 end
    if st.type ~= "directory" then
      mkdirs((to .. "/" .. rel):match("^(.*)/[^/]*$") or to)
      return uv.fs_copyfile(from .. "/" .. rel, to .. "/" .. rel) and 1 or 0
    end
    local n, scan = 0, uv.fs_scandir(from .. "/" .. rel)
    mkdirs(to .. "/" .. rel)
    while scan do
      local name = uv.fs_scandir_next(scan)
      if not name then break end
      n = n + carry(from, to, rel .. "/" .. name)
    end
    return n
  end

  local ok, out = pcall(function()
    local staging = a.updates .. "/" .. a.version .. ".new"
    local final   = a.updates .. "/" .. a.version
    local blob    = a.temp .. "/wxl-hub-payload.bin"

    mkdirs(a.updates)
    rmtree(staging)
    mkdirs(staging)

    note("downloading", 0, 0)
    local got = http.download(a.url, blob, {
      headers  = { "User-Agent: wxl-hub" },
      on_chunk = function(done, total) note("downloading", done, total) end,
    })
    if got.status ~= 200 then error(("the download answered %d"):format(got.status)) end

    note("unpacking", 0, 0)
    local probe = io.open(blob, "rb")
    local magic = probe and probe:read(4) or nil
    if probe then probe:close() end
    if magic ~= "PK\3\4" then error("the download is not an archive") end

    local zip = miniz.new_reader(blob)
    if not zip then error("the archive cannot be read") end

    -- Same normalisation the extension installer does, for the same reason: a zip built on Windows
    -- writes backslashes, and one produced from a source tree wraps everything in a single folder.
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

    local written = 0
    for i, name in pairs(names) do
      local rel = strip and name:sub(#strip + 2) or name
      -- A zip is attacker-controlled input the moment the release it came from is. Nothing here
      -- climbs out of the staging folder, whatever the archive claims its entries are called.
      if rel ~= "" and not rel:match("%.%.") and not rel:match("^[/\\]") and not rel:match("^%a:") then
        local dest = staging .. "/" .. rel
        mkdirs(dest:match("^(.*)/[^/]*$") or staging)
        local w = io.open(dest, "wb")
        if not w then error("cannot write " .. rel) end
        w:write(zip:extract(i))
        w:close()
        written = written + 1
      end
    end

    note("assembling", 0, 0)
    local carried = carry(a.shipped, staging, "VERSION")
                  + carry(a.shipped, staging, "deps/webview")
                  + carry(a.shipped, staging, "deps/sqlite")

    -- Checked before anything points at it. A tree missing its entry point or its libraries would
    -- be chosen by the bootstrap, fail, and cost a launch to roll back; refusing here costs nothing.
    for _, needed in ipairs { "main.lua", "core/app.lua", "PAYLOAD",
                              "deps/webview/webview.dll", "deps/sqlite/sqlite3.dll" } do
      if not uv.fs_stat(staging .. "/" .. needed) then
        error("the update is incomplete, " .. needed .. " is missing")
      end
    end

    rmtree(final)
    local renamed, why = uv.fs_rename(staging, final)
    if not renamed then error("cannot put the update in place: " .. tostring(why)) end

    -- Last, so a folder interrupted at any earlier point is never mistaken for a finished one.
    local fd = io.open(final .. "/.ok", "wb")
    if not fd then error("cannot mark the update complete") end
    fd:write(a.version)
    fd:close()

    os.remove(blob)
    return { version = a.version, files = written, carried = carried }
  end)

  if not ok then return json.encode { error = tostring(out) } end
  return json.encode(out)
end

local function slurp(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local s = (fd:read("*l") or ""):gsub("%s+$", "")
  fd:close()
  return s ~= "" and s or nil
end

--- The update named by USE, when it is not the one already running. nil the rest of the time, which
--- includes the ordinary case of an update that has been applied and is now simply the app.
function M.staged()
  if not release.installed then return nil end
  local name = slurp(release.updates .. "/USE")
  if not name or name == release.payload then return nil end
  if not uv.fs_stat(release.updates .. "/" .. name .. "/.ok") then return nil end
  return name
end

--- What the catalogue fetch found, when it is newer than what is running.
--
-- A tree with no payload version, which is what a checkout is, compares equal to everything and is
-- therefore never offered anything. That is the intended answer: there is nothing here to replace.
function M.available()
  if not release.installed then return nil end
  local boot = require("core.boot")
  local h = boot.hub
  if not h or not h.url or not h.version then return nil end
  if manifest.compare(h.version, release.payload) <= 0 then return nil end
  if M.staged() == h.version then return nil end
  return h
end

--- Fetch and assemble an update. It becomes live at the next launch and not before.
function M.start()
  local h = M.available()
  if not h then return nil, "there is nothing newer to install" end
  if not release.shipped then return nil, "this build cannot update itself" end
  if jobs.busy("hub") then return nil, "an update is already being installed" end

  local temp = (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("[/\\]+$", "")

  return jobs.start {
    kind  = "update",
    label = "WarcraftXL Hub " .. h.version,
    ref   = "hub",
    work  = worker,
    args  = {
      url     = h.url,
      version = h.version,
      updates = release.updates,
      shipped = release.shipped,
      temp    = temp,
    },
    -- Written here and not in the worker. Assembling a folder and choosing to run it are two
    -- decisions, and only the second one is irreversible from the user's side.
    on_done = function(job)
      local fd = io.open(release.updates .. "/USE", "wb")
      if not fd then error("the update is ready but cannot be selected") end
      fd:write(job.result.version)
      fd:close()
    end,
    on_settle = function(job)
      local notify = require("core.notify")
      if job.state == "done" then
        notify.raise {
          kind = "update", ref = "hub", level = "good",
          title = "Hub " .. h.version .. " is ready",
          body  = "It replaces the current version the next time you start the hub.",
          href  = "/settings/about",
        }
      else
        notify.raise {
          kind = "update", ref = "hub", level = "bad",
          title = "The hub update failed",
          body  = tostring(job.error),
          href  = "/settings/about",
        }
      end
    end,
  }
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

--- Forget a staged update. The folder goes with it, since keeping one nobody selected is keeping a
--- copy of the application for no reason.
function M.discard()
  local name = M.staged()
  if not name then return nil, "nothing is staged" end
  os.remove(release.updates .. "/USE")
  pcall(rmtree, release.updates .. "/" .. name)
  return true
end

local announced = false

--- Say what this launch turned out to be, once, on the first page of the session.
--
-- Two states are worth a word, and they are not the two you would guess. An update that has been
-- downloaded is not one of them: the next launch applies it before anything here runs, so "waiting
-- to be applied" is a state the user practically never opens the window in. What they do open the
-- window in is the launch **after**, which is why arriving on a new version is announced at all. The
-- settings page covers the in-between for the session that downloaded it, and so does the bell.
--
-- A toast and a notice answer different questions. The toast is for whoever is sitting in front of
-- the window and is gone in five seconds; the notice is what the bell still holds for whoever was
-- making coffee. `raise_once` is what stops the second from being marked unread again at every
-- launch until the user gives in.
function M.announce()
  if announced then return end
  announced = true
  if not release.installed then return end

  local page   = require("core.page")
  local notify = require("core.notify")
  local seen   = release.updates .. "/ANNOUNCED"

  -- A first launch has nothing to compare against and is not an upgrade. Recording without saying
  -- anything is what keeps a fresh install from congratulating itself on existing.
  local last = slurp(seen)
  if last ~= release.payload then
    -- On a hub that has never been offered an update there is no updates folder yet, and the marker
    -- would have nowhere to go. Both calls are no-ops once the folder exists.
    uv.fs_mkdir(release.hub, tonumber("755", 8))
    uv.fs_mkdir(release.updates, tonumber("755", 8))
    local fd = io.open(seen, "wb")
    if fd then fd:write(release.payload); fd:close() end
    if last then
      page.queue("good", "Updated to " .. release.payload, "The hub is running the new version.")
      notify.raise {
        kind = "update", ref = "hub", level = "good", href = "/settings/about",
        title = "Hub " .. release.payload .. " is installed",
        body  = "Updated from " .. last .. ".",
      }
      return
    end
  end

  local offer = M.available()
  if not offer then return end

  page.queue("info", "Hub " .. offer.version .. " is available",
             "Install it from Settings, under About.")
  notify.raise_once {
    kind = "update", ref = "hub", level = "info", href = "/settings/about",
    title = "Hub " .. offer.version .. " is available",
    body  = "Only the application is downloaded, and the executable is left where it is.",
  }
end

-- Confirmation, and the tidying that only makes sense once something has been confirmed.
local confirmed = false

--- Declare the running tree healthy. Called once the server has answered a request, which proves
--- the bootstrap chose a tree that loads every module, opens the database and binds the socket.
--- Until it happens the bootstrap treats the tree as unproven and rolls back on the next launch.
---
--- It does not prove every page renders. A payload that boots and then breaks one route is a bug to
--- fix forward, not a reason to throw the whole update away.
function M.confirm()
  if confirmed then return end
  confirmed = true
  if not release.installed then return end
  os.remove(release.updates .. "/trying")

  -- Old trees, now that there is a proven one. Each is a full copy of the application, so leaving
  -- them costs about eight megabytes apiece for nothing. A folder still in use fails to delete
  -- because its libraries are open, which is the safety net rather than a case to detect.
  local live = release.live()
  local function sweep(dir, keep)
    local scan = uv.fs_scandir(dir)
    while scan do
      local name, kind = uv.fs_scandir_next(scan)
      if not name then break end
      local path = dir .. "/" .. name
      if kind == "directory" and name ~= keep and name ~= "updates" and path ~= live then
        pcall(rmtree, path)
      end
    end
  end

  sweep(release.hub, release.build)
  sweep(release.updates, release.payload)
end

return M
