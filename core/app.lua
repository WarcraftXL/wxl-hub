--[[
  Wiring. The only file that knows about every other one.

  Two threads, because they cannot share: `webview_run` blocks its thread pumping the Win32 message
  loop, and libuv wants a loop of its own. The UI thread holds no application state: it is handed a
  port and a token, points the WebView at that URL, and stops thinking. Everything it asks for
  crosses as HTTP, which is what htmx was doing anyway.
]]

local uv = require("uv")

local M = {}

-- Paths that answer for themselves whatever else is in the way.
--
-- Both gates below hand back a whole page for any request they intercept, which is right for a
-- navigation and wrong for anything the page itself then asks for. The stylesheet is the plain case:
-- gated, it comes back as HTML and the browser renders the splash and the profile question with no
-- styling at all. /boot/status is the subtler one: it is polled several times a second, so a gate
-- answering it injects that page into the loading screen and replaces it on the next tick, which
-- destroys a click before it can be sent.
--
-- Anything served out of a static directory is already past this, because static files are resolved
-- before `before` runs. This list is for the ones the shell serves from code.
local UNGATED = {
  ["/boot/status"] = true,
  ["/theme.css"]   = true,
}

--- A job reports on work the page that started it is still waiting for, so it has to be readable
--- from behind a gate: the first-run form sets the client up before it has answered the question
--- that raised the gate. Not a key in the table above because the id is in the path.
local function ungated(path)
  return UNGATED[path] ~= nil or path:find("^/jobs/") ~= nil
end


