--[[
  The page shell: what wraps a module's body before it reaches the browser.

  Navigation is asked of core.modules rather than declared here, so a module appears in the bar by
  existing. The one thing this file owns is the content security policy, and it owns it because it is
  the wrong decision to leave to a module.

  Two policies, and the difference is not cosmetic. Our own pages may run inline script. A page that
  renders text written by strangers may not: it shares a document with the hub's session cookie, so
  an injected script there could drive the hub's own API. `untrusted = true` is how a module says its
  body came from somewhere else.
]]

local modules  = require("core.modules")
local view     = require("core.view")
local style    = require("core.style")
local mediator = require("core.mediator")

local M = {}

-- Image hosts are named one at a time rather than opened to https:. A blocked image is a visible
-- bug fixed in a minute; a wildcard img-src is an invisible exfiltration channel for any listing the
-- hub renders.
local IMG = "'self' data: https://raw.githubusercontent.com https://bnetcmsus-a.akamaihd.net"

-- 'self' is what lets the stylesheet load at all now that it is a file rather than a <style> block;
-- 'unsafe-inline' still has to stand beside it for the `style=` attributes the cards carry.
local STYLE = "style-src 'self' 'unsafe-inline'"

local CSP_OWN = "default-src 'none'; img-src " .. IMG .. "; "
             .. STYLE .. "; script-src 'self' 'unsafe-inline'; connect-src 'self'"

local CSP_UNTRUSTED = "default-src 'none'; img-src 'self' data: https://raw.githubusercontent.com; "
                   .. STYLE .. "; script-src 'self'; connect-src 'self'"

--- For the two pages that render outside the shell: the splash and the startup profile question.
--
-- They are whole documents of our own with no listing content on them, and they were each carrying a
-- copy of this string. One definition, so a change to what the stylesheet needs cannot reach two of
-- the three pages and leave the third rendering unstyled.
M.CSP_PLAIN = "default-src 'none'; img-src 'self' data:; " .. STYLE .. "; "
           .. "script-src 'self' 'unsafe-inline'; connect-src 'self'"

-- `images` is page id -> artwork URL for the band each working page opens with. Empty is the normal
-- state and renders a gradient, so a page never waits on a picture to exist.
M.config = { discord = nil, lost_image = nil, images = {} }

--- Asked at render time, not cached at startup: toggling developer mode in settings should change
--- the navigation on the next page, not on the next launch. Defaults to on when nothing provides it,
--- which is the case where there is no settings module to turn it off with either.
local function developer()
  return mediator.ask_or("setting.bool", true, "developer")
end

--- Is there any remote data at all? A warm cache counts: the catalogue it holds is real, it is just
--- not fresh. Only a hub that has never fetched, or whose cache expired with no network to refresh
--- it, is offline in the sense that matters here.
function M.online()
  return require("core.boot").state ~= "offline"
end

local function ago(seconds)
  if not seconds then return "an unknown age" end
  if seconds < 5400 then return math.max(1, math.floor(seconds / 60)) .. " minutes old" end
  if seconds < 172800 then return math.floor(seconds / 3600) .. " hours old" end
  return math.floor(seconds / 86400) .. " days old"
end

--- The warning strip, or nil.
--
-- Shown only when the fetch actually failed and an expired copy was used. A fresh cache hit is
-- normal operation, not a problem, and warning on every launch inside the eight-hour window would
-- teach people to ignore the bar that matters.
function M.staleness()
  local boot = require("core.boot")
  if boot.source ~= "stale" then return nil end
  return {
    -- The live age, not the one recorded when it was adopted: an offline session goes on, and the
    -- copy keeps getting older while the banner sits there saying otherwise.
    text = "No connection. What you are seeing is " .. ago(boot.age_now() or boot.age)
        .. " and may not match what is published now.",
  }
end

local NO_STATS = { modules = 0, authors = 0 }

--- What the two icons in the bar count. Wrapped in pcall because they read tables a module owns:
--- the bar is on every page, including the ones that render when a module failed to load, and a bar
--- that cannot draw takes the whole page with it.
function M.counts()
  local function safe(fn)
    local fine, n = pcall(fn)
    return (fine and tonumber(n)) or 0
  end
  return {
    unread = safe(function() return require("core.notify").unread() end),
    queued = safe(function() return require("core.upgrade").count() end),
  }
