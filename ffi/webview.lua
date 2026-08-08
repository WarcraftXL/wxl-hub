--[[
  FFI binding to webview.dll (modern API, 0.11+).

  The API this targets returns webview_error_t from nearly every entry point; the pre-0.11 API
  returned void. Binding the wrong one still loads and still runs, then misbehaves in ways that look
  like WebView2 problems, so `open` checks webview_version() and refuses a mismatch outright.
]]

local ffi = require("ffi")

ffi.cdef [[
typedef void *webview_t;

typedef enum {
  WEBVIEW_HINT_NONE = 0,
  WEBVIEW_HINT_MIN  = 1,
  WEBVIEW_HINT_MAX  = 2,
  WEBVIEW_HINT_FIXED = 3
} webview_hint_t;

typedef enum {
  WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW = 0,
  WEBVIEW_NATIVE_HANDLE_KIND_UI_WIDGET = 1,
  WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER = 2
} webview_native_handle_kind_t;

typedef struct { unsigned int major, minor, patch; } webview_version_t;
typedef struct {
  webview_version_t version;
  char version_number[32];
  char pre_release[48];
  char build_metadata[48];
} webview_version_info_t;

typedef void (*webview_bind_fn_t)(const char *id, const char *req, void *arg);
typedef void (*webview_dispatch_fn_t)(webview_t w, void *arg);

webview_t webview_create(int debug, void *window);
int  webview_destroy(webview_t w);
int  webview_run(webview_t w);
int  webview_terminate(webview_t w);
int  webview_dispatch(webview_t w, webview_dispatch_fn_t fn, void *arg);
void *webview_get_window(webview_t w);
void *webview_get_native_handle(webview_t w, webview_native_handle_kind_t kind);
int  webview_set_title(webview_t w, const char *title);
int  webview_set_size(webview_t w, int width, int height, webview_hint_t hints);
int  webview_navigate(webview_t w, const char *url);
int  webview_set_html(webview_t w, const char *html);
int  webview_init(webview_t w, const char *js);
int  webview_eval(webview_t w, const char *js);
int  webview_bind(webview_t w, const char *name, webview_bind_fn_t fn, void *arg);
int  webview_unbind(webview_t w, const char *name);
int  webview_return(webview_t w, const char *id, int status, const char *result);
const webview_version_info_t *webview_version(void);
]]

ffi.cdef [[
int SetDllDirectoryA(const char *lpPathName);
unsigned long GetCurrentDirectoryA(unsigned long nBufferLength, char *lpBuffer);
void *LoadImageA(void *hInst, const char *name, unsigned int type,
                 int cx, int cy, unsigned int fuLoad);
intptr_t SendMessageA(void *hWnd, unsigned int Msg, uintptr_t wParam, intptr_t lParam);
int ShowWindow(void *hWnd, int nCmdShow);
uintptr_t SetClassLongPtrA(void *hWnd, int nIndex, intptr_t dwNewLong);
]]

ffi.cdef [[
void *CreateSolidBrush(unsigned long color);
]]

local M = {}

local C          -- the loaded library, set by M.setup
local kernel32 = ffi.load("kernel32")
local user32   = ffi.load("user32")
local gdi32    = ffi.load("gdi32")

local ERRORS = {
  [-5] = "missing dependency (WebView2 runtime not installed?)",
  [-4] = "canceled",
  [-3] = "invalid state",
  [-2] = "invalid argument",
  [-1] = "unspecified failure",
  [1]  = "duplicate",
  [2]  = "not found",
}

local function check(rc, what)
  if rc ~= 0 then
    error(("webview: %s failed (%d: %s)"):format(what, rc, ERRORS[rc] or "unknown"), 3)
  end
end

local function absolute(path)
  path = path:gsub("/", "\\"):gsub("\\+$", "")
  -- "C:\..." or a UNC "\\server\..." is already absolute; anything else is relative to the cwd.
  if path:match("^%a:\\") or path:match("^\\\\") then return path end
  local buf = ffi.new("char[520]")
  local n = kernel32.GetCurrentDirectoryA(520, buf)
  if n == 0 then error("webview: GetCurrentDirectory failed") end
  return ffi.string(buf, n) .. "\\" .. path
