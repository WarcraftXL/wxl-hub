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

-- Before the unpack rather than after it. The entries are relative, so they resolve against whatever
-- the working directory is at require time, and setting it here is what lets the block below reach
-- core.log the moment it knows where the log belongs.
package.path = "./?.lua;./?/init.lua;" .. package.path

if bundled then
  local root = (os.getenv("LOCALAPPDATA") or os.getenv("TEMP")):gsub("\\", "/")
  local hub  = root .. "/WarcraftXL/hub"
  local dst  = hub .. "/" .. version()

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

  -- Beside the version folders, not inside one. The launcher and the application it starts are two
  -- processes running two different builds out of two different folders, and a log per folder is two
  -- halves of one story filed separately.
  local log = require("core.base.log")
  log.install(hub .. "/hub.log", "main")
  log.banner(("wxl-hub %s  %s  %s")
             :format(require("core.release").version, version(), os.date("%Y-%m-%d %H:%M:%S")))
end

-- Templates are unpacked once per version into a folder named after that version, so nothing under
-- it can change while the app runs. Saying so lets core.view skip even the stat it would otherwise
-- do to check. Running from a directory leaves it off, which is what makes editing a .etlua and
-- refreshing the window the whole development loop.
if bundled then require("core.base.view").cache = true end

-- One binary, two roles, told apart by where it is running from.
--
-- The copy the user keeps is the launcher: it checks for a newer hub, writes it, and starts it. The
-- copy it writes lives at a fixed path and is the application. Neither can ever replace itself while
-- running, and neither has to: whichever one is doing the writing, the other one is idle.
local role = require("core.release").role()
print("role " .. role)

local entry = role == "launcher" and "core.launcher" or "core.app"
local ok, err = xpcall(function() require(entry).run() end, debug.traceback)
if not ok then
  print("FATAL\n" .. tostring(err))
  os.exit(1, false)
end
