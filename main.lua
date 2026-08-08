--[[
  Entry point, for both ways the app runs.

  From a directory (development) it simply starts. From a bundled executable it first unpacks itself
  next to the user's local data, then starts from there.

  The unpack is not a convenience, it is the only thing that works. Two hard constraints:

    * a DLL cannot be loaded out of a zip. webview, WebView2Loader and sqlite3 have to exist as
      files before LoadLibrary will look at them;
    * `luvi.bundle` is mounted only in the main Lua state. The HTTP server runs on a worker thread
      with its own state, where `require('luvi')` succeeds but `luvi.bundle` is nil, so the worker
      could never read a template or a module out of the bundle.

  Unpacking to disk and chdir-ing there makes both problems disappear, and every path in the rest of
  the codebase keeps working unchanged.
]]

local uv   = require("uv")
local luvi = require("luvi")

local bundle = luvi.bundle

local function is_bundled()
  local st = uv.fs_stat(bundle.base)
  return st ~= nil and st.type == "file"
end

local function version()
  -- Wrapped: gsub returns the string *and* a replacement count, and letting both through means
  -- anything that forwards the result, io.write notably, silently gets two arguments.
  return ((bundle.readfile("VERSION") or "dev"):gsub("%s+$", ""))
end

local function mkdirp(path)
  local acc
  for part in path:gmatch("[^/\\]+") do
    acc = acc and (acc .. "/" .. part) or part
    uv.fs_mkdir(acc, 493)
  end
end

local function unpack_to(dst)
  local function walk(rel)
    for _, name in ipairs(bundle.readdir(rel) or {}) do
      local p = rel == "" and name or (rel .. "/" .. name)
      local st = bundle.stat(p)
      if st and st.type == "directory" then
        uv.fs_mkdir(dst .. "/" .. p, 493)
        walk(p)
      elseif st then
        local fd = assert(io.open(dst .. "/" .. p, "wb"))
        fd:write(bundle.readfile(p))
        fd:close()
      end
    end
  end
  walk("")
end

local bundled = is_bundled()

if bundled then
  local root = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP")):gsub("\\", "/")
  local dst  = root .. "/WarcraftXL/hub/" .. version()

  -- The marker is written last, so an unpack interrupted halfway is retried rather than trusted.
  local done = uv.fs_stat(dst .. "/.unpacked")
  if not done then
    mkdirp(dst)
    unpack_to(dst)
    local fd = assert(io.open(dst .. "/.unpacked", "wb"))
    fd:write(version())
    fd:close()
  end

  uv.chdir(dst)

  -- The shipped binary is a GUI-subsystem PE, so there is no console for `print` to reach. Without
  -- somewhere to put it, a failure before the window opens is indistinguishable from nothing
  -- happening at all.
  local log = io.open(dst .. "/hub.log", "w")
  if log then
    log:write("wxl-hub ", version(), "\n")
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      log:write(table.concat(parts, "\t"), "\n")
      log:flush()
    end
  end
end

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Templates are unpacked once per version into a folder named after that version, so nothing under
-- it can change while the app runs. Saying so lets core.view skip even the stat it would otherwise
-- do to check. Running from a directory leaves it off, which is what makes editing a .etlua and
-- refreshing the window the whole development loop.
if bundled then require("core.view").cache = true end

local ok, err = xpcall(function() require("core.app").run() end, debug.traceback)
if not ok then
  print("FATAL\n" .. tostring(err))
  os.exit(1, false)
end
