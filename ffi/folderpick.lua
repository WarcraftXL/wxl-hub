--[[
  The native folder picker.

  This is the modern shell dialog (`IFileOpenDialog` in FOS_PICKFOLDERS mode), not the old
  `SHBrowseForFolder` tree: same result, but the old one still looks like Windows 2000 and this app
  is trying not to.

  It is COM with no helper library, so every call goes through the interface's vtable by index. The
  indexes below are the interface's binary contract and are not negotiable: an entry declared in the
  wrong order calls the wrong method and the failure looks like anything but a typo. They are
  declared down to GetResult and no further, because nothing past it is used.

  Modal, so it must run on the thread that owns the window. In this app that is the main thread,
  inside a webview binding; see core/app.lua.
]]

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
typedef struct GUID {
  unsigned long  Data1;
  unsigned short Data2;
  unsigned short Data3;
  unsigned char  Data4[8];
} GUID;

typedef struct IShellItem IShellItem;
typedef struct IShellItemVtbl {
  long (__stdcall *QueryInterface)(IShellItem*, const GUID*, void**);
  unsigned long (__stdcall *AddRef)(IShellItem*);
  unsigned long (__stdcall *Release)(IShellItem*);
  long (__stdcall *BindToHandler)(IShellItem*, void*, const GUID*, const GUID*, void**);
  long (__stdcall *GetParent)(IShellItem*, IShellItem**);
  /* The SIGDN argument is unsigned on purpose. Every useful value has the top bit set, and typing
     it `int` makes LuaJIT saturate the conversion at INT_MAX rather than wrap: the flag bits are
     lost, the call still returns S_OK, and you get the folder's display name instead of its path. */
  long (__stdcall *GetDisplayName)(IShellItem*, unsigned long, uint16_t**);
  long (__stdcall *GetAttributes)(IShellItem*, unsigned long, unsigned long*);
  long (__stdcall *Compare)(IShellItem*, IShellItem*, unsigned long, int*);
} IShellItemVtbl;
struct IShellItem { IShellItemVtbl* lpVtbl; };

typedef struct IFileOpenDialog IFileOpenDialog;
typedef struct IFileOpenDialogVtbl {
  long (__stdcall *QueryInterface)(IFileOpenDialog*, const GUID*, void**);   /*  0 */
  unsigned long (__stdcall *AddRef)(IFileOpenDialog*);                       /*  1 */
  unsigned long (__stdcall *Release)(IFileOpenDialog*);                      /*  2 */
  long (__stdcall *Show)(IFileOpenDialog*, void* owner);                     /*  3 */
  long (__stdcall *SetFileTypes)(IFileOpenDialog*, unsigned int, void*);     /*  4 */
  long (__stdcall *SetFileTypeIndex)(IFileOpenDialog*, unsigned int);        /*  5 */
  long (__stdcall *GetFileTypeIndex)(IFileOpenDialog*, unsigned int*);       /*  6 */
  long (__stdcall *Advise)(IFileOpenDialog*, void*, unsigned long*);         /*  7 */
  long (__stdcall *Unadvise)(IFileOpenDialog*, unsigned long);               /*  8 */
  long (__stdcall *SetOptions)(IFileOpenDialog*, unsigned long);             /*  9 */
  long (__stdcall *GetOptions)(IFileOpenDialog*, unsigned long*);            /* 10 */
  long (__stdcall *SetDefaultFolder)(IFileOpenDialog*, void*);               /* 11 */
  long (__stdcall *SetFolder)(IFileOpenDialog*, void*);                      /* 12 */
  long (__stdcall *GetFolder)(IFileOpenDialog*, void**);                     /* 13 */
  long (__stdcall *GetCurrentSelection)(IFileOpenDialog*, void**);           /* 14 */
  long (__stdcall *SetFileName)(IFileOpenDialog*, const uint16_t*);          /* 15 */
  long (__stdcall *GetFileName)(IFileOpenDialog*, uint16_t**);               /* 16 */
  long (__stdcall *SetTitle)(IFileOpenDialog*, const uint16_t*);             /* 17 */
  long (__stdcall *SetOkButtonLabel)(IFileOpenDialog*, const uint16_t*);     /* 18 */
  long (__stdcall *SetFileNameLabel)(IFileOpenDialog*, const uint16_t*);     /* 19 */
  long (__stdcall *GetResult)(IFileOpenDialog*, void**);                     /* 20 */
} IFileOpenDialogVtbl;
struct IFileOpenDialog { IFileOpenDialogVtbl* lpVtbl; };

long  __stdcall CoInitializeEx(void*, unsigned long);
void  __stdcall CoUninitialize(void);
long  __stdcall CoCreateInstance(const GUID*, void*, unsigned long, const GUID*, void**);
void  __stdcall CoTaskMemFree(void*);

long  __stdcall SHCreateItemFromParsingName(const uint16_t*, void*, const GUID*, void**);

int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, uint16_t*, int);
int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const uint16_t*, int,
                                  char*, int, const char*, int*);
]]

local ole32    = ffi.load("ole32")
local shell32  = ffi.load("shell32")
local kernel32 = ffi.load("kernel32")

