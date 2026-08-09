--[[
  The HTTP server.

  A private transport between the WebView and the application, not a web server: it binds
  127.0.0.1 on an ephemeral port and refuses anything without the session token. That gate is the
  only thing standing between the hub's API and every other process on the machine, so it runs before
  routing and has no exceptions.

  Requests are read until the headers are complete and the declared body has arrived; a request split
  across TCP segments is normal rather than an edge case, and treating the first chunk as the whole
  request holds only until a POST grows large enough to fragment.
]]

local uv     = require("uv")
local router = require("core.router")

local M = {}

local STATUS = {
  [200] = "OK", [204] = "No Content", [302] = "Found",
  [400] = "Bad Request", [403] = "Forbidden", [404] = "Not Found",
  [405] = "Method Not Allowed", [500] = "Internal Server Error",
}

local MIME = {
  html = "text/html; charset=utf-8", css = "text/css", js = "application/javascript",
  json = "application/json", png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg",
  svg = "image/svg+xml", ico = "image/x-icon", woff2 = "font/woff2", txt = "text/plain",
}

local function url_decode(s)
  return (s:gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function parse_query(qs)
  local out = {}
  for pair in (qs or ""):gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    if k and k ~= "" then out[url_decode(k)] = url_decode(v) end
  end
  return out
end

local function parse_cookies(header)
  local out = {}
  for k, v in (header or ""):gmatch("([%w_%-]+)=([^;]*)") do out[k] = v end
  return out
end

-- ------------------------------------------------------------- response ----

local Response = {}
Response.__index = Response

local function new_response(client)
  return setmetatable({ _client = client, status = 200, headers = {}, sent = false }, Response)
end

function Response:header(name, value)
  self.headers[#self.headers + 1] = name .. ": " .. value
  return self
end

function Response:send(status, ctype, body)
  if self.sent then return end
  self.sent = true
  body = body or ""

  local head = { ("HTTP/1.1 %d %s"):format(status, STATUS[status] or "OK") }
  if status ~= 204 then
    head[#head + 1] = "Content-Type: " .. ctype
    head[#head + 1] = "Content-Length: " .. #body
  end
  head[#head + 1] = "Connection: close"
  for _, h in ipairs(self.headers) do head[#head + 1] = h end

  self._client:write(table.concat(head, "\r\n") .. "\r\n\r\n" .. body)
  self._client:shutdown(function() self._client:close() end)
end

function Response:html(body, status) self:send(status or 200, MIME.html, body) end
function Response:text(body, status) self:send(status or 200, MIME.txt, body) end
function Response:file(body, ext)    self:send(200, MIME[ext] or "application/octet-stream", body) end

--- 204 tells htmx to leave the DOM alone. Re-sending identical markup instead is what makes a
--- polling fragment flicker and replay its animations.
function Response:nothing() self:send(204, nil, nil) end

function Response:redirect(to)
  self:header("Location", to):send(302, MIME.txt, "")
end

--- htmx follows this instead of swapping, which is how a fragment endpoint can navigate the window.
function Response:hx_redirect(to)
  self:header("HX-Redirect", to):send(200, MIME.html, "")
end

-- -------------------------------------------------------------- request ----

local function parse_request(raw)
  local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
  if not head then return nil end

  local line, rest = head:match("^([^\r\n]+)\r?\n?(.*)$")
  local method, target = line:match("^(%u+)%s+(%S+)")
  if not method then return nil end

  local headers = {}
  for k, v in (rest or ""):gmatch("([%w%-]+):%s*([^\r\n]*)") do headers[k:lower()] = v end

  -- A posted form is the same encoding as a query string, so it is decoded here rather than in each
  -- module that reads one. Every write in the hub arrives this way, htmx posting it for a single
  -- field or for a whole form.
  local ctype = headers["content-type"] or ""
  local form = ctype:find("application/x%-www%-form%-urlencoded") and parse_query(body) or {}

  return {
    method  = method,
    target  = target,
    path    = target:match("^[^?]*"),
    query   = parse_query(target:match("%?(.*)")),
    headers = headers,
    cookies = parse_cookies(headers.cookie),
    body    = body,
    form    = form,
    -- A navigation from a link the shell already framed, rather than the browser being pointed at a
    -- URL. The difference decides how much of the document is worth sending back.
    boosted = headers["hx-boosted"] == "true",

    -- Deliberately not just "htmx sent this". A boosted navigation carries htmx's header too, and
    -- `htmx` is what four modules read to answer with a piece of the page they are already on: the
    -- store's filtered grid, the library's list. Given that test unqualified, asking for a different
    -- page returns the current page's insides, and the document loses the parts that frame it.
    -- Written once here rather than as `and not req.boosted` in each of them.
    htmx    = headers["hx-request"] == "true" and headers["hx-boosted"] ~= "true",
  }
end

--- How many bytes this request will be in total, once its headers have all arrived.
--
-- nil while the header terminator has not been seen yet, which is the caller's signal to keep
-- reading. The answer never changes once given, so a body arriving in fifty segments is measured
-- once rather than re-measured against a re-joined string per segment.
local function expected_length(raw)
  local head_end = raw:find("\r\n\r\n", 1, true)
  if not head_end then return nil end
  local len = tonumber(raw:sub(1, head_end):match("[Cc]ontent%-[Ll]ength:%s*(%d+)") or 0)
  return head_end + 3 + len
end

-- ----------------------------------------------------------------- app -----

local App = {}
App.__index = App

function M.new(opts)
  return setmetatable({
    router   = router.new(),
    token    = assert(opts.token, "server: a token is required"),
    statics  = {},            -- url prefix -> directory on disk
    on_error = opts.on_error,
    not_found = opts.not_found,
  }, App)
end

--- Serve a directory. Paths are resolved inside it and nothing else: a request may not climb out
--- with `..`, and the check is on the requested name rather than the resolved one so there is no
--- normalisation subtlety to get wrong.
function App:static(prefix, dir)
  self.statics[prefix] = dir
  return self
end

local function serve_static(self, req, res)
  for prefix, dir in pairs(self.statics) do
    if req.path:sub(1, #prefix) == prefix then
      local rel = req.path:sub(#prefix + 1)
      if rel == "" or rel:find("%.%.") or rel:find("[\\:]") then return false end

      local fd = io.open(dir .. "/" .. rel, "rb")
      if not fd then return false end
      local body = fd:read("*a")
      fd:close()

      res:header("Cache-Control", "max-age=86400")
      res:file(body, rel:match("%.([%w]+)$"))
      return true
    end
  end
  return false
end

--- Run one stage of the request, and turn a raise into a 500 instead of into a dead server.
--
-- Everything on this path can fail on author input or on a template edit, not just the route
-- handler: `before` renders the splash, `not_found` renders a page, and either raising would
-- propagate out of the libuv read callback and take the worker thread with it. The window would
-- then sit there, apparently fine, answering nothing.
-- Requests that are asked for on a timer rather than by a person, and so say nothing about intent.
local QUIET = { ["/boot/status"] = true, ["/theme.css"] = true }

local function guard(what, path, fn, ...)
  local ok, err = xpcall(fn, debug.traceback, ...)
  if ok then return true, err end
  print(("%s error on %s\n%s"):format(what, path, tostring(err)))
  return false, err
end

function App:handle(raw, client)
  local res = new_response(client)
  local req = parse_request(raw)
  if not req then return res:text("bad request", 400) end

  -- The gate. The token arrives in the URL on the first navigation and as a cookie afterwards;
  -- anything else on this machine has neither.
  if req.query.token ~= self.token and req.cookies.wxl_token ~= self.token then
    return res:text("forbidden", 403)
  end
  if req.query.token == self.token then
    res:header("Set-Cookie", "wxl_token=" .. self.token .. "; Path=/; SameSite=Strict")
  end

  if serve_static(self, req, res) then return end

  -- One line per request, because the last thing that happened before something went wrong is
  -- usually the only clue there is: a window that closes on its own leaves nothing else saying which
  -- click preceded it.
  --
  -- The pollers are left out deliberately. /boot/status runs several times a second and the job
  -- fragments do the same while a transfer is live, so logging them would bury the one line worth
  -- reading under a thousand that say nothing.
  if not QUIET[req.path] and not req.path:find("^/jobs/") then
    print(("%s %s"):format(req.method, req.path))
  end

  local function failed(err)
    if self.on_error then pcall(self.on_error, req, res, err) end
    if not res.sent then res:text("internal error", 500) end
  end

  -- Runs before routing, and can answer on its own. The splash screen uses it: while the startup
  -- fetch is in flight there is no data for a module to render, and having every module check for
  -- itself would be the same test written six times.
  if self.before then
    local ok, answered = guard("before", req.path, self.before, req, res)
    if not ok then return failed(answered) end
    if answered then return end
  end
  if self.before_route then
    local ok, answered = guard("before_route", req.path, self.before_route, req, res)
    if not ok then return failed(answered) end
    if answered then return end
  end

  local handler, params, route = self.router:match(req.method, req.path)
  if not handler then
    if params == "method" then return res:text("method not allowed", 405) end
    if not self.not_found then return res:text("not found", 404) end
    local ok, err = guard("not_found", req.path, self.not_found, req, res)
    if not ok then return failed(err) end
    return
  end

  req.params = params
  req.route  = route

  local ok, err = guard("handler", req.path, handler, req, res)
  if not ok then failed(err) end
end

--- Block until something is listening on `port`, or the timeout runs out. Returns whether it is.
--
-- The window is pointed at a socket another thread is still on its way to binding. That thread has
-- to start, load its modules, and for the application open a database and run its migrations, while
-- the navigation is queued the moment the message loop starts. Whoever wins decides whether the
-- first document is a page or a connection error, which is why the window sometimes came up showing
-- nothing at all.
--
-- Runs the caller's own loop, which is idle at this point: the UI thread hands its loop to
-- `webview_run` immediately afterwards and never uses libuv again.
function M.wait(port, timeout_ms)
  local done, ok = false, false
  local retry = uv.new_timer()
  local guard = uv.new_timer()

  local function attempt()
    local sock = uv.new_tcp()
    local fine = pcall(function()
      sock:connect("127.0.0.1", port, function(err)
        pcall(function() sock:close() end)
        if done then return end
        if err then retry:start(20, 0, attempt) else ok, done = true, true end
      end)
    end)
    if not fine then pcall(function() sock:close() end); retry:start(20, 0, attempt) end
  end

  guard:start(timeout_ms or 8000, 0, function() done = true end)
  attempt()
  while not done do uv.run("once") end

  retry:stop(); retry:close()
  guard:stop(); guard:close()
  return ok
end

function App:listen(port)
  local server = uv.new_tcp()
  server:bind("127.0.0.1", port)
  server:listen(128, function(err)
    assert(not err, err)
    local client = uv.new_tcp()
    server:accept(client)

    -- Joined only while the headers are still incomplete, which is bounded by the header size, and
    -- then once more at the end. Re-joining every segment against a growing string is what makes a
    -- large POST cost the square of its length.
    local parts, have, need = {}, 0, nil
    client:read_start(function(rerr, chunk)
      if rerr or not chunk then client:close(); return end
      parts[#parts + 1] = chunk
      have = have + #chunk

      if not need then
        local head = table.concat(parts)
        parts, have = { head }, #head
        need = expected_length(head)
        if not need then return end
      end

      if have >= need then
        client:read_stop()
        local raw = table.concat(parts)
        -- Nothing above may raise past here: this is a libuv callback, and an error escaping it
        -- ends the loop rather than the request.
        local ok, err = xpcall(self.handle, debug.traceback, self, raw, client)
        if not ok then
          print("request failed on " .. tostring(raw:match("^[^\r\n]*")) .. "\n" .. tostring(err))
          pcall(function() client:close() end)
        end
      end
    end)
  end)
  self._server = server
  return self
end

return M
