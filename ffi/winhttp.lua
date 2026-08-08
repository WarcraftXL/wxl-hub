--[[
  HTTPS client over WinHTTP.

  luvi bundles lua-openssl, so TLS on top of a luv socket is possible, but it would mean shipping
  and maintaining a CA bundle, and re-implementing HTTP/1.1 on a BIO. WinHTTP instead uses the
  Windows certificate store (nothing to ship, nothing to keep current) and honours system proxy
  settings, which is what makes the store work on a corporate network without a support ticket.

  Everything here is synchronous and blocks the calling thread. That is fine for startup and for an
  explicit "refresh", which is all M1 needs; anything on a request path has to move to uv's
  threadpool first, or a slow network freezes the UI.
]]

local ffi = require("ffi")

ffi.cdef [[
typedef void *HINTERNET;
typedef int BOOL;
typedef unsigned long DWORD;
typedef unsigned short WCHAR;

HINTERNET WinHttpOpen(const WCHAR *pszAgentW, DWORD dwAccessType,
                      const WCHAR *pszProxyW, const WCHAR *pszProxyBypassW, DWORD dwFlags);
HINTERNET WinHttpConnect(HINTERNET hSession, const WCHAR *pswzServerName,
                         unsigned short nServerPort, DWORD dwReserved);
HINTERNET WinHttpOpenRequest(HINTERNET hConnect, const WCHAR *pwszVerb,
                             const WCHAR *pwszObjectName, const WCHAR *pwszVersion,
                             const WCHAR *pwszReferrer, const WCHAR **ppwszAcceptTypes,
                             DWORD dwFlags);
BOOL WinHttpSendRequest(HINTERNET hRequest, const WCHAR *pwszHeaders, DWORD dwHeadersLength,
                        void *lpOptional, DWORD dwOptionalLength, DWORD dwTotalLength,
                        unsigned long *dwContext);
BOOL WinHttpReceiveResponse(HINTERNET hRequest, void *lpReserved);
BOOL WinHttpQueryHeaders(HINTERNET hRequest, DWORD dwInfoLevel, const WCHAR *pwszName,
                         void *lpBuffer, DWORD *lpdwBufferLength, DWORD *lpdwIndex);
BOOL WinHttpReadData(HINTERNET hRequest, void *lpBuffer, DWORD dwNumberOfBytesToRead,
                     DWORD *lpdwNumberOfBytesRead);
BOOL WinHttpSetTimeouts(HINTERNET hInternet, int nResolveTimeout, int nConnectTimeout,
                        int nSendTimeout, int nReceiveTimeout);
BOOL WinHttpCloseHandle(HINTERNET hInternet);

int MultiByteToWideChar(unsigned int CodePage, DWORD dwFlags, const char *lpMultiByteStr,
                        int cbMultiByte, WCHAR *lpWideCharStr, int cchWideChar);
int WideCharToMultiByte(unsigned int CodePage, DWORD dwFlags, const WCHAR *lpWideCharStr,
                        int cchWideChar, char *lpMultiByteStr, int cbMultiByte,
                        const char *lpDefaultChar, BOOL *lpUsedDefaultChar);
DWORD GetLastError(void);
]]

local winhttp  = ffi.load("winhttp")
local kernel32 = ffi.load("kernel32")

local CP_UTF8 = 65001

local ACCESS_AUTOMATIC_PROXY = 4
local FLAG_SECURE            = 0x00800000
local PORT_HTTPS             = 443

local QUERY_STATUS_CODE = 19
local QUERY_CUSTOM      = 65535
local QUERY_FLAG_NUMBER = 0x20000000

local M = {}

