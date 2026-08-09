--[[
  Putting the framework into a client.

  Two things have to be true before anything the store installs will load: the client's own
  executable has to carry the WarcraftXL import, and the library it names has to be beside it. Both
  come out of one wxl-core release, and this is what fetches them and applies them.

  It is deliberately the same shape as installing a module: a job, so it reports through the same
  progress element, and a worker that does the blocking work off the loop. What it does not share is
  the destination. A module lands in `Extensions/<id>/` and can be removed by deleting a folder;
  this writes next to Wow.exe and edits Wow.exe itself, which is why the patcher keeps `Wow.exe.orig`
  and why nothing here is undone by uninstalling anything.

  The patcher is the authority on whether it has already run. Nothing here decides that: it is run
  every time and skips a client it has already done.
]]

local jobs = require("core.jobs")

local M = {}

local CORE_REPO = "WarcraftXL/wxl-core"

-- What the release archive is expected to carry, and where each piece goes. The proxy is left out
-- on purpose: d3d9.dll only works alongside the real library renamed beside it, so shipping it as
-- part of "make this client ready" would be handing someone a client that no longer starts.
local WANTED = { ["warcraftxl.dll"] = true, ["wxl-patcher.exe"] = true }

-- Runs in a threadpool state. No upvalues: it is dumped and reloaded elsewhere.
local function worker(args_json, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path

  local json  = require("deps.lua.json")
  local http  = require("ffi.winhttp")
  local miniz = require("miniz")
  local uv    = require("uv")
  local run   = require("utils.run")

  local a = json.decode(args_json)

  local last, last_phase = 0, nil
  local function note(phase, done, total)
    local ms = tonumber(uv.hrtime() / 1e6)
    if phase == last_phase and ms - last < 100 then return end
    last, last_phase = ms, phase
    local fd = io.open(progress_path, "wb")
    if fd then
      fd:write(("%s\n%d\n%d\n"):format(phase, math.floor(done or 0), math.floor(total or 0)))
      fd:close()
    end
  end

  local ok, out = pcall(function()
    note("Looking for the framework", 0, 0)
    local r = http.get("https://api.github.com/repos/" .. a.repo .. "/releases?per_page=10",
      { headers = { "User-Agent: wxl-hub", "Accept: application/vnd.github+json" } })
    if r.status ~= 200 then error(("GitHub answered %d"):format(r.status)) end

    local tag, url
    for _, rel in ipairs(json.decode(r.body)) do
      if not rel.draft and not rel.prerelease then
        tag = tostring(rel.tag_name or "")
        for _, asset in ipairs(rel.assets or {}) do
          if type(asset.name) == "string" and asset.name:lower():match("%.zip$") then
            url = asset.browser_download_url
          end
        end
        break
      end
    end
    if not tag then error("wxl-core has published no release yet") end
    if not url then
      error(("release %s carries no archive to install from"):format(tag))
    end

    note("Downloading " .. tag, 0, 0)
    local blob = a.temp .. "/wxl-core.zip"
    local got = http.download(url, blob, {
      headers  = { "User-Agent: wxl-hub" },
      on_chunk = function(done, total) note("Downloading " .. tag, done, total) end,
    })
    if got.status ~= 200 then error(("the download answered %d"):format(got.status)) end

    note("Unpacking", 0, 0)
    local zip = miniz.new_reader(blob)
    if not zip then error("what came back is not a readable archive") end

    -- Matched on the file name alone, so however the archive is laid out inside, the two files it
    -- has to contain are found.
    local written = {}
    for i = 1, zip:get_num_files() do
      if not zip:is_directory(i) then
        local name = zip:get_filename(i):gsub("\\", "/")
        local base = name:match("[^/]+$"):lower()
        if a.wanted[base] and not written[base] then
          local fd = io.open(a.client .. "/" .. name:match("[^/]+$"), "wb")
          if not fd then error("cannot write into the client folder") end
          fd:write(zip:extract(i))
          fd:close()
          written[base] = true
        end
      end
    end
    os.remove(blob)

    for base in pairs(a.wanted) do
      if not written[base] then error(("%s is not in the %s archive"):format(base, tag)) end
    end

    -- The patcher is idempotent and keeps its own backup, so it is simply run: asking first would
    -- mean holding a second opinion about a question it already answers.
    note("Patching Wow.exe", 0, 0)
    local code, why = run.wait(a.client .. "/wxl-patcher.exe", a.client .. "/Wow.exe", a.client)
    if not code then error(why) end
    if code ~= 0 then error(("the patcher gave up (exit %d)"):format(code)) end

    return { version = tag, patched = true }
  end)

  if not ok then return json.encode { error = tostring(out) } end
  return json.encode(out)
end

--- Fetch wxl-core and make `path` ready to load it. Returns the job, or nil plus a reason.
function M.start(path)
  if not path or path == "" then return nil, "no client is set for this profile" end
  if jobs.busy("client") then return nil, "the client is already being set up" end

  return jobs.start {
    kind  = "patch",
    label = "Setting up the client",
    ref   = "client",
    work  = worker,
    args  = {
      repo   = CORE_REPO,
      client = (path:gsub("[/\\]+$", "")),
      wanted = WANTED,
      temp   = ((os.getenv("TEMP") or "."):gsub("[/\\]+$", "")),
    },
    on_settle = function(job)
      local notify = require("core.notify")
      if job.state == "done" then
        notify.raise {
          kind = "client", ref = "client", level = "good",
          title = "Client ready",
          body  = "WarcraftXL " .. tostring(job.result.version) .. " is installed and Wow.exe is patched.",
        }
      else
        notify.raise {
          kind = "client", ref = "client", level = "bad",
          title = "The client could not be set up",
          body  = tostring(job.error),
        }
      end
    end,
  }
end

return M
