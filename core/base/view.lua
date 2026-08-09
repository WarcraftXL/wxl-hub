--[[
  etlua views, scoped per module.

  `<%= %>` escapes, `<%- %>` does not. Author input goes through `<%= %>` or through
  core/base/markdown.lua; `<%- %>` is only ever for HTML this codebase produced itself. Getting the two
  backwards fails silently, which is why it is stated here rather than assumed.

  Name resolution, from a module's renderer:

      render("card")           modules/<id>/views/card.etlua, then views/card.etlua
      render("core:layout")    views/layout.etlua
      render("store:card")     modules/store/views/card.etlua

  A module can therefore override a shared partial by name without touching the shared one, and can
  borrow another module's partial only by saying so explicitly.

  Compiled templates are always kept. `M.cache = true` keeps them unconditionally; false revalidates
  against the file's mtime, which is one stat instead of a read plus a full etlua compile. Editing a
  .etlua and refreshing the window is still the whole development loop, and a page that renders one
  partial thirty times compiles it once either way.
]]

local uv    = require("uv")
local etlua = require("deps.lua.etlua")

local M = { cache = false }

-- path -> { tpl, sec, nsec }. The timestamps are what a non-caching run compares against.
local entries = {}
-- owner .. "\0" .. name -> path. Which file backs a name cannot change while the app runs; only its
-- contents can. Adding a view to a module is therefore picked up on the next start, and editing one
-- is picked up immediately, which is the pair that matters.
local resolved = {}
local helpers  = {}
-- owner -> the environment metatable its templates render under. Built once rather than per render:
-- a page that renders a partial in a loop would otherwise allocate a table and a closure per pass.
local metas = {}

--- Register a helper available inside every template.
function M.helper(name, fn)
  helpers[name] = fn
  return M
end

local function read(path)
  local fd = io.open(path, "rb")
  if not fd then return nil end
  local src = fd:read("*a")
  fd:close()
  return src
end

local function exists(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "file"
end

--- "store:card" / "card" -> the file that backs it, given the module asking.
local function locate(name, owner)
  local key = (owner or "") .. "\0" .. name
  local hit = resolved[key]
  if hit then return hit end

  local path
  local scope, plain = name:match("^([%w_%-%.]+):(.+)$")
  if scope == "core" then
    path = "views/" .. plain .. ".etlua"
  elseif scope then
    path = "modules/" .. scope .. "/views/" .. plain .. ".etlua"
  else
    local own = owner and ("modules/" .. owner .. "/views/" .. name .. ".etlua")
    path = (own and exists(own)) and own or ("views/" .. name .. ".etlua")
  end

  resolved[key] = path
  return path
end

local function load(path)
  local e = entries[path]
  if e then
    if M.cache then return e.tpl end
    local st = uv.fs_stat(path)
    if st and st.mtime.sec == e.sec and st.mtime.nsec == e.nsec then return e.tpl end
  end

  local src = read(path)
  if not src then error("view not found: " .. path, 3) end
  local tpl, err = etlua.compile(src)
  if not tpl then error("view " .. path .. ": " .. tostring(err), 3) end

  local st = uv.fs_stat(path)
  entries[path] = { tpl = tpl, sec = st and st.mtime.sec, nsec = st and st.mtime.nsec }
  return tpl
end

local function meta_for(owner)
  local key = owner or ""
  local m = metas[key]
  if m then return m end

  local nested = function(n, c) return M.render(n, c, owner) end
  m = {
    __index = function(_, k)
      if k == "render" then return nested end
      local h = helpers[k]
      if h ~= nil then return h end
      -- Falling through to _G is what lets a template call tostring or ipairs. The cost is that a
      -- name the caller did not pass resolves to the global of that name instead of nil: a variable
      -- called `error`, `type` or `next` is therefore always truthy, and `<% if error then %>` runs
      -- every time. Name template variables so they cannot collide.
      return _G[k]
    end,
  }
  metas[key] = m
  return m
end

--- Render by name. `owner` scopes bare names to a module's own views.
function M.render(name, ctx, owner)
  return load(locate(name, owner))(setmetatable(ctx or {}, meta_for(owner)))
end

--- A renderer bound to one module, which is what modules actually hold.
function M.for_module(id)
  return {
    render = function(name, ctx) return M.render(name, ctx, id) end,
  }
end

return M