end

--- The two counters, as out-of-band markup any response can carry back.
--
-- Only the counters, never the tray around them: the notification panel is a <details>, and swapping
-- an open one closes it the instant it is opened.
function M.pips(unread, queued)
  return view.render("traypip", { id = "bellpip", n = unread or 0, oob = true })
      .. view.render("traypip", { id = "dlpip",   n = queued or 0, oob = true })
end

--- The profile name in the bar, out of band.
--
-- Switching profiles changes what the bar says without navigating anywhere, and the alternative was
-- for the profiles module to redirect to the page it happens to be shown on, which means knowing
-- where another module mounted it.
function M.profile_chip()
  local name = mediator.ask_or("profile.name", "Default")
  return ('<span id="profilename" hx-swap-oob="true">%s</span>'):format(name)
end

--- One toast, as markup any response can append to itself.
--
-- Returned rather than queued: a toast belongs to the reply that caused it, so it cannot outlive its
-- reason or arrive attached to some later request.
function M.toast(level, title, text)
  return view.render("toast", { level = level, title = title, text = text, oob = true })
end

-- Toasts with no reply to ride on, waiting for the next full page.
--
-- The exception to the rule above, and a narrow one. Something discovered while the splash was up
-- has no request to attach itself to: the fetch that found it was answering nobody. Rather than let
-- it be lost or invent a place for it, it waits here for the first page that renders, which is the
-- first moment there is a window to show it in.
local waiting = {}

--- Leave a toast for the next full page render.
function M.queue(level, title, text)
  waiting[#waiting + 1] = { level = level, title = title, text = text }
end

--- Whether the request being answered is a navigation from inside the app.
--
-- Held here rather than threaded through every handler's call to `render`, which would mean every
-- module passing a request object it otherwise has no use for. Safe as a single value because one
-- request is handled at a time on this thread: the socket's read callback parses, routes and answers
-- without ever yielding, so there is no second request in flight to confuse it with.
local boosted = false

--- Called by the shell for every request, before anything is routed.
function M.begin(req)
  boosted = (req and req.boosted) or false
end

--- Render a full page around `body`.
--
-- opts: title, active (module id), untrusted (bool), cache_age
--
-- The footer figures are asked for rather than passed in. Making every module carry the catalogue's
-- statistics through its own handler was the coupling in miniature: four modules importing the store
-- to fill in a footer they do not own.
function M.render(body, opts)
  opts = opts or {}
  local counts = M.counts()

  -- Drained, not read: a queued toast is shown by the first page that renders and by no other.
  local toasts = {}
  for i = 1, #waiting do toasts[i] = view.render("toast", waiting[i]) end
  waiting = {}

  -- A navigation from inside the app already has the shell on screen, so it is answered with the
  -- part that changes and the two pieces of shell that depend on which page it is. Same data either
  -- way: only how much of it is written out differs.
  return view.render(boosted and "layout_view" or "layout", {
    toasts     = table.concat(toasts),
    -- Suffixed here so no caller has to remember to. A tab reading only "Store" says nothing once
    -- the window is one of a dozen.
    title      = opts.title and (opts.title .. " · WarcraftXL Hub") or "WarcraftXL Hub",
    body       = body,
    nav        = modules.nav(opts.active, developer(), M.online()),
    stylesheet = style.href,
    csp        = opts.untrusted and CSP_UNTRUSTED or CSP_OWN,
    discord   = require("core.news").support().discord or M.config.discord,
    profile   = mediator.ask_or("profile.name", "Default"),
    unread    = counts.unread,
    queued    = counts.queued,
    stats     = opts.stats or mediator.ask_or("catalogue.stats", NO_STATS),
    cache_age = opts.cache_age or mediator.ask_or("catalogue.age", "unknown"),
    stale     = M.staleness(),
    active    = opts.active,
  })
end

--- The full-page dead end, shared by 404 and not-built-yet.
function M.notice(opts)
  local body = view.render("notice", {
    title = opts.title, text = opts.text,
    code  = opts.code or "404 not found",
    image = M.config.lost_image,
  })
  return M.render(body, { title = opts.title })
end

return M
