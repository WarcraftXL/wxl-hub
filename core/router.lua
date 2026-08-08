--[[
  Routing.

  Lapis' router is the reference for the shape, meaning `/store/:id`, named captures and a splat, but
  not for the implementation: it is built on lpeg, and pulling the lapis rock in to reach one file would mean
  vendoring a framework to route a dozen paths. Patterns compile to plain Lua patterns instead.

  Routes are matched most-specific-first, not in declaration order. `/store/new` and `/store/:id`
  both match `/store/new`, and the one without a capture is what the author meant; making that depend
  on which module happened to register first is a bug waiting for a second module.
]]

local M = {}

local Router = {}
Router.__index = Router

function M.new()
  return setmetatable({ routes = {}, exact = {}, dynamic = {}, indexed = true }, Router)
end

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

--- "/store/:id/files/*rest" -> a Lua pattern plus the capture names, in order.
--
-- One pass, escaping only the literal runs. Escaping the whole path first and substituting after
-- does not work: `*` is itself a magic character, so the escape turns `*rest` into `%*rest` and the
-- placeholder pass then leaves a stray `%` welded to the capture.
local function compile(path)
  local names, n_params, has_splat = {}, 0, false
  local out, i = {}, 1

  while i <= #path do
    local s, e, kind, name = path:find("([:%*])([%a_][%w_]*)", i)
    if not s then
      out[#out + 1] = path:sub(i):gsub(MAGIC, "%%%0")
      break
    end
    out[#out + 1] = path:sub(i, s - 1):gsub(MAGIC, "%%%0")
    names[#names + 1] = name
    if kind == ":" then
      out[#out + 1] = "([^/]+)"
      n_params = n_params + 1
    else
      out[#out + 1] = "(.*)"
      has_splat = true
    end
    i = e + 1
  end

  return "^" .. table.concat(out) .. "$", names, n_params, has_splat
end

--- Register a handler. `methods` is a string or an array; "*" matches any.
function Router:add(methods, path, handler, meta)
  local pattern, names, n_params, splat = compile(path)
  if type(methods) == "string" then methods = { methods } end

  local set = {}
  for _, m in ipairs(methods) do set[m:upper()] = true end

  self.routes[#self.routes + 1] = {
    path = path, pattern = pattern, names = names, methods = set,
    handler = handler, meta = meta,
    -- Specificity: literal segments beat captures, and a splat is the least specific thing there is.
    literals = select(2, path:gsub("[^/]+", "")) - n_params - (splat and 1 or 0),
    params = n_params, splat = splat,
  }
  self.indexed = false
  return self
end

function Router:get(path, handler, meta)  return self:add("GET", path, handler, meta) end
function Router:post(path, handler, meta) return self:add("POST", path, handler, meta) end
function Router:any(path, handler, meta)  return self:add("*", path, handler, meta) end

local function rank(a, b)
  if a.splat ~= b.splat then return b.splat end
  if a.literals ~= b.literals then return a.literals > b.literals end
  if a.params ~= b.params then return a.params < b.params end
  return #a.path > #b.path
end

--- Sort once, then split into the two things a lookup actually needs.
--
-- A route with no capture can only ever match one string, so it belongs in a table keyed by that
-- string rather than in a list to be pattern-matched. Most of what the hub registers is literal, and
-- a single list costs a pattern match and a capture table per route per request. `dynamic` keeps
-- only the handful of paths that really do take a parameter, still in specificity order.
local function reindex(self)
  table.sort(self.routes, rank)

  local exact, dynamic = {}, {}
  for _, r in ipairs(self.routes) do
    if r.params == 0 and not r.splat then
      local bucket = exact[r.path]
      if not bucket then bucket = {}; exact[r.path] = bucket end
      bucket[#bucket + 1] = r
    else
      dynamic[#dynamic + 1] = r
    end
  end

  self.exact, self.dynamic, self.indexed = exact, dynamic, true
end

--- Find a handler. Returns handler, params, route, or nil plus a reason so the caller can tell a
--- missing path (404) from a path that exists under another verb (405).
function Router:match(method, path)
  if not self.indexed then reindex(self) end
  method = method:upper()

  -- A literal route outranks every pattern that could also match it, so the exact table is not
  -- merely a shortcut: it is the first tier of the same ordering. A hit here is what `rank` would
  -- have picked anyway.
  local wrong_method = false
  local bucket = self.exact[path]
  if bucket then
    for i = 1, #bucket do
      local r = bucket[i]
      if r.methods[method] or r.methods["*"] then return r.handler, {}, r end
      wrong_method = true
    end
  end

  for i = 1, #self.dynamic do
    local r = self.dynamic[i]
    local caps = { path:match(r.pattern) }
    if caps[1] ~= nil then
      if r.methods[method] or r.methods["*"] then
        local params = {}
        for n, name in ipairs(r.names) do params[name] = caps[n] end
        return r.handler, params, r
      end
      wrong_method = true
    end
  end

  return nil, wrong_method and "method" or "missing"
end

--- Every registered route, for the developer page and for tests.
function Router:list()
  local out = {}
  for _, r in ipairs(self.routes) do
    local verbs = {}
    for m in pairs(r.methods) do verbs[#verbs + 1] = m end
    table.sort(verbs)
    out[#out + 1] = { path = r.path, methods = table.concat(verbs, "|"), meta = r.meta }
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

return M