--- Runs on the worker thread. Owns the database, the modules and the socket.
--
-- Returns the server so the whole startup sequence can be exercised without a window. Ordering bugs
-- here are invisible to a test that only calls the pieces: reading a module's table before its
-- migrations ran, for one.
function M.serve(port, token, opts)
  opts = opts or {}
  local db      = require("core.base.db")
  local migrate = require("core.base.migrate")
  local cache   = require("core.base.cache")
  local server  = require("core.base.server")
  local modules = require("core.modules")
  local history = require("core.history")
  local page    = require("core.ui.page")
  local view    = require("core.base.view")
  local boot    = require("core.extensions.boot")
  local flavour = require("core.game.flavour")
  local style   = require("core.ui.style")
  local tools    = require("core.game.tools")
  local jobs     = require("core.jobs")
  local notify   = require("core.notify")
  local launch   = require("core.game.launch")
  local mediator = require("core.base.mediator")
  require("core.ui.helpers").install()

  -- Not "hub.db". The working directory is a per-build cache folder, so a relative name would give
  -- every build its own database and hand the user an empty hub after every update.
  db.open(opts.db or require("core.release").db())
  migrate.init(db.handle())
  for _, r in ipairs(migrate.run("core/migrations")) do
    if r.status ~= "skipped" then print(("  %s %s"):format(r.status, r.path)) end
  end
  cache.init(db.handle())
  cache.sweep()

  -- The Discord invite comes from wxl-core's manifest once the boot fetch lands, so it can be
  -- changed without rebuilding. Until then the button simply is not rendered.
  page.config.discord    = nil
  page.config.lost_image =
    "https://bnetcmsus-a.akamaihd.net/cms/blog_header/zo/ZO4ANW9RVELV1781126422562.png"

  -- Artwork for the band each working page opens with. A bare URL is the common case; the table form
  -- exists for a picture whose subject sits on the side the title needs, which the scrim would
  -- otherwise cover. Every host here has to be in the img-src list in core/ui/page.lua.
  page.config.images = {
    library = {
      src  = "https://bnetcmsus-a.akamaihd.net/cms/blog_header/3h/3HY9H7J7HMX21761349941189.png",
      flip = true,
    },
    store = "https://bnetcmsus-a.akamaihd.net/cms/blog_header/e8/E8WQFI083QTW1738635431840.png",
    downloads =
      "https://bnetcmsus-a.akamaihd.net/cms/blog_header/d8/D84JV9ZJWDS01772587429618.png",
    settings =
      "https://bnetcmsus-a.akamaihd.net/cms/blog_header/zq/ZQIXYN40KUPU1764984459732.png",
  }

  local available = tools.detect { "python", "git" }

  print("boot:")
  boot.start()

  -- The cache TTL decides whether a *launch* refetches. On its own that leaves a window open all
  -- afternoon showing what it read at breakfast, so the same expiry is also checked while running.
  -- Every minute, because the check is one indexed row and the fetch only happens when it is due.
  local refresher = uv.new_timer()
  refresher:start(60000, 60000, function()
    if boot.state ~= "loading" and boot.due() and boot.refresh() then
      print("refreshing the catalogue")
    end
  end)
  uv.unref(refresher)

  local app = server.new { token = token }
  app:static("/vendor/", "deps/htmx")
  app:static("/static/", "assets")

  local ctx = {
    boot  = boot,
    tools = available,
  }

  local loaded, failed = modules.load(app, ctx)
  print(("modules: %d loaded, %d failed"):format(#loaded, #failed))
  for _, m in ipairs(loaded) do
    print(("  %-10s %-10s order %d%s"):format(m.id, m.mount or "-", m.order,
          m.dev_only and "  (developer)" or ""))
  end
  for _, f in ipairs(failed) do print("  FAILED " .. f.id .. "\n" .. tostring(f.error)) end

  -- Which flavour line the rotation opens on, and what the splash last showed. One window polls, so
  -- tracking it here is enough to answer 204 when nothing has changed, which is what stops the
  -- text re-rendering, and re-animating, three times a second.
  local seed  = os.time() % #flavour.lines
  local shown = { idx = -1, step = nil }

  app.before = function(req, res)
    -- Before the gates, so it is set for every request that can end up rendering anything.
    page.begin(req)

    -- A navigation is answered with the part of the document that changes, so htmx is told here
    -- where to put it. On the response rather than on the markup: an `hx-target` attribute is
    -- inherited by everything under it, and most fragments in the app mean "replace me" by leaving
    -- the target out entirely.
    if req.boosted then
      res:header("HX-Retarget", "#view")
      res:header("HX-Reswap", "outerHTML show:window:top")
    end

    if ungated(req.path) then return false end

    if not boot.ready() then
      local step, done, total = boot.phase()
      res:html(view.render("splash", {
        stylesheet = style.href,
        csp        = page.CSP_PLAIN,
        line       = flavour.at(boot.elapsed(), seed),
        step       = step, done = done, total = total,
      }))
      return true
    end

    -- Questions that have to be answered before the app opens: today the first-run form and the
    -- profile choice, tomorrow a licence or a migration notice. Core knows only that questions
    -- exist, that each owns a stretch of the URL space, and that the first one still unanswered is
    -- the one to put on screen. It does not know what any of them ask.
    --
    -- A collection rather than a single provider, because there is no reason two modules cannot both
    -- want something before the hub opens. When it was one slot, whoever held it had to answer for
    -- everyone, and unrelated questions ended up branching inside one module.
    local questions = mediator.collect("startup.question")

    -- A question's own flow has to reach its own handlers, or it would answer the very posts that
    -- fill it in. Declared once, here, instead of a path test written again inside each module that
    -- asks something: two copies of this rule is how a poll that belonged to a form ended up being
    -- served the form.
    for _, q in ipairs(questions) do
      if q.owns and req.path:sub(1, #q.owns) == q.owns then return false end
    end

    for _, q in ipairs(questions) do
      local asked = q.render and q.render()
      if asked then
        res:html(asked)
        return true
      end
    end

    return false
  end

  -- The stylesheet, at a URL carrying its own digest. Cached hard because a changed sheet is a
  -- changed URL; see core/ui/style.lua.
  app.router:get("/theme.css", function(req, res)
    res:header("Cache-Control", style.cache_control)
    res:send(200, style.mime, style.css)
  end)

  app.router:get("/boot/status", function(req, res)
    if boot.ready() then return res:hx_redirect("/") end
    local idx = flavour.index_at(boot.elapsed(), seed)
    local step, done, total = boot.phase()
    if idx == shown.idx and step == shown.step and done == shown.done then return res:nothing() end
    shown.idx, shown.step, shown.done = idx, step, done
    res:html(view.render("flavour",
                         { line = flavour.lines[idx], step = step, done = done, total = total }))
  end)

  -- Registered here rather than in a module because more than one of them starts jobs, and the
  -- fragment that reports on one has to look the same wherever it was started from.
  app.router:get("/jobs/:id", function(req, res)
    local job = jobs.get(req.params.id)
    if not job then
      return res:html('<span class="note">that job is no longer around</span>')
    end

    local html = view.render("core:job", { job = jobs.view(job) })

    -- A job that just settled is the only moment the counters in the bar can change without a
    -- navigation, so they ride along out of band. That is why nothing here polls on a timer.
    if job.state ~= "running" then
      local counts = page.counts()
      html = html .. page.pips(counts.unread, counts.queued)
    end
    res:html(html)
  end)

  -- In core because the button is in the bar, on every page, whichever modules happen to be loaded.
  app.router:post("/launch", function(req, res)
    local report = mediator.ask("client.inspect")
    local result = launch.start(report and report.path,
                     { clear_cache = mediator.ask("setting.bool", "clear_cache") })

    if not result.ok then
      return res:html(page.toast("bad", "Could not start the client", result.why))
    end
    res:html(page.toast("good", "Client starting",
             result.cleared and (result.cleared .. " cached file(s) removed first") or nil))
  end)

  local function panel(items, unread)
    return view.render("core:notifications", { items = items, ago = notify.ago })
        .. page.pips(unread, page.counts().queued)
  end

  app.router:get("/notifications/panel", function(req, res)
    local items = notify.recent(12)
    -- Opening the panel is what reading is, so the count clears here rather than on a button.
    notify.mark_read()
    res:html(panel(items, 0))
  end)

  app.router:post("/notifications/clear", function(req, res)
    notify.clear()
    res:html(panel({}, 0))
  end)

  app.router:post("/notifications/:id/dismiss", function(req, res)
    notify.dismiss(req.params.id)
    res:html(panel(notify.recent(12), notify.unread()))
  end)

  -- A module that needs the network is not merely hidden from the bar: its routes stop answering,
  -- so a bookmark, a redirect or a stale link cannot walk into a page with no data behind it.
  app.before_route = function(req, res)
    if page.online() then return false end
    local owner = modules.owning(req.path)
    if not owner or not owner.requires_network then return false end

    local to = modules.get("library") and "/library"
    if to and req.path ~= to then
      res:redirect(to)
    else
      res:html(page.notice {
        title = "Offline",
        text  = "This part of the hub reads from the network, and there is nothing cached to show. "
             .. "What you have installed still works.",
        code  = "offline",
      })
    end
    return true
  end

  app.not_found = function(req, res)
    res:html(page.notice {
      title = "This road is not on any map",
      text  = "Nothing answers at " .. req.path .. ". It may land with a later milestone, or it "
           .. "may never have existed.",
      code  = "404 not found",
    }, 404)
  end

  app:listen(port)
  print(("listening on 127.0.0.1:%d"):format(port))
  return app
end

--- Runs on the main thread. Opens the window and nothing else.
function M.run()
  local webview = require("ffi.webview")
  local ffi     = require("ffi")

  local probe = uv.new_tcp()
  probe:bind("127.0.0.1", 0)
  local port = probe:getsockname().port
  probe:close()

  local token = tostring(os.time()) .. tostring(math.floor(os.clock() * 1e6))

  uv.new_thread(function(port, token, cwd)
    local uv2 = require("uv")
    uv2.chdir(cwd)
    package.path = "./?.lua;./?/init.lua;" .. package.path

    require("core.base.log").install(require("core.release").log(), "server")

    local ok, err = xpcall(function()
      require("core.app").serve(port, token)
    end, debug.traceback)
    if not ok then print("SERVER FAILED\n" .. tostring(err)) end

    uv2.run()
  end, port, token, uv.cwd())

  webview.setup("deps/webview")

  -- Hidden and dark from the moment it exists, which is the only way there is no white frame: the
  -- window is created visible and nothing the caller does afterwards is early enough.
  local win = webview.open {
    title = "WarcraftXL Hub", width = 1280, height = 880, debug = true,
    hidden = true, background = { 0x10, 0x12, 0x16 },
  }
  win:icon("assets/logo.ico")

  -- Back where it was left, if it was ever left anywhere. Applied while the window is still hidden,
  -- so nobody watches it jump from the middle of the screen to its corner. The size above is only
  -- the first launch's answer.
  local geometry = require("core.ui.geometry")
  local remembered = geometry.read()
  if remembered then
    win:place(remembered)
    print(("window restored to %dx%d at %d,%d%s"):format(
      remembered.w, remembered.h, remembered.x, remembered.y,
      remembered.maximised and ", maximised" or ""))
  end

  -- Asked for by the page, because the page is the only part of this that gets told when anything
  -- happened. Reading the placement is cheap and writing only happens when it has actually changed,
  -- so a chatty caller costs nothing.
  win:bind("wxlGeom", function()
    geometry.write(win:placement())
    return "null"
  end)
  print("window created, hidden until the first page reports in")

  -- The one thing the UI thread does that is not "show a page". A folder dialog is modal and has to
  -- be owned by the window, so it can only run here; the worker thread has no window to parent to
  -- and would block the server for as long as the dialog stayed open. The page asks over the
  -- binding, gets a path back, and everything after that is an ordinary form post.
  local folderpick = require("ffi.folderpick")
  local json       = require("deps.lua.json")
  win:bind("wxlPickFolder", function(argv)
    local ok, args = pcall(json.decode, argv)
    local start = ok and type(args) == "table" and type(args[1]) == "string" and args[1] or nil
    local chosen = folderpick.pick(win:hwnd(), start, "Choose a folder")
    -- Encoded rather than quoted by hand: a Windows path is mostly backslashes, and every one of
    -- them has to survive as a JSON escape.
    return chosen and json.encode(chosen) or "null"
  end)

  -- What puts the window on screen.
  --
  -- The page announces itself rather than the launcher guessing: nothing on this side knows when a
  -- document has been parsed, and a delay long enough to be safe is a delay everyone waits through
  -- on a fast machine. Injected rather than written into the templates, because `init` runs on every
  -- navigation and the splash, the profile question and the app are three different documents.
  --
  -- It fires on the browser's own error page too, so a hub whose server never came up still shows a
  -- window saying so instead of nothing at all.
  -- `init` runs on every navigation, so this fires on each document. Only the first one is news;
  -- the rest would just be a line saying the window is still visible.
  local visible = false
  win:bind("wxlReady", function()
    win:show()
    if not visible then visible = true; print("window shown") end
    return "null"
  end)
  -- The class it leaves behind is what any entrance animation hangs off. A CSS animation starts when
  -- the style is first resolved, which here is while the window is still hidden, so an animation
  -- written the ordinary way has already run part of its course by the time anyone can see it: the
  -- top of the page looks placed and the bottom snaps into position.
  --
  -- Set on failure as well as on success, because the stylesheet treats its absence as "do not
  -- animate" rather than as "stay invisible". A binding that never answers must cost the page its
  -- entrance, never its content.
  -- The second half of this is what remembers the window. There is no close event to hang it on, so
  -- it reports at the three moments the answer can have changed: a document arrived, a drag or a
  -- resize came to rest, and the window lost focus, which is what happens on the way to closing it.
  win:init([[
addEventListener('DOMContentLoaded', function () {
  var lit = function () { document.documentElement.classList.add('wxl-shown') };
  window.wxlReady ? wxlReady().then(lit, lit) : lit();

  var save = function () { window.wxlGeom && wxlGeom() };
  var idle;
  addEventListener('resize', function () { clearTimeout(idle); idle = setTimeout(save, 400) });
  addEventListener('blur', save);
  save();
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
  print(("navigating to 127.0.0.1:%d"):format(port))

  -- The message loop, and the three lines that say how it ended.
  --
  -- Returning from here is the process's only normal exit, so without a word the log of a window
  -- that vanished and the log of a window that was closed on purpose are the same log: everything
  -- up to "listening", then nothing. The distinction is the whole question when someone reports the
  -- window disappearing, and it costs one line to record.
  local ran, why = xpcall(function() return win:run() end, debug.traceback)
  if ran then
    print("message loop ended, closing")
  else
    print("MESSAGE LOOP FAILED\n" .. tostring(why))
  end

  win:destroy()

  -- The process ends outright, without unwinding anything.
  --
  -- Closing the window while a download is in flight is the case that forces this. The transfer is a
  -- blocking read on a threadpool thread that nothing can interrupt, and Lua tearing itself down
  -- around a live foreign state ends in "PANIC: unprotected error in call to Lua API".
  -- os.exit(0, false) is enough when the worker is merely parked and not enough here.
  --
  -- Nothing is lost by it: the database is committed per statement, and the only casualty is a
  -- partial file in TEMP that the next install overwrites anyway.
  ffi.cdef [[ void ExitProcess(unsigned int code); ]]
  ffi.C.ExitProcess(0)
end

return M
