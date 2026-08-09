--[[
  Compile every source in the repository, and check that core/ still points the way it says it does.

  Run from the repository root:
      .\deps\luvi\luvi-Windows-amd64-luajit-regular.exe scripts\check

  This loads each .lua and compiles each .etlua without executing either. It opens no database, binds
  no socket and starts no timer, so it is safe to run anywhere and finishes in well under a second.
  What it catches is the class of mistake that otherwise waits until a page is opened: a syntax
  error in a route nobody visited, or a template with an unbalanced tag.

  A template is compiled the way core/base/view.lua compiles it, which is the point. `<%#` is not a
  comment in this etlua and would be reported here rather than at render time.
]]

local uv    = require("uv")
local root  = uv.cwd():gsub("\\", "/")

package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local etlua = require("deps.lua.etlua")

-- Vendored trees hold someone else's code, and build\ holds a copy of ours from a previous run.
local SKIP = { build = true, [".git"] = true, luvi = true, webview = true, sqlite = true,
               htmx = true, node_modules = true }

local broken, lua_n, tpl_n, crossed = 0, 0, 0, 0

local function fail(kind, path, err)
  broken = broken + 1
  print(("%s  %s\n     %s"):format(kind, path:sub(#root + 2), tostring(err)))
end

local function slurp(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local src = fd:read("*a")
  fd:close()
  return src
end

local function walk(dir)
  local scan = uv.fs_scandir(dir)
  if not scan then return end
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then break end
    local path = dir .. "/" .. name

    if kind == "directory" then
      if not SKIP[name] then walk(path) end

    elseif name:match("%.lua$") then
      lua_n = lua_n + 1
      local chunk, err = loadfile(path)
      if not chunk then fail("LUA", path, err) end

    elseif name:match("%.etlua$") then
      tpl_n = tpl_n + 1
      local tpl, err = etlua.compile(slurp(path))
      if not tpl then fail("TPL", path, err) end
    end
  end
end

walk(root)

--[[
  The direction core/ is laid out in, checked rather than described.

  The folders are worth having only for the direction they impose: `base/` is the framework and has
  no business knowing what an extension is, `game/` owns everything that touches the client and is
  reachable only from the files composing the app. Written down in a doc that rule survives about two
  months; checked here it survives.

  The key "" is a module still at core/ root, which is the shared-services layer every folder above
  the framework is allowed to reach.
]]
local ALLOWED = {
  base       = { base = true },
  game       = { game = true },
  extensions = { base = true, extensions = true, [""] = true },
  ui         = { base = true, ui = true, extensions = true, [""] = true },
}

for layer, allowed in pairs(ALLOWED) do
  local dir  = root .. "/core/" .. layer
  local scan = uv.fs_scandir(dir)
  while scan do
    local name = uv.fs_scandir_next(scan)
    if not name then break end
    if name:match("%.lua$") then
      local path = dir .. "/" .. name
      for target in (slurp(path) or ""):gmatch('require%("core%.([%w_%.]+)"%)') do
        local into = target:match("^([%w_]+)%.") or ""
        if not allowed[into] then
          crossed = crossed + 1
          fail("DEP", path, ("core/" .. layer .. "/ may not require core." .. target))
        end
      end
    end
  end
end

print(("\n%d lua, %d etlua, %s  ->  %s")
      :format(lua_n, tpl_n,
              crossed == 0 and "core/ layers clean"
                           or ("%d cross-layer require%s"):format(crossed, crossed == 1 and "" or "s"),
              broken == 0 and "all compile" or (broken .. " broken")))

-- `false` closes without running finalisers, which is what luvi wants when nothing is on the loop.
os.exit(broken == 0 and 0 or 1, false)
