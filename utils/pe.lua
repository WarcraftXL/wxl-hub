--[[
  A read-only look at a Windows executable: its sections, and its characteristics.

  Enough of the format to answer one question, and no more. The patcher marks a client it has done
  by adding a section named `.wxl`, and it recognises its own work the same way rather than by
  keeping a list somewhere:

      if (pe.HasSection(kTagSection)) { ... already patched ... }

  Reading the same mark is what keeps the two from ever disagreeing. A version number, a file size or
  a hash would all be a second opinion about a fact the file already carries.

  Nothing here writes. Patching is a separate program's job, and this one only has to be able to say
  whether it has run.

  In `utils/` rather than in `core/`: this is a file-format reader, not a part of the application's
  wiring, and it holds no state and knows nothing about the hub. Not a module either, because the
  first-run form asks the question before any module is guaranteed to exist, and a screen that
  cannot be answered is worse than one nobody customised.
]]

local M = {}

local function u16(s, i) return s:byte(i) + s:byte(i + 1) * 0x100 end
local function u32(s, i)
  return s:byte(i) + s:byte(i + 1) * 0x100 + s:byte(i + 2) * 0x10000 + s:byte(i + 3) * 0x1000000
end

-- IMAGE_FILE_LARGE_ADDRESS_AWARE. The patcher sets it on every run, including on a client it has
-- already done, so it is the one thing that can be true while `.wxl` is absent.
local LARGE_ADDRESS_AWARE = 0x0020

--- Sections and characteristics, or nil plus a reason.
function M.read(path)
  local fd = io.open(path, "rb")
  if not fd then return nil, "cannot be opened" end

  local ok, out = pcall(function()
    local dos = fd:read(0x40)
    if not dos or #dos < 0x40 or dos:sub(1, 2) ~= "MZ" then error("not an executable", 0) end

    -- e_lfanew: where the real header starts. Everything before it is a stub from 1985.
    fd:seek("set", u32(dos, 0x3D))
    local coff = fd:read(24)
    if not coff or #coff < 24 or coff:sub(1, 4) ~= "PE\0\0" then error("no PE header", 0) end

    local sections   = u16(coff, 7)
    local opt_size   = u16(coff, 21)
    local characters = u16(coff, 23)

    -- The section table follows the optional header, whose size is declared rather than fixed: that
    -- is what makes this work for a 32-bit image and a 64-bit one without knowing which it is.
    fd:seek("cur", opt_size)
    local names = {}
    for i = 1, sections do
      local entry = fd:read(40)
      if not entry or #entry < 40 then error("the section table is truncated", 0) end
      names[i] = (entry:sub(1, 8):gsub("%z+$", ""))
    end

    return {
      machine  = u16(coff, 5),
      sections = names,
      large_address_aware = (characters % (LARGE_ADDRESS_AWARE * 2)) >= LARGE_ADDRESS_AWARE,
    }
  end)

  fd:close()
  if not ok then return nil, tostring(out) end
  return out
end

--- Does this image carry a section with that name?
function M.has_section(path, name)
  local pe = M.read(path)
  if not pe then return false end
  for _, s in ipairs(pe.sections) do if s == name then return true end end
  return false
end

return M