local function towide(s)
  if s == nil then return nil end
  local n = kernel32.MultiByteToWideChar(CP_UTF8, 0, s, #s, nil, 0)
  local buf = ffi.new("WCHAR[?]", n + 1)
  kernel32.MultiByteToWideChar(CP_UTF8, 0, s, #s, buf, n)
  buf[n] = 0
  return buf
end

local function fromwide(buf, nchars)
  local n = kernel32.WideCharToMultiByte(CP_UTF8, 0, buf, nchars, nil, 0, nil, nil)
  if n <= 0 then return "" end
  local out = ffi.new("char[?]", n + 1)
  kernel32.WideCharToMultiByte(CP_UTF8, 0, buf, nchars, out, n, nil, nil)
  return ffi.string(out, n)
end

--- https://host/path -> host, path
local function split_url(url)
  local host, path = url:match("^https://([^/]+)(/.*)$")
  if not host then host, path = url:match("^https://([^/]+)$"), "/" end
  if not host then error("winhttp: only https:// URLs are supported, got " .. tostring(url), 3) end
  return host, path
end

local function query_header(req, name)
  -- Converted once. The call is made twice, to size the buffer and then to fill it, and widening
  -- the name again for the second costs a throwaway buffer per header read.
  local wide = towide(name)
  local len = ffi.new("DWORD[1]", 0)
  local idx = ffi.new("DWORD[1]", 0)
  winhttp.WinHttpQueryHeaders(req, QUERY_CUSTOM, wide, nil, len, idx)
  if len[0] == 0 then return nil end
  local buf = ffi.new("WCHAR[?]", len[0] / 2 + 1)
  idx[0] = 0
  if winhttp.WinHttpQueryHeaders(req, QUERY_CUSTOM, wide, buf, len, idx) == 0 then
    return nil
  end
  return fromwide(buf, len[0] / 2)
end

--- Open a request, send it, and read back the response head.
--
-- Both entry points below need exactly this and differ only in what they do with the body, so it is
-- one function rather than two copies that drift. Returns a handle carrying the live request plus
-- `close`, which every exit path has to call: these are OS handles, and the session outlives the
-- Lua values pointing at it.
--
-- Errors carry this file's own position deliberately. A caller cannot do anything about a WinHTTP
-- failure except report it, and the line number is the useful half of that report.
local function open_request(url, opts, default_timeout)
  local host, path = split_url(url)

  local session = winhttp.WinHttpOpen(towide("wxl-hub"), ACCESS_AUTOMATIC_PROXY, nil, nil, 0)
  if session == nil then
    error(("winhttp: open failed (%d)"):format(kernel32.GetLastError()))
  end

  local t = opts.timeout_ms or default_timeout
  winhttp.WinHttpSetTimeouts(session, t, t, t, t)

  local conn, req
  local function close()
    if req then winhttp.WinHttpCloseHandle(req) end
    if conn then winhttp.WinHttpCloseHandle(conn) end
    winhttp.WinHttpCloseHandle(session)
  end
  local function fail(what)
    local code = kernel32.GetLastError()
    close()
    error(("winhttp: %s failed (%d) for %s"):format(what, code, url))
  end

  conn = winhttp.WinHttpConnect(session, towide(host), PORT_HTTPS, 0)
  if conn == nil then fail("connect") end

  req = winhttp.WinHttpOpenRequest(conn, towide("GET"), towide(path), nil, nil, nil, FLAG_SECURE)
  if req == nil then fail("open request") end

  local headers = {}
  for _, h in ipairs(opts.headers or {}) do headers[#headers + 1] = h end
  if opts.etag then headers[#headers + 1] = "If-None-Match: " .. opts.etag end

  local hdr, hdrlen = nil, 0
  if #headers > 0 then
    local joined = table.concat(headers, "\r\n")
    hdr, hdrlen = towide(joined), #joined
  end

  if winhttp.WinHttpSendRequest(req, hdr, hdrlen, nil, 0, 0, nil) == 0 then fail("send") end
  if winhttp.WinHttpReceiveResponse(req, nil) == 0 then fail("receive") end

  local status = ffi.new("DWORD[1]", 0)
  local slen   = ffi.new("DWORD[1]", ffi.sizeof("DWORD"))
  local sidx   = ffi.new("DWORD[1]", 0)
  if winhttp.WinHttpQueryHeaders(req, bit.bor(QUERY_STATUS_CODE, QUERY_FLAG_NUMBER),
                                 nil, status, slen, sidx) == 0 then
    fail("query status")
  end

  return {
    req    = req,
    status = tonumber(status[0]),
    etag   = query_header(req, "ETag"),
    close  = close,
    fail   = fail,
  }
end

--- GET a URL.
--
-- opts.etag       -> sent as If-None-Match; a 304 comes back with body = nil
-- opts.headers    -> array of "Name: value" strings
-- opts.timeout_ms -> per-phase timeout, default 15s
--
-- Returns { status, body, etag }. A non-2xx status is returned, not raised: 404 and 403 are
-- information the caller acts on, not exceptions.
function M.get(url, opts)
  opts = opts or {}
  local r = open_request(url, opts, 15000)

  local body
  if r.status ~= 304 then
    local chunks, n = {}, 0
    local buf = ffi.new("char[16384]")
    local got = ffi.new("DWORD[1]", 0)
    repeat
      if winhttp.WinHttpReadData(r.req, buf, 16384, got) == 0 then r.fail("read") end
      if got[0] > 0 then
        n = n + 1
        chunks[n] = ffi.string(buf, got[0])
      end
    until got[0] == 0
    body = table.concat(chunks)
  end

  r.close()
  return { status = r.status, body = body, etag = r.etag }
end

--- GET a URL straight into a file.
--
-- Separate from `get` deliberately. A release asset is megabytes of binary, and buffering it into a
-- Lua string only to write it out again doubles peak memory for nothing. This also gives the caller
-- the bytes as they land, which is the only place a progress bar can get an honest number.
--
-- opts.on_chunk(done, total) -> called as data arrives. `total` is 0 when the server sent no
--                               Content-Length, which is normal on a redirected release asset.
-- opts.headers, opts.timeout_ms -> as `get`.
--
-- WinHTTP follows the https redirect a release download starts with, so nothing here has to.
--
-- Returns { status, bytes, etag }. The file is written only on a 2xx; anything else leaves the
-- destination untouched, so a 404 cannot half-replace what is already there.
function M.download(url, dest, opts)
  opts = opts or {}
  local r = open_request(url, opts, 30000)

  local total = tonumber(query_header(r.req, "Content-Length") or "") or 0

  if r.status < 200 or r.status > 299 then
    r.close()
    return { status = r.status, bytes = 0, etag = r.etag }
  end

  local fd = io.open(dest, "wb")
  if not fd then
    r.close()
    error("winhttp: cannot write " .. tostring(dest))
  end

  local buf  = ffi.new("char[65536]")
  local got  = ffi.new("DWORD[1]", 0)
  local done = 0

  -- `fail` closes the OS handles and raises; it knows nothing about this file, and neither does a
  -- progress callback that decides to raise. Wrapping the loop puts the file's close on one line
  -- instead of on every way out of it.
  local ok, err = pcall(function()
    repeat
      if winhttp.WinHttpReadData(r.req, buf, 65536, got) == 0 then r.fail("read") end
      if got[0] > 0 then
        fd:write(ffi.string(buf, got[0]))
        done = done + tonumber(got[0])
        if opts.on_chunk then opts.on_chunk(done, total) end
      end
    until got[0] == 0
  end)

  fd:close()
  -- Level 0: the message already carries the position it was raised at, and re-stamping it here
  -- would point at this line instead of at what went wrong.
  if not ok then error(err, 0) end

  r.close()
  return { status = r.status, bytes = done, etag = r.etag }
end

--- Convenience for the registry: raw.githubusercontent URL for a repo path.
function M.raw_url(repo, ref, path)
  return ("https://raw.githubusercontent.com/%s/%s/%s"):format(repo, ref, path)
end

return M