end

--- Point the loader at the directory holding webview.dll.
--
-- webview.dll resolves WebView2Loader.dll at runtime rather than through its import table, so that
-- directory has to be on the DLL search path for the WebView2 bootstrap to find
-- it.
--
-- Both paths below must be absolute, and that is not cosmetic: SetDllDirectory *removes the current
-- directory* from the search path. Passing it a relative path succeeds (it returns non-zero) and
-- then silently breaks every later relative load, including this one, with a bare
-- ERROR_MOD_NOT_FOUND that names the module it did find.
function M.setup(dir)
  dir = absolute(dir or os.getenv("WXL_WEBVIEW_DIR") or "deps/webview")
  if kernel32.SetDllDirectoryA(dir) == 0 then
    error("webview: SetDllDirectory failed for " .. dir)
  end
  C = ffi.load(dir .. "\\webview.dll")
  return M
end

--- Runtime version of the loaded DLL, as "major.minor.patch".
function M.version()
  if not C then M.setup() end
  local v = C.webview_version()
  return ("%d.%d.%d"):format(v.version.major, v.version.minor, v.version.patch),
         ffi.string(v.version_number)
end

local Window = {}
Window.__index = Window

--- Create a window. `debug = true` enables devtools (F12), which is the only practical way to see
-- why a page misbehaves once htmx is involved.
function M.open(opts)
  if not C then M.setup(opts and opts.dir) end
  opts = opts or {}

  local major = C.webview_version().version.major
  local minor = C.webview_version().version.minor
  if major == 0 and minor < 11 then
    error(("webview: this binding needs API >= 0.11, DLL reports %d.%d"):format(major, minor))
  end

  local handle = C.webview_create(opts.debug and 1 or 0, nil)
  if handle == nil then
    error("webview: create failed. Is the WebView2 runtime installed?")
  end

  local self = setmetatable({
    _h = handle,
    -- FFI callbacks are collectable. Dropping the last Lua reference to one while C still holds the
    -- pointer turns the next JS call into an access violation, so every cast is anchored here for
    -- the window's lifetime.
    _callbacks = {},
  }, Window)

  -- First, and deliberately before the title and the size.
  --
  -- `webview_create` makes the window visible. Nothing paints it yet, because painting needs the
  -- message loop and that does not start until `run`, but the gap is the only place a white frame
  -- can come from and every call made in it widens the gap. Hiding here rather than in the caller is
  -- the difference between "hidden before the loop starts" and "hidden a few statements later".
  if opts.hidden then self:hide() end
  if opts.background then self:background(opts.background[1], opts.background[2], opts.background[3]) end

  if opts.title then self:title(opts.title) end
  if opts.width then self:size(opts.width, opts.height or 600, opts.hint) end
  return self
end

function Window:title(text)
  check(C.webview_set_title(self._h, text), "set_title")
  return self
end

function Window:size(w, h, hint)
  check(C.webview_set_size(self._h, w, h, hint or C.WEBVIEW_HINT_NONE), "set_size")
  return self
end

function Window:navigate(url)
  check(C.webview_navigate(self._h, url), "navigate")
  return self
end

function Window:html(markup)
  check(C.webview_set_html(self._h, markup), "set_html")
  return self
end

--- Inject JS that runs before page scripts, on every navigation.
function Window:init(js)
  check(C.webview_init(self._h, js), "init")
  return self
end

function Window:eval(js)
  check(C.webview_eval(self._h, js), "eval")
  return self
end

