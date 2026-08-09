--[[
  What a folder has to be before the hub will treat it as the client.

  The core resolves `Extensions\<name>\<name>.dll` against the process working directory, which for
  the client is the folder holding Wow.exe. "Where is the client" and "where do extensions go" are
  therefore the same answer, and it has to be right before anything can be installed.

  `inspect` reports rather than decides: it returns every check with its verdict, so the settings
  page can say which one failed instead of showing one unhelpful cross.
]]

local uv     = require("uv")
local winver = require("ffi.winver")

local M = {
  -- The only build the core serves. Kept next to the check that uses it rather than in config: it
  -- is not a preference, it is what WXL_CLIENT_BUILD is compiled to on the other side.
  BUILD = 12340,

  -- Capitalised the way the core writes it. Windows does not care, but a folder that matches what
  -- the log prints is one less thing to wonder about.
  EXT_DIR = "Extensions",
}

local function stat(path) return path and uv.fs_stat(path) or nil end

local function is_dir(path)
  local st = stat(path)
  return st ~= nil and st.type == "directory"
end

local function is_file(path)
  local st = stat(path)
  return st ~= nil and st.type == "file"
end

--- Can we create a folder here? Answered by trying, because a permission bit is not the only reason
--- a write fails and testing the real operation is the only honest check.
local function can_create(dir)
  local probe = dir .. "/.wxl-write-probe"
  local made, err = uv.fs_mkdir(probe, tonumber("755", 8))
  if not made then
    -- A probe left behind by a run that died mid-check proves the folder was writable, so this is
    -- the one failure that answers yes.
    return tostring(err or ""):find("EEXIST", 1, true) ~= nil
  end
  uv.fs_rmdir(probe)
  return true
end

--- Everything the hub knows about a candidate folder.
--
-- Never raises. An empty path, a missing folder and a wrong client are all reports with `ok = false`
-- and a list of checks, not errors for the caller to catch.
function M.inspect(path)
  path = tostring(path or ""):gsub("[/\\]+$", "")
  -- A drive root is the one place the separator carries meaning: "D:" names the current directory
  -- on D:, which is not the same folder and usually not any folder at all.
  if path:match("^%a:$") then path = path .. "\\" end

  local r = { path = path, ok = false, checks = {}, ext_dir = nil, build = nil }
  local function check(label, state, detail)
    r.checks[#r.checks + 1] = { label = label, state = state, detail = detail }
  end

  if path == "" then
    check("Folder", "bad", "not set")
    return r
  end
  if not is_dir(path) then
    check("Folder", "bad", "no such folder")
    return r
  end
  check("Folder", "ok", path)

  local exe = path .. "/Wow.exe"
  if not is_file(exe) then
    check("Wow.exe", "bad", "not in this folder")
    return r
  end
  check("Wow.exe", "ok", ("%.1f MB"):format(stat(exe).size / 1048576))

  local version, why = winver.file_version_string(exe)
  local _, _, _, build = winver.file_version(exe)
  r.build = build
  if not version then
    check("Build", "bad", why)
  elseif build ~= M.BUILD then
    check("Build", "bad", version .. ", the core only serves " .. M.BUILD)
  else
    check("Build", "ok", version)
  end

  -- Everything above decides whether this is the client. What follows describes it.
  r.ok = build == M.BUILD

  check("Data folder", is_dir(path .. "/Data") and "ok" or "warn",
        is_dir(path .. "/Data") and "present" or "missing, the client will not start")

  local ext = path .. "/" .. M.EXT_DIR
  r.ext_dir = ext
  if is_dir(ext) then
    local n = 0
    local scan = uv.fs_scandir(ext)
    while scan do
      local name, kind = uv.fs_scandir_next(scan)
      if not name then break end
      if kind == "directory" and name:sub(1, 1) ~= "." then n = n + 1 end
    end
    check(M.EXT_DIR, "ok", n == 0 and "empty" or (n .. " installed"))
  elseif can_create(path) then
    check(M.EXT_DIR, "warn", "not there yet, created on the first install")
  else
    check(M.EXT_DIR, "bad", "cannot be created, the folder is not writable")
    r.ok = false
  end

  -- Whether the client itself has been prepared, read from the mark the patcher leaves and checks
  -- for. Two things have to be true before anything installed here loads, and they fail
  -- independently: the import has to be in the image, and the library it names has to be on disk.
  r.patched = require("utils.pe").has_section(exe, ".wxl")
  check("Wow.exe patched", r.patched and "ok" or "warn",
        r.patched and "the WarcraftXL section is present"
                   or "no WarcraftXL section, the client will start without it")

  local dll = path .. "/WarcraftXL.dll"
  -- Lifted out of the list as well as left in it. Everything else here describes whether this is
  -- the right folder; this one describes whether the framework is in it, which is the only thing
  -- about a valid client anyone can still be asked to fix.
  r.core = { present = is_file(dll), version = is_file(dll) and winver.file_version_string(dll) }
  check("WarcraftXL.dll", r.core.present and "ok" or "warn",
        r.core.present and (r.core.version or "present")
                        or "not deployed, extensions will not load")

  return r
end

return M
