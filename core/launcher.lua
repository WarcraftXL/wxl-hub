--[[
  The launcher.

  The published executable is this, not the hub. It runs first, which is the whole point: the binary
  it is about to replace is the one binary that is guaranteed not to be running. Writing over a live
  executable is impossible on Windows, writing over an idle one is a file copy.

  It owns exactly three things: a small window, a check against the newest release, and a download.
  Everything else the user thinks of as the hub is a second process it starts and forgets.

  Same two-thread shape as the application, for the same reason: `webview_run` never returns until
  the window closes, so the work happens on a loop thread and the window asks it for progress over
  HTTP. The launch itself has to happen on the UI thread, because that is the thread that can stop
  the message loop afterwards.
]]

local uv      = require("uv")
local release = require("core.release")

local M = {}

local REPO  = "WarcraftXL/wxl-hub"
local ASSET = "^wxl%-hub%.exe$"

-- What the window is told. Written by the loop thread, read by the request handler on the same
-- thread, so there is nothing to synchronise.
M.state = {
  phase = "Starting up",
  done  = 0,
  total = 0,
  ready = false,     -- the hub on disk is the one to run
  failed = nil,
  version = nil,
}

local function slurp(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local s = (fd:read("*l") or ""):gsub("%s+$", "")
  fd:close()
  return s ~= "" and s or nil
end

--- What is installed right now, or nil when nothing is.
function M.installed()
  if not uv.fs_stat(release.hub_exe) then return nil end
  return slurp(release.hub_ver) or "unknown"
end

-- Runs in a threadpool state: no upvalues, primitives in and out.
local function work(repo, asset_pattern, bin, exe, verfile, have, progress_path)
  package.path = "./?.lua;./?/init.lua;" .. package.path
  local json = require("deps.lua.json")
  local http = require("ffi.winhttp")
  local uv   = require("uv")

  local last = 0
  local function say(phase, done, total)
    local ms = tonumber(uv.hrtime() / 1e6)
    if done and done > 0 and ms - last < 100 then return end
    last = ms
    local fd = io.open(progress_path, "wb")
    if fd then
      fd:write(("%s\n%d\n%d\n"):format(phase, math.floor(done or 0), math.floor(total or 0)))
      fd:close()
    end
  end

  local function mkdirs(dir)
    local acc = ""
    for part in dir:gmatch("[^/\\]+") do
      acc = acc == "" and part or (acc .. "/" .. part)
      if not acc:match("^%a:$") then uv.fs_mkdir(acc, tonumber("755", 8)) end
    end
  end

  local ok, out = pcall(function()
    say("Checking for updates", 0, 0)
    local r = http.get("https://api.github.com/repos/" .. repo .. "/releases?per_page=10",
      { headers = { "User-Agent: wxl-hub", "Accept: application/vnd.github+json" } })
    if r.status ~= 200 then error(("GitHub answered %d"):format(r.status)) end

    -- The newest published release, and the program inside it. Named exactly if it is there, and
    -- otherwise the one executable it carries: this file cannot be corrected remotely, so it should
    -- not be the thing that breaks the day an asset is renamed.
    local newest, url, size
    for _, rel in ipairs(json.decode(r.body)) do
      if not rel.draft and not rel.prerelease then
        newest = (tostring(rel.tag_name or ""):gsub("^v", ""))
        local exes = {}
        for _, a in ipairs(rel.assets or {}) do
          if type(a.name) == "string" and a.name:lower():match("%.exe$") then
            exes[#exes + 1] = a
            if a.name:match(asset_pattern) then url, size = a.browser_download_url, a.size or 0 end
          end
        end
        if not url and #exes == 1 then url, size = exes[1].browser_download_url, exes[1].size or 0 end
        break
      end
    end
    if not newest then error("no release has been published yet") end
    if not url then error(("release %s carries no application"):format(newest)) end

    -- Different, not newer. Comparing strings is a rule that cannot rot; comparing versions means
    -- this file has an opinion about how versions are shaped, and it is the one file nobody can
    -- correct afterwards. Equality also makes withdrawing a bad release work on its own: publish the
    -- previous one again and every launcher converges back onto it.
    --
    -- The escape hatch is a file, because a developer testing a local build is the only case that
    -- wants a launcher to sit still, and a file is something they can see and delete.
    if have == newest then return { version = newest, action = "kept" } end
    if uv.fs_stat(bin .. "/hub.pin") then
      return { version = have ~= "" and have or "pinned", action = "pinned" }
    end

    say(("Downloading WarcraftXL Hub %s"):format(newest), 0, size)
    mkdirs(bin)
    local tmp = exe .. ".new"
    uv.fs_unlink(tmp)
    local got = http.download(url, tmp, {
      headers  = { "User-Agent: wxl-hub" },
      on_chunk = function(done, total)
        say(("Downloading WarcraftXL Hub %s"):format(newest), done, total > 0 and total or size)
      end,
    })
    if got.status ~= 200 then error(("the download answered %d"):format(got.status)) end

    -- A PE or nothing. A proxy or a captive portal answering 200 with an HTML error page is the
    -- realistic way this goes wrong, and installing that would leave an unstartable hub behind.
    local probe = io.open(tmp, "rb")
    local magic = probe and probe:read(2) or nil
    if probe then probe:close() end
    if magic ~= "MZ" then
      uv.fs_unlink(tmp)
      error("what came back is not a Windows program")
    end

    say("Installing", 0, 0)
    -- Renamed over the top rather than downloaded onto it, so a transfer that dies half way leaves
    -- the previous hub intact and startable.
    uv.fs_unlink(exe)
    local moved, why = uv.fs_rename(tmp, exe)
    if not moved then error("cannot replace the hub: " .. tostring(why)) end

    local fd = io.open(verfile, "wb")
    if not fd then error("cannot record the installed version") end
    fd:write(newest)
    fd:close()

    return { version = newest, action = "installed" }
  end)

  if not ok then return json.encode { error = tostring(out) } end
  return json.encode(out)
end

--- Read what the worker last wrote. Same torn-read tolerance as the boot fetch: the file is rewritten
--- whole with nothing locking it.
local function read_progress(path)
  local fd = io.open(path, "rb")
  if not fd then return end
  local text = fd:read("*a")
  fd:close()
  if not text or text == "" then return end
  local phase, done, total = text:match("^([^\n]*)\n(%d+)\n(%d+)")
  if not phase then return end
  M.state.phase, M.state.done, M.state.total = phase, tonumber(done), tonumber(total)
end

--- Everything the worker needs, in one place, so the path with a window and the path without one
--- cannot end up disagreeing about what they are installing.
local function work_args()
  local progress = ((os.getenv("TEMP") or "."):gsub("[/\\]+$", "")) .. "/wxl-launcher.progress"
  -- `have` is empty rather than nil on a machine with nothing installed. A nil in the middle of an
  -- argument list truncates it, and the worker would be handed no progress path at all.
  return REPO, ASSET, release.bin, release.hub_exe, release.hub_ver, M.installed() or "", progress
end

--- Start the check. Returns immediately; `M.state.ready` flips when there is something to launch.
function M.start()
  local repo, asset, bin, exe, verfile, have, progress = work_args()
  os.remove(progress)

  local timer = uv.new_timer()
  timer:start(120, 120, function() read_progress(progress) end)

  local job
  job = uv.new_work(work, function(payload)
    timer:stop()
    os.remove(progress)

    local ok, out = pcall(require("deps.lua.json").decode, payload or "")
    if not ok or type(out) ~= "table" then out = { error = "the check returned nothing readable" } end

    if out.error then
      -- An update that cannot be fetched is not a reason to refuse to start. A hub already on disk
      -- is a working hub, and the network is the part that failed.
      if have ~= "" then
        M.state.phase, M.state.version, M.state.ready = "Starting offline", have, true
        print("update check failed, starting what is installed: " .. tostring(out.error))
      else
        M.state.failed = tostring(out.error)
        M.state.phase  = "Cannot start"
        print("FAILED " .. tostring(out.error))
      end
      return
    end

    M.state.version, M.state.phase, M.state.ready = out.version, "Starting", true
    print(("hub %s %s"):format(out.version, out.action))
  end)

  -- `have` is empty rather than nil on a machine with nothing installed. A nil in the middle of an
  -- argument list truncates it, and the worker would be handed no progress path at all.
  uv.queue_work(job, repo, asset, bin, exe, verfile, have, progress)
end

--- Hand over. Returns the spawned process, or nil plus a reason.
--
-- Detached and with its streams let go, so the launcher can exit without the hub going with it or
-- blocking on a pipe nobody reads.
function M.launch()
  if not uv.fs_stat(release.hub_exe) then return nil, "there is no hub to start" end
  local handle, err = uv.spawn(release.hub_exe, { detached = true, stdio = { nil, nil, nil } })
  if not handle then return nil, tostring(err) end
  uv.unref(handle)
  return handle
end

-- Its own, rather than core.page's. The launcher has no database, no modules and no navigation, and
-- reaching for that file would drag most of the application into a process whose whole job is to
-- start another one.
local CSP = "default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
         .. "script-src 'self' 'unsafe-inline'; connect-src 'self'"

local function megabytes(n)
  if not n or n <= 0 then return nil end
  return ("%.1f MB"):format(n / 1048576)
end

--- Runs on the loop thread. One page, one status fragment, and the work behind them.
function M.serve(port, token)
  local server = require("core.base.server")
  local view   = require("core.base.view")
  local style  = require("core.ui.style")

  local app = server.new { token = token }
  app:static("/vendor/", "deps/htmx")
  app:static("/static/", "assets")

  local function ctx()
    local s = M.state
    return {
      state = s,
      known = s.total and s.total > 0,
      pct   = (s.total and s.total > 0) and math.floor(s.done / s.total * 100) or 100,
      size  = (s.total and s.total > 0)
              and ("%s of %s"):format(megabytes(s.done) or "0.0 MB", megabytes(s.total)) or nil,
    }
  end

  app.router:get("/", function(req, res)
    local c = ctx()
    c.stylesheet, c.csp = style.href, CSP
    res:html(view.render("launcher", c))
  end)

  app.router:get("/status", function(req, res)
    res:html(view.render("launchstep", ctx()))
  end)

  app.router:get("/theme.css", function(req, res)
    res:header("Cache-Control", style.cache_control)
    res:send(200, style.mime, style.css)
  end)

  app:listen(port)
  print(("launcher listening on 127.0.0.1:%d"):format(port))
  M.start()
  return app
end

--- Start the hub, with a window if one can be had and without one if not.
--
-- The window is decoration; the handover is the contract. Everything that draws sits behind one
-- pcall, so a machine whose WebView2 runtime is missing or broken still gets its application
-- installed and started, headlessly, out of the same worker function.
function M.run()
  if pcall(M.with_window) then return end

  print("no window, installing and handing over without one")
  local ok, out = pcall(require("deps.lua.json").decode, work(work_args()))
  if ok and type(out) == "table" and out.error then
    print("update check failed: " .. tostring(out.error))
  end

  local started, why = M.launch()
  if not started then print("cannot start the hub: " .. tostring(why)) end
end

--- The window, and the handover.
function M.with_window()
  local webview = require("ffi.webview")
  local ffi     = require("ffi")

  local probe = uv.new_tcp()
  probe:bind("127.0.0.1", 0)
  local port = probe:getsockname().port
  probe:close()

  local token = tostring(os.time()) .. tostring(math.floor(os.clock() * 1e6))

  -- The window is made before the server thread starts. A runtime that cannot produce one throws
  -- here, and throwing here means no download has been set going that nobody will see the end of.
  webview.setup("deps/webview")
  local win = webview.open {
    title = "WarcraftXL Hub", width = 460, height = 200, hint = 3, debug = true,
    hidden = true, background = { 0x10, 0x12, 0x16 },
  }
  win:icon("assets/logo.ico")

  uv.new_thread(function(port, token, cwd)
    local uv2 = require("uv")
    uv2.chdir(cwd)
    package.path = "./?.lua;./?/init.lua;" .. package.path
    -- Required here, not closed over. A thread gets a fresh Lua state and every upvalue arrives nil.
    require("core.base.log").install(require("core.release").log(), "launch")
    local ok, err = xpcall(function()
      require("core.launcher").serve(port, token)
    end, debug.traceback)
    if not ok then print("LAUNCHER FAILED\n" .. tostring(err)) end
    uv2.run()
  end, port, token, uv.cwd())

  local visible = false
  win:bind("wxlReady", function()
    win:show()
    if not visible then visible = true; print("launcher window shown") end
    return "null"
  end)

  -- The handover, and the only thing that happens on this thread. It has to: stopping the message
  -- loop is something only the thread pumping it can do, and the loop thread that decided the hub
  -- was ready has no way to reach the window.
  win:bind("wxlStart", function()
    local ok, why = M.launch()
    if not ok then
      print("cannot start the hub: " .. tostring(why))
      return "false"
    end
    print("hub started, launcher stepping aside")
    win:terminate()
    return "true"
  end)

  -- Same script as the application's window, and for the same reason: see core/app.lua. The class is
  -- what any entrance animation waits on, so that it runs against a window that is on screen rather
  -- than against one still hidden.
  win:init([[
addEventListener('DOMContentLoaded', function () {
  var lit = function () { document.documentElement.classList.add('wxl-shown') };
  window.wxlReady ? wxlReady().then(lit, lit) : lit();
});
]])
  -- Hidden again, and not out of superstition. `webview_get_native_handle` can still answer nothing
  -- straight after create, and a hide that found no handle did nothing at all: that is the window
  -- that turned up showing its background colour and no page. Here the handle certainly exists, and
  -- the message loop has not started, so nothing has been able to paint yet either way.
  win:hide()

  -- And only now is there something at the other end to navigate to.
  if not require("core.base.server").wait(port) then
    print("the server did not come up in time, showing whatever the browser makes of that")
  end

  win:navigate(("http://127.0.0.1:%d/?token=%s"):format(port, token))

  local ran, why = xpcall(function() return win:run() end, debug.traceback)
  if not ran then print("MESSAGE LOOP FAILED\n" .. tostring(why)) end
  win:destroy()

  -- Same reasoning as the application: a blocking download on a threadpool thread cannot be
  -- interrupted, and unwinding Lua around a live foreign state panics.
  ffi.cdef [[ void ExitProcess(unsigned int code); ]]
  ffi.C.ExitProcess(0)
end

return M