--- Expose a Lua function to JS as `window.<name>(...)`, returning a Promise.
--
-- `fn` receives the raw JSON arguments array as a string and returns a raw JSON string (or nil for
-- undefined). Decoding is left to the caller so this binding stays dependency-free.
--
-- The handler runs inside webview's message loop: an error raised here would unwind through C and
-- take the process with it, so it is trapped and turned into a rejected Promise instead.
function Window:bind(name, fn)
  local cb = ffi.cast("webview_bind_fn_t", function(id, req, _)
    local sid = ffi.string(id)
    local ok, result = pcall(fn, ffi.string(req))
    if ok then
      C.webview_return(self._h, sid, 0, result or "null")
    else
      C.webview_return(self._h, sid, 1,
        ('{"message":%q}'):format(tostring(result)))
    end
  end)
  self._callbacks[name] = cb
  check(C.webview_bind(self._h, name, cb, nil), "bind " .. name)
  return self
end

function Window:unbind(name)
  check(C.webview_unbind(self._h, name), "unbind " .. name)
  local cb = self._callbacks[name]
  if cb then cb:free(); self._callbacks[name] = nil end
  return self
end

--- Native HWND, for anything that needs the Win32 handle.
function Window:hwnd()
  return C.webview_get_native_handle(self._h, C.WEBVIEW_NATIVE_HANDLE_KIND_UI_WINDOW)
end

--- Take the window off screen, or put it back.
--
-- `webview_create` makes the window **and** shows it, while the first document is a round trip away
-- on another thread. Nothing can paint that gap: an empty frame is empty whatever colour it is, so
-- the only way not to show it is not to show the window.
function Window:hide() return self:_show(0) end   -- SW_HIDE
function Window:show() return self:_show(5) end   -- SW_SHOW

function Window:_show(cmd)
  local hwnd = self:hwnd()
  if hwnd ~= nil then user32.ShowWindow(hwnd, cmd) end
  return self
end

--- Paint the frame's own background, behind whatever the web view has not drawn.
--
-- The belt to the hiding above: dragging a resize faster than the view repaints exposes the window
-- class brush, and the stock one is white. COLORREF is 0x00BBGGRR, so the channels go in backwards.
function Window:background(r, g, b)
  local hwnd = self:hwnd()
  if hwnd == nil then return self end
  local GCLP_HBRBACKGROUND = -10
  local brush = gdi32.CreateSolidBrush(b * 65536 + g * 256 + r)
  if brush ~= nil then
    user32.SetClassLongPtrA(hwnd, GCLP_HBRBACKGROUND, ffi.cast("intptr_t", brush))
  end
  return self
end

--- Set the window and taskbar icon from a .ico file.
--
-- Two sizes are loaded rather than one scaled: WM_SETICON takes a separate handle for the title bar
-- and for Alt-Tab/taskbar, and letting Windows downscale a 32px icon to 16px is what makes a title
-- bar look muddy. Handles live for the process, which is why they are never destroyed.
function Window:icon(path)
  local file = absolute(path)
  local hwnd = self:hwnd()
  if hwnd == nil then return self end

  local IMAGE_ICON, LR_LOADFROMFILE = 1, 0x0010
  local WM_SETICON, ICON_SMALL, ICON_BIG = 0x0080, 0, 1

  -- LoadImageA lives in user32, not kernel32, despite sitting next to the file APIs in most docs.
  for _, spec in ipairs { { ICON_BIG, 32 }, { ICON_SMALL, 16 } } do
    local h = user32.LoadImageA(nil, file, IMAGE_ICON, spec[2], spec[2], LR_LOADFROMFILE)
    if h ~= nil then
      user32.SendMessageA(hwnd, WM_SETICON, spec[1], ffi.cast("intptr_t", h))
    end
  end
  return self
end

--- Run the message loop. Blocks until the window closes or `terminate` is called.
function Window:run()
  check(C.webview_run(self._h), "run")
  return self
end

function Window:terminate()
  check(C.webview_terminate(self._h), "terminate")
  return self
end

function Window:destroy()
  for name, cb in pairs(self._callbacks) do
    cb:free()
    self._callbacks[name] = nil
  end
  if self._h ~= nil then
    C.webview_destroy(self._h)
    self._h = nil
  end
end

return M
