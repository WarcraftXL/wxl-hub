--[[
  Putting the framework into a client.

  Two things have to be true before anything the store installs will load: the client's executable has
  to carry the WarcraftXL import, and the library it names has to be beside it. Both come out of one
  wxl-core release, and this is what fetches them and applies them.

  It is deliberately the same shape as installing a module: a job, so it reports through the same
  progress element, and a worker that does the blocking work off the loop. What it does not share is
  the destination. A module lands in `Extensions/<id>/` and can be removed by deleting a folder; this
  writes next to Wow.exe and edits Wow.exe itself, which is why the patcher keeps `Wow.exe.orig` and
  why nothing here is undone by uninstalling anything.

  The patcher is the authority on whether it has already run. Nothing here decides that: it is run
  every time and skips a client it has already done.

  In the workspace rather than in the first-run form, which is where it started. Two screens need it
  now, and the one that only borrows it is the form. It is offered as `client.deploy` so neither has
  to know where the other keeps its files.
]]

local jobs     = require("core.jobs")
local mediator = require("core.base.mediator")

local M = {}

local CORE_REPO = "WarcraftXL/wxl-core"

-- What the two assets are called once they are in the client, whatever the release called them.
--
-- The library's name is not cosmetic: core/game/client.lua decides whether the framework is present
-- by looking for exactly this, so the name lives in one place and everything else follows it. The
-- patcher's is ours to choose, and a fixed one is what makes the run step below deterministic.
local AS_LIBRARY = "WarcraftXL.dll"
local AS_PATCHER = "wxl-patcher.exe"

-- Runs in a threadpool state. No upvalues: it is dumped and reloaded elsewhere.
local function worker(args_json, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path

  local json = require("deps.lua.json")
  local http = require("ffi.winhttp")
  local uv   = require("uv")
  local run  = require("utils.run")

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

    -- A release carries one executable and one library. Found by name first, so the build renaming an
    -- artefact is the only thing that has to change and it changes in one place; falling back to the
    -- single candidate of that extension, so a rename does not need a release of the hub to follow it.
    --
    -- What it will not do is choose between two. A release that grows a second library is a question
    -- this cannot answer, and picking one would put a file next to Wow.exe that nothing downstream
    -- would ever report as the wrong one.
    local function pick(assets, ext, prefer)
      local exact, all = nil, {}
      for _, asset in ipairs(assets) do
        local name = tostring(asset.name or "")
        if name:lower():match("%." .. ext .. "$") then
          all[#all + 1] = asset
          if name:lower() == prefer then exact = asset end
        end
      end
      if exact then return exact.browser_download_url end
      if #all == 1 then return all[1].browser_download_url end
      return nil
    end

    local tag, exe, dll, seen
    for _, rel in ipairs(json.decode(r.body)) do
      if not rel.draft and not rel.prerelease then
        tag, seen = tostring(rel.tag_name or ""), {}
        for _, asset in ipairs(rel.assets or {}) do seen[#seen + 1] = tostring(asset.name or "") end
        dll = pick(rel.assets or {}, "dll", a.library:lower())
        exe = pick(rel.assets or {}, "exe", a.patcher:lower())
        break
      end
    end

    if not tag then error("wxl-core has published no release yet") end
    if not (exe and dll) then
      error(("release %s does not say which of its files to install: %s"):format(tag,
            #seen == 0 and "it carries none" or table.concat(seen, ", ")))
    end

    -- Downloaded beside the client and then copied in, rather than straight into it. A transfer that
    -- fails half way would otherwise leave a truncated library next to Wow.exe, which is a client
    -- that starts and then dies rather than one that visibly did not get set up.
    local function fetch(url, label, into)
      note("Downloading " .. label, 0, 0)
      local tmp = a.temp .. "/" .. into
      local got = http.download(url, tmp, {
        headers  = { "User-Agent: wxl-hub" },
        on_chunk = function(done, total) note("Downloading " .. label, done, total) end,
      })
      if got.status ~= 200 then error(("%s answered %d"):format(label, got.status)) end

      local done, why = uv.fs_copyfile(tmp, a.client .. "/" .. into)
      os.remove(tmp)
      if not done then error(("cannot write %s into the client folder: %s"):format(into, tostring(why))) end
    end

    fetch(dll, a.library .. " " .. tag, a.library)
    fetch(exe, "the patcher", a.patcher)

    -- The patcher is idempotent and keeps its own backup, so it is simply run: asking first would
    -- mean holding a second opinion about a question it already answers.
    note("Patching Wow.exe", 0, 0)
    local code, why = run.wait(a.client .. "/" .. a.patcher, a.client .. "/Wow.exe", a.client)
    if not code then error(why) end
    if code ~= 0 then error(("the patcher gave up (exit %d)"):format(code)) end

    return { version = tag, patched = true }
  end)

  if not ok then return json.encode { error = tostring(out) } end
  return json.encode(out)
end

--- Fetch wxl-core and make `path` ready to load it. Returns the job, or nil plus a reason.
--
-- `after` is { url, target }: what the calling page wants re-asked for once this lands. Two screens
-- start this job and each describes the client in its own markup, so neither the job nor this file
-- can know what has gone stale.
function M.start(path, after)
  if not path or path == "" then return nil, "no client is set" end
  if jobs.busy("client") then return nil, "the client is already being set up" end

  return jobs.start {
    kind  = "patch",
    label = "Setting up the client",
    ref   = "client",
    after = after,
    work  = worker,
    args  = {
      repo    = CORE_REPO,
      client  = (path:gsub("[/\\]+$", "")),
      library = AS_LIBRARY,
      patcher = AS_PATCHER,
      temp    = ((os.getenv("TEMP") or "."):gsub("[/\\]+$", "")),
    },
    on_settle = function(job)
      local notify = require("core.notify")
      if job.state == "done" then
        notify.raise {
          kind = "client", ref = "client", level = "good",
          title = "Client ready",
          body  = "WarcraftXL " .. tostring(job.result.version)
               .. " is installed and Wow.exe is patched.",
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

--- Offered by name so the first-run form can start the same job without knowing where this lives.
--- One table rather than two returns: the mediator carries a single value.
function M.install()
  mediator.provide("client.deploy", function(path, after)
    local job, why = M.start(path, after)
    return { job = job, error = why }
  end)
end

return M
