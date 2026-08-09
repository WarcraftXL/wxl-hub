--[[
  What the workspace operates on.

  Every tool in this shell reads or rewrites the files of one client, so there has to be exactly one
  answer to "which one", and it has to be the same answer on every page.

  It defaults to the client the active profile launches, because that is almost always the right one
  and asking twice for the same fact is how the two drift apart. It can be pointed elsewhere, and
  that is the point: rewriting terrain in the folder you also play from is the case worth making
  someone choose out loud rather than the one you fall into. When the two are the same the shell says
  so, in the one place it uses the accent colour.

  The override is a setting rather than a table of its own. It is one path, it belongs to whoever is
  using the hub, and it follows the profile the same way every other preference does.
]]

local mediator = require("core.base.mediator")
local client   = require("core.game.client")

local M = {}

local KEY = "workspace_target"

--- Comparable form. Windows is case-insensitive and takes either separator, so two spellings of one
--- folder must not read as two folders.
local function same(a, b)
  local function norm(p) return (tostring(p or ""):gsub("[/\\]+$", ""):gsub("/", "\\"):lower()) end
  a, b = norm(a), norm(b)
  return a ~= "" and a == b
end

--- The target, as everything in the workspace sees it.
--
-- `info` is a full client.inspect result or nil, so a caller can show the checks without repeating
-- the work. `playing` is the warning the bar draws.
function M.get()
  local profile = mediator.ask("client.inspect")

  local chosen = mediator.ask("setting.get", KEY)
  if chosen == "" then chosen = nil end

  local info = chosen and client.inspect(chosen) or profile
  local set  = info ~= nil and info.path ~= ""

  -- One word for the whole folder, decided here rather than by each page working it out from the
  -- checks. Three states and not two: a valid client without the framework on it is not broken, it is
  -- unfinished, and telling someone their client is wrong when it is merely bare sends them looking
  -- in the one place there is nothing to find.
  local state, verdict = "unset", "No client set"
  if set then
    if not info.ok then
      state, verdict = "bad", "Not a usable 3.3.5a client"
    elseif not (info.patched and info.core.present) then
      state, verdict = "warn", "Valid client, framework not deployed"
    else
      state, verdict = "ok", "Ready to work"
    end
  end

  return {
    info    = info,
    path    = (info and info.path) or "",
    set     = set,
    own     = chosen ~= nil,
    playing = same(info and info.path, profile and profile.path),
    state   = state,
    verdict = verdict,
  }
end

--- Point the workspace at a folder. An empty path puts it back on the profile's client.
function M.set(path)
  mediator.ask("setting.set", KEY, tostring(path or ""))
  return M.get()
end

--- Shortened from the front, because the end of a path is the part that names the folder. Cut on a
--- separator so what is left is still a sequence of folder names rather than half of one.
function M.short(path, keep)
  path = tostring(path or "")
  keep = keep or 44
  if #path <= keep then return path end

  local tail = path:sub(-keep)
  local cut  = tail:find("[/\\]")
  -- The ellipsis as bytes rather than as \u{2026}: this file is read by whatever Lua the bundle ships
  -- with, and a decimal escape needs no version to agree with it.
  return "\226\128\166" .. (cut and tail:sub(cut) or tail)
end

return M
