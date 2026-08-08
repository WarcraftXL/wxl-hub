--[[
  Reading a file's version resource.

  The client's build number is the one fact that decides whether a folder is the right client, and
  Wow.exe already carries it. This reads the binary VS_FIXEDFILEINFO block rather than the version
  string: 3.3.5a spells its FileVersion "3, 3, 5, 12340", commas and spaces included, while the fixed
  block holds the same four numbers as integers.
]]

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
typedef int            BOOL;
typedef unsigned long  DWORD;
typedef unsigned int   UINT;
typedef const char*    LPCSTR;
typedef void*          LPVOID;

DWORD GetFileVersionInfoSizeA(LPCSTR filename, DWORD* handle);
BOOL  GetFileVersionInfoA(LPCSTR filename, DWORD handle, DWORD len, LPVOID data);
BOOL  VerQueryValueA(LPVOID block, LPCSTR sub_block, LPVOID* buffer, UINT* len);

typedef struct {
  DWORD dwSignature;
  DWORD dwStrucVersion;
  DWORD dwFileVersionMS;
  DWORD dwFileVersionLS;
  DWORD dwProductVersionMS;
  DWORD dwProductVersionLS;
  DWORD dwFileFlagsMask;
  DWORD dwFileFlags;
  DWORD dwFileOS;
  DWORD dwFileType;
  DWORD dwFileSubtype;
  DWORD dwFileDateMS;
  DWORD dwFileDateLS;
} VS_FIXEDFILEINFO;
]]

-- A system DLL, so the loader finds it without a path even after SetDllDirectory has taken the
-- working directory out of the search order.
local ver = ffi.load("version")

local M = {}

--- The four parts of a file's version, or nil plus a reason.
--
-- Never raises: a path that is not a PE, or one with the resource stripped, is an ordinary answer
-- here rather than an error to handle upstream.
function M.file_version(path)
  if type(path) ~= "string" or path == "" then return nil, "no path" end

  local handle = ffi.new("DWORD[1]")
  local size = ver.GetFileVersionInfoSizeA(path, handle)
  if size == 0 then return nil, "no version resource" end

  local block = ffi.new("uint8_t[?]", size)
  if ver.GetFileVersionInfoA(path, 0, size, block) == 0 then
    return nil, "version resource unreadable"
  end

  local out, len = ffi.new("LPVOID[1]"), ffi.new("UINT[1]")
  if ver.VerQueryValueA(block, "\\", out, len) == 0 or len[0] == 0 then
    return nil, "no fixed version block"
  end

  local info = ffi.cast("VS_FIXEDFILEINFO*", out[0])
  local ms, ls = tonumber(info.dwFileVersionMS), tonumber(info.dwFileVersionLS)
  return bit.rshift(ms, 16), bit.band(ms, 0xffff),
         bit.rshift(ls, 16), bit.band(ls, 0xffff)
end

--- The four parts joined, for display. nil when there is no resource.
function M.file_version_string(path)
  local a, b, c, d = M.file_version(path)
  if not a then return nil end
  return ("%d.%d.%d.%d"):format(a, b, c, d)
end

return M
