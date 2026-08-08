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

-- First line of a file, trimmed. nil when there is no file, which is how every marker here is read:
-- absent and empty mean the same thing to the caller.
local function slurp(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local s = (fd:read("*l") or ""):gsub("%s+$", "")
  fd:close()
  return s ~= "" and s or nil
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

-- Which unpacked tree to run.
--
-- The executable ships one, and the updater can leave a newer one beside it. This function is the
-- only thing that chooses between them, and it is also the one piece of the program a payload
-- update can never replace: the copy that runs is always the executable's own. It therefore does as
-- little as possible, and everything it does is reversible.
--
-- The guard is the reason it is worth the lines. `trying` is written here and cleared by the
-- application once it has served a page, so finding one on entry means the tree it names loaded far
-- enough to be chosen and never came up. That candidate is dropped and the shipped tree runs
-- instead. A bad payload costs one launch rather than an install.
local function choose(hub, shipped, ours)
  local updates = hub .. "/updates"

  if uv.fs_stat(updates .. "/trying") then
    os.remove(updates .. "/trying")
    os.remove(updates .. "/USE")
    return shipped, "an update failed to start and was rolled back"
  end

  local name = slurp(updates .. "/USE")
  -- The name reaches a path, so it is checked as one. Anything outside this alphabet, ".." first
  -- among them, is not a folder this program wrote.
  if not name or not name:match("^[%w%.%-_]+$") then return shipped end

  local candidate = updates .. "/" .. name
  if not uv.fs_stat(candidate .. "/.ok") then return shipped end

  -- A payload states the oldest executable it will run under. Build stamps are yyyymmdd-hhmmss, so
  -- comparing them as text is comparing them as dates. Refusing here is the whole reason a payload
  -- may assume things about its container: the alternative is finding out by crashing.
  local floor = slurp(candidate .. "/REQUIRES")
  if floor and floor > ours then
    return shipped, ("update %s needs a newer WarcraftXL Hub and was skipped"):format(name)
  end

  local fd = io.open(updates .. "/trying", "wb")
  if not fd then return shipped end
  fd:write(name)
  fd:close()
  return candidate
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

  local live, why = choose(hub, dst, version())
  uv.chdir(live)

  local log = require("core.log")
  log.install(live .. "/hub.log", "main")
  log.banner(("wxl-hub %s  %s"):format(version(), os.date("%Y-%m-%d %H:%M:%S")))
  -- Two launches of the same executable can be running different code, and this is where anyone
  -- reading a bug report finds out which.
  print("payload " .. (slurp(live .. "/PAYLOAD") or "?"))
  if why then print(why) end
end

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
