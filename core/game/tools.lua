--[[
  Which external programs are on this machine.

  Resolved by walking PATH rather than by running `python --version`. In a GUI-subsystem binary,
  spawning a console program flashes a black window on screen, and doing that once per tool at every
  startup is a visible defect for information we can get from the filesystem.
]]

local uv = require("uv")

local M = {}

local function exists(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "file"
end

--- Absolute path of `name` on PATH, or nil.
function M.which(name)
  local exts = { ".exe", ".cmd", ".bat", "" }
  for dir in (os.getenv("PATH") or ""):gmatch("[^;]+") do
    dir = dir:gsub("[/\\]+$", "")
    for _, ext in ipairs(exts) do
      local full = dir .. "\\" .. name .. ext
      if exists(full) then return full end
    end
  end
end

--- A name -> path table of everything found, for module availability checks.
function M.detect(names)
  local out = {}
  for _, n in ipairs(names) do
    local p = M.which(n)
    if p then out[n] = p end
  end
  return out
end

return M