local S_OK, S_FALSE       = 0, 1
local RPC_E_CHANGED_MODE  = -2147417850  -- 0x80010106 as a signed long
local COINIT_APARTMENT    = 0x2
local CLSCTX_INPROC       = 0x1
local CP_UTF8             = 65001

local FOS_PICKFOLDERS     = 0x00000020
local FOS_FORCEFILESYSTEM = 0x00000040
local FOS_PATHMUSTEXIST   = 0x00000800
local SIGDN_FILESYSPATH   = 0x80058000

--- Build a GUID from its canonical text. Written out rather than byte-swapped by hand: the first
--- three fields are little-endian integers and the last eight bytes are not, which is exactly the
--- kind of asymmetry a hand-written byte array gets wrong.
local function guid(text)
  local g = ffi.new("GUID")
  local a, b, c, d, e = text:match("^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$")
  if not a then error("folderpick: malformed GUID " .. text) end
  g.Data1 = tonumber(a, 16)
  g.Data2 = tonumber(b, 16)
  g.Data3 = tonumber(c, 16)
  for i = 0, 1 do g.Data4[i]     = tonumber(d:sub(i * 2 + 1, i * 2 + 2), 16) end
  for i = 0, 5 do g.Data4[i + 2] = tonumber(e:sub(i * 2 + 1, i * 2 + 2), 16) end
  return g
end

local CLSID_FileOpenDialog = guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")
local IID_IFileOpenDialog  = guid("D57C7288-D4AD-4768-BE02-9D969532D960")
local IID_IShellItem       = guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")

local function to_wide(s)
  if type(s) ~= "string" or s == "" then return nil end
  local n = kernel32.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
  if n == 0 then return nil end
  local buf = ffi.new("uint16_t[?]", n)
  kernel32.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, n)
  return buf
end

local function from_wide(p)
  if p == nil then return nil end
  local n = kernel32.WideCharToMultiByte(CP_UTF8, 0, p, -1, nil, 0, nil, nil)
  if n <= 1 then return nil end
  local buf = ffi.new("char[?]", n)
  kernel32.WideCharToMultiByte(CP_UTF8, 0, p, -1, buf, n, nil, nil)
  return ffi.string(buf)
end

local M = {}

--- Ask the user for a folder.
--
-- @param owner  HWND the dialog is modal to. Passing nil gives an unowned dialog that can fall
--               behind the app window, so callers should always supply one.
-- @param start  folder to open at, or nil. A path that no longer exists is ignored rather than
--               refused: it is a stale setting, not a reason to withhold the dialog.
-- @param title  dialog caption.
-- @return the chosen path, or nil when the user cancelled or the dialog could not open.
function M.pick(owner, start, title)
  local hr = ole32.CoInitializeEx(nil, COINIT_APARTMENT)
  -- S_FALSE means this thread was already initialised, and the balancing CoUninitialize is still
  -- ours to call. RPC_E_CHANGED_MODE means another apartment model is already in force here, which
  -- we must leave exactly as we found it.
  local ours = (hr == S_OK or hr == S_FALSE)
  local function done(value)
    if ours then ole32.CoUninitialize() end
    return value
  end
  if hr == RPC_E_CHANGED_MODE then ours = false end

  local slot = ffi.new("void*[1]")
  if ole32.CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC,
                            IID_IFileOpenDialog, slot) ~= S_OK then
    return done(nil)
  end
  local dialog = ffi.cast("IFileOpenDialog*", slot[0])

  local options = ffi.new("unsigned long[1]")
  dialog.lpVtbl.GetOptions(dialog, options)
  dialog.lpVtbl.SetOptions(dialog, bit.bor(tonumber(options[0]),
                                           FOS_PICKFOLDERS, FOS_FORCEFILESYSTEM, FOS_PATHMUSTEXIST))

  if title then dialog.lpVtbl.SetTitle(dialog, to_wide(title)) end

  local wide_start = to_wide(start)
  if wide_start then
    local item_slot = ffi.new("void*[1]")
    if shell32.SHCreateItemFromParsingName(wide_start, nil, IID_IShellItem, item_slot) == S_OK then
      local item = ffi.cast("IShellItem*", item_slot[0])
      dialog.lpVtbl.SetFolder(dialog, item)
      item.lpVtbl.Release(item)
    end
  end

  -- Cancelling is a failing HRESULT (HRESULT_FROM_WIN32(ERROR_CANCELLED)), so there is nothing to
  -- tell apart here: anything but S_OK means no folder was chosen.
  if dialog.lpVtbl.Show(dialog, owner) ~= S_OK then
    dialog.lpVtbl.Release(dialog)
    return done(nil)
  end

  local path
  local result_slot = ffi.new("void*[1]")
  if dialog.lpVtbl.GetResult(dialog, result_slot) == S_OK then
    local item = ffi.cast("IShellItem*", result_slot[0])
    local name = ffi.new("uint16_t*[1]")
    if item.lpVtbl.GetDisplayName(item, SIGDN_FILESYSPATH, name) == S_OK then
      path = from_wide(name[0])
      -- The shell allocated it, so the shell's allocator frees it.
      ole32.CoTaskMemFree(name[0])
    end
    item.lpVtbl.Release(item)
  end

  dialog.lpVtbl.Release(dialog)
  return done(path)
end

return M
