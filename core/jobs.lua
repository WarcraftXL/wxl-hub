--[[
  Background jobs, and how their progress gets back to the page.

  The work blocks: a download, a zip, a few hundred file writes. It therefore runs on libuv's
  threadpool, in a Lua state that shares nothing with this one, and the only thing that crosses the
  boundary is the JSON the worker returns when it is finished.

  Progress cannot wait for that. The worker writes a three-line progress file and this side reads it
  when the page polls. Deliberately cheap: no shared memory, no second database connection, nothing
  to get subtly wrong about threads. The cost is that a torn read shows one stale frame of a
  progress bar.
]]

local uv   = require("uv")
local json = require("deps.lua.json")

local M = {}

local jobs, order, seq = {}, {}, 0

--- Where progress files go. Not the database: this is per-run scratch that nothing should outlive.
local function scratch()
  return (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("[/\\]+$", "")
end

local function now()
  uv.update_time()
  return uv.now()
end

--- Read what the worker last wrote.
--
-- Returns false when there was nothing readable, which matters more than it looks: a read caught
-- mid-write leaves the previous numbers standing, and recording those as a fresh sample invents a
-- moment where no bytes arrived. Sampled at four hertz that reads as a speed collapsing to zero
-- every other frame.
local function read_progress(job)
  local fd = io.open(job.file, "rb")
  if not fd then return false end
  local text = fd:read("*a")
  fd:close()

  local phase, done, total = text:match("^([^\n]*)\n(%d+)\n(%d+)")
  if not phase then return false end
  job.phase = phase
  job.done  = tonumber(done)
  job.total = tonumber(total)
  return true
end

-- Sampling runs on a timer of its own rather than on the back of whoever polls, so the speed graph
-- describes the download and not the page that happens to be open. A user who walks away and comes
-- back sees the curve they actually had.
local sampler

local SAMPLE_MS   = 250
local SAMPLE_KEEP = 160          -- 40 seconds of history, which is what a rate is averaged over

-- How many finished jobs stay in memory. The list is what the download centre shows and what a
-- just-settled poll reads back, and neither needs more than a screenful; without a bound this table
-- is a leak that only shows up in a session long enough to matter.
local KEEP_JOBS = 50

local function tick()
  local running = false
  for _, id in ipairs(order) do
    local job = jobs[id]
    if job.state == "running" then
      running = true
      -- No reading, no sample. Skipping one widens the next interval, and since a rate is bytes
      -- over the time they took, a wider interval is still the right answer.
      if read_progress(job) then
        local s = job.samples
        s[#s + 1] = { t = now(), done = job.done or 0 }
        if #s > SAMPLE_KEEP then table.remove(s, 1) end
      end
    end
  end
  if not running and sampler then
    sampler:stop()
    sampler:close()
    sampler = nil
  end
end

local function ensure_sampler()
  if sampler then return end
  sampler = uv.new_timer()
  sampler:start(SAMPLE_MS, SAMPLE_MS, tick)
end

--- Forget the oldest finished jobs once there are more than KEEP_JOBS of them.
--
-- Running jobs are never dropped however old they are: something is still writing to them, and a
-- poll that could not find its own job would report it as gone while it was still downloading.
local function prune()
  local excess = #order - KEEP_JOBS
  if excess <= 0 then return end

  local kept, dropped = {}, 0
  for i = 1, #order do
    local id = order[i]
    if dropped < excess and jobs[id].state ~= "running" then
      jobs[id] = nil
      dropped = dropped + 1
    else
      kept[#kept + 1] = id
    end
  end
  order = kept
end

--- Start a job.
--
-- spec.work must be a plain function with no upvalues: it is compiled into a fresh Lua state. It
-- receives (args_json, progress_path) and returns a JSON string.
--
-- spec.on_done runs back on this thread once the worker returns, and is where the database is
-- written. Doing it in the worker would need a second connection to a database this thread has open.
function M.start(spec)
  seq = seq + 1
  local id = tostring(seq)

  local job = {
    id      = id,
    kind    = spec.kind,
    label   = spec.label,
    ref     = spec.ref,
    state   = "running",
    phase   = "starting",
    done    = 0,
    total   = 0,
    started = now(),
    -- uv.now is monotonic milliseconds since the loop started, which is right for measuring a
    -- duration and useless for saying when something happened. Both are kept.
    at      = os.time(),
    samples = {},
    file    = ("%s/wxl-job-%s-%d.progress"):format(scratch(), tostring(spec.ref or "x"), seq),
  }
  jobs[id] = job
  order[#order + 1] = id
  prune()
  ensure_sampler()

  local work
  work = uv.new_work(spec.work, function(payload)
    read_progress(job)
    os.remove(job.file)
    job.finished = now()

    local ok, out = pcall(json.decode, payload or "")
    if not ok or type(out) ~= "table" then
      job.state, job.error = "failed", "the worker returned nothing readable"
    elseif out.error then
      job.state, job.error = "failed", out.error
    else
      job.state, job.result = "done", out
      job.phase = "finished"
    end

    -- Only on success. on_done exists to record a result and a failed job has none, so calling it
    -- anyway crashes on the missing result and replaces the reason the job failed with the crash.
    if job.state == "done" and spec.on_done then
      local fine, why = pcall(spec.on_done, job)
      -- Recording the result is part of the job. A job whose bookkeeping failed did not succeed,
      -- however well the download went.
      if not fine then job.state, job.error = "failed", tostring(why) end
    end

    -- Runs whichever way it went, and after on_done, so it sees the final state including a failure
    -- that only bookkeeping caused. This is where a job announces itself to anyone not watching.
    if spec.on_settle then pcall(spec.on_settle, job) end

    -- The samples describe a transfer in progress. A finished job shows how long it took, not how
    -- fast it was going, so nothing reads them once it has stopped and holding a few hundred per
    -- job for the rest of the session buys nothing.
    job.samples = nil
  end)

  uv.queue_work(work, json.encode(spec.args or {}), job.file)
  return job
end

--- One job, with its progress refreshed. nil when the id is unknown.
function M.get(id)
  local job = jobs[id]
  if not job then return nil end
  if job.state == "running" then read_progress(job) end
  return job
end

--- The most recent jobs, newest first.
function M.recent(n)
  local out = {}
  for i = #order, math.max(1, #order - (n or 20) + 1), -1 do
    out[#out + 1] = jobs[order[i]]
  end
  return out
end

--- Is something already running against this ref? Two installs of the same module at once would
--- race over the same folder, and the second would win by accident.
function M.busy(ref)
  for _, id in ipairs(order) do
    local job = jobs[id]
    if job.ref == ref and job.state == "running" then return job end
  end
end

--- Percentage complete, or nil when the size is unknown. A download with no Content-Length is
--- common on a redirected release asset, and inventing a number for it would be a lie the bar tells.
function M.percent(job)
  if not job or not job.total or job.total <= 0 then return nil end
  return math.min(100, math.floor(job.done / job.total * 100))
end

local function mb(n)
  if n < 1024 then return n .. " B" end
  if n < 1048576 then return ("%.0f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1048576)
end

--- Bytes per second across the sampled window, oldest first. Empty until two samples exist, because
--- a speed needs an interval and one reading is not one.
--
-- The window is taken by starting late. Building the whole series and shifting the front off it
-- costs a full array move per surplus sample.
function M.speed_series(job, keep)
  local s = job and job.samples or {}
  local out = {}
  local from = math.max(2, #s - (keep or 70) + 1)
  for i = from, #s do
    local dt = s[i].t - s[i - 1].t
    local dn = s[i].done - s[i - 1].done
    out[#out + 1] = (dt > 0) and math.max(0, dn / dt * 1000) or 0
  end
  return out
end

--- Current speed, averaged over the last second or so. A single 250 ms interval swings wildly with
--- TCP, and a number that jumps by a factor of three every frame is unreadable.
function M.speed(job)
  local s = M.speed_series(job)
  local n, sum = 0, 0
  for i = math.max(1, #s - 3), #s do sum = sum + s[i]; n = n + 1 end
  return n > 0 and (sum / n) or 0
end

--- Seconds left at the current rate, or nil when either the size or the rate is unknown.
--
-- Deliberately nil rather than a guess: a download with no declared size has no remaining time, and
-- a countdown invented for it is worse than no countdown. A job that has stopped has none either,
-- and computing one from its last interval is how a finished row ends up captioned "0s left".
function M.eta(job)
  if not job or job.state ~= "running" then return nil end
  if not job.total or job.total <= 0 then return nil end
  local rate = M.speed(job)
  if rate < 1024 then return nil end
  return math.max(0, (job.total - job.done) / rate)
end

--- The fastest interval seen so far.
function M.peak(job)
  local top = 0
  for _, v in ipairs(M.speed_series(job, 1e9)) do if v > top then top = v end end
  return top
end

function M.duration(seconds)
  seconds = math.floor(seconds or 0)
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return ("%dm %02ds"):format(seconds / 60, seconds % 60) end
  return ("%dh %02dm"):format(seconds / 3600, (seconds % 3600) / 60)
end

function M.size(bytes)
  bytes = bytes or 0
  if bytes >= 1073741824 then return ("%.2f GB"):format(bytes / 1073741824) end
  if bytes >= 1048576 then return ("%.0f MB"):format(bytes / 1048576) end
  if bytes >= 1024 then return ("%.0f KB"):format(bytes / 1024) end
  return bytes .. " B"
end

function M.rate(bytes_per_second)
  -- The trailing ".0" is dropped so an axis reading "75 MB/s" does not read "75.0 MB/s". Only the
  -- number is trimmed, never the unit.
  local function trim(s) return (s:gsub("%.0$", "")) end
  if bytes_per_second >= 1048576 then
    return trim(("%.1f"):format(bytes_per_second / 1048576)) .. " MB/s"
  end
  if bytes_per_second >= 1024 then return ("%.0f KB/s"):format(bytes_per_second / 1024) end
  return ("%.0f B/s"):format(bytes_per_second)
end

--- Everything still running, oldest first, which is the order a queue is worked through.
function M.running()
  local out = {}
  for _, id in ipairs(order) do
    if jobs[id].state == "running" then out[#out + 1] = jobs[id] end
  end
  return out
end

--- What the progress fragment renders from. Built here so the template never reaches into a live
--- job and never has to decide what an unknown size looks like.
function M.view(job)
  if not job then return nil end
  local eta = M.eta(job)
  return {
    id      = job.id,
    ref     = job.ref,
    kind    = job.kind,
    label   = job.label,
    state   = job.state,
    phase   = job.phase,
    error   = job.error,
    at      = job.at,
    percent = M.percent(job),
    bytes   = (job.total and job.total > 0)
              and ("%s of %s"):format(mb(job.done), mb(job.total)) or nil,
    done_h  = M.size(job.done),
    total_h = (job.total and job.total > 0) and M.size(job.total) or nil,
    eta     = eta and M.duration(eta) or nil,
    took    = job.finished and M.duration((job.finished - job.started) / 1000) or nil,
  }
end

return M
