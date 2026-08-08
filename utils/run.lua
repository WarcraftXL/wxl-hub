--[[
  Run a console program, wait for it, and show nobody a console.

  `uv.spawn` needs a running loop and answers through a callback, which is the wrong shape here: the
  one caller is a threadpool worker, where blocking is the whole point and there is no loop to run.
  So this goes straight to CreateProcess and waits.

  The window flag is the reason this file exists rather than `os.execute`. The hub is a GUI-subsystem
  binary with no console of its own, so anything it starts through the C runtime gets a black window
  flashed on screen for as long as it runs. core/tools.lua avoids the problem by never spawning
  anything; here the program has to actually run.
]]

local ffi = require("ffi")

ffi.cdef [[
typedef struct {
  unsigned long  cb;
  char          *lpReserved, *lpDesktop, *lpTitle;
  unsigned long  dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
  unsigned short wShowWindow, cbReserved2;
  unsigned char *lpReserved2;
  void          *hStdInput, *hStdOutput, *hStdError;
} WXL_STARTUPINFOA;

typedef struct {
  void *hProcess, *hThread;
  unsigned long dwProcessId, dwThreadId;
} WXL_PROCESS_INFORMATION;

int  CreateProcessA(const char *app, char *cmd, void *pa, void *ta, int inherit,
                    unsigned long flags, void *env, const char *cwd,
                    WXL_STARTUPINFOA *si, WXL_PROCESS_INFORMATION *pi);
unsigned long WaitForSingleObject(void *h, unsigned long ms);
int  GetExitCodeProcess(void *h, unsigned long *code);
int  CloseHandle(void *h);
unsigned long GetLastError(void);
]]

local k32 = ffi.load("kernel32")

local CREATE_NO_WINDOW = 0x08000000
local INFINITE         = 0xFFFFFFFF

local M = {}

--- Run `exe` with one argument, in `cwd`, and wait. Returns the exit code, or nil plus a reason.
--
-- One argument rather than a list, because that is what the only caller needs and quoting a list
-- correctly for Windows is a job with more edge cases than it has users here.
function M.wait(exe, argument, cwd)
  -- CreateProcess writes into the command line it is given, so it cannot be a Lua string.
  local line = ('"%s" "%s"'):format(exe, argument or "")
  local cmd  = ffi.new("char[?]", #line + 1)
  ffi.copy(cmd, line)

  local si = ffi.new("WXL_STARTUPINFOA")
  si.cb = ffi.sizeof("WXL_STARTUPINFOA")
  local pi = ffi.new("WXL_PROCESS_INFORMATION")

  if k32.CreateProcessA(exe, cmd, nil, nil, 0, CREATE_NO_WINDOW, nil, cwd, si, pi) == 0 then
    return nil, ("cannot start %s (win32 %d)"):format(exe, tonumber(k32.GetLastError()))
  end

  k32.WaitForSingleObject(pi.hProcess, INFINITE)

  local code = ffi.new("unsigned long[1]")
  local got = k32.GetExitCodeProcess(pi.hProcess, code) ~= 0
  k32.CloseHandle(pi.hThread)
  k32.CloseHandle(pi.hProcess)

  if not got then return nil, "the program ended but said nothing about how" end
  return tonumber(code[0])
end

return M
