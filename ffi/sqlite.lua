--[[
  FFI binding to sqlite3.dll (official build from sqlite.org, x64).

  FFI rather than the lsqlite3 rock: a native rock would have to be compiled against luvi's exported
  Lua symbols, which is a build system to maintain. A DLL plus this file is neither.

  Everything here is synchronous, and it runs on the worker thread that also serves HTTP. That is
  correct for what this database holds, being settings, profiles, the deploy ledger and cached
  listings, where queries are microseconds. Anything that could take milliseconds belongs on uv's threadpool
  instead, not here.
]]

local ffi = require("ffi")

ffi.cdef [[
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
typedef long long sqlite3_int64;

int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs);
int sqlite3_close_v2(sqlite3 *db);
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_exec(sqlite3 *db, const char *sql, void *cb, void *arg, char **errmsg);
void sqlite3_free(void *p);

int sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte,
                       sqlite3_stmt **ppStmt, const char **pzTail);
int sqlite3_step(sqlite3_stmt *s);
int sqlite3_reset(sqlite3_stmt *s);
int sqlite3_finalize(sqlite3_stmt *s);

int sqlite3_bind_null(sqlite3_stmt *s, int i);
int sqlite3_bind_int64(sqlite3_stmt *s, int i, sqlite3_int64 v);
int sqlite3_bind_double(sqlite3_stmt *s, int i, double v);
int sqlite3_bind_text(sqlite3_stmt *s, int i, const char *v, int n, void *destructor);
int sqlite3_bind_parameter_count(sqlite3_stmt *s);

int sqlite3_column_count(sqlite3_stmt *s);
const char *sqlite3_column_name(sqlite3_stmt *s, int i);
int sqlite3_column_type(sqlite3_stmt *s, int i);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt *s, int i);
double sqlite3_column_double(sqlite3_stmt *s, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *s, int i);
int sqlite3_column_bytes(sqlite3_stmt *s, int i);

sqlite3_int64 sqlite3_last_insert_rowid(sqlite3 *db);
int sqlite3_changes(sqlite3 *db);
const char *sqlite3_libversion(void);
]]

ffi.cdef [[
int SetDllDirectoryA(const char *lpPathName);
unsigned long GetCurrentDirectoryA(unsigned long nBufferLength, char *lpBuffer);
]]

local kernel32 = ffi.load("kernel32")

local OK, ROW, DONE = 0, 100, 101
local OPEN_READWRITE, OPEN_CREATE = 0x00000002, 0x00000004

local INTEGER, FLOAT, TEXT, NULL_T = 1, 2, 3, 5

-- SQLITE_TRANSIENT, which is the pointer -1 rather than a number: it tells sqlite to copy the bytes
-- it was handed, so the Lua string behind them may be collected the moment the bind returns.
--
-- Built once, and through intptr_t, because that is the only spelling that survives the trace
-- compiler. `ffi.cast("void*", -1)` gives the full-width -1 while the code is interpreted and
-- 0x00000000ffffffff once the path is compiled, which is neither of the two values sqlite treats as
-- a marker. It takes it for a real destructor and calls it, and the process dies executing address
-- 0xffffffff a few hundred queries into a session.
local TRANSIENT = ffi.cast("void*", ffi.cast("intptr_t", -1))

local C
local M = {}

local function absolute(path)
  path = path:gsub("/", "\\"):gsub("\\+$", "")
  if path:match("^%a:\\") or path:match("^\\\\") then return path end
  local buf = ffi.new("char[520]")
  local n = kernel32.GetCurrentDirectoryA(520, buf)
  if n == 0 then error("sqlite: GetCurrentDirectory failed") end
  return ffi.string(buf, n) .. "\\" .. path
end

--- Load sqlite3.dll. Absolute paths for the same reason as the webview binding: SetDllDirectory
-- removes the cwd from the search path, so a relative load afterwards silently stops resolving.
function M.setup(dir)
  dir = absolute(dir or os.getenv("WXL_SQLITE_DIR") or "deps/sqlite")
  if kernel32.SetDllDirectoryA(dir) == 0 then
    error("sqlite: SetDllDirectory failed for " .. dir)
  end
  C = ffi.load(dir .. "\\sqlite3.dll")
  return M
end

function M.version()
  if not C then M.setup() end
  return ffi.string(C.sqlite3_libversion())
end

local Db = {}
Db.__index = Db

local Stmt = {}
Stmt.__index = Stmt

local function db_error(db, what)
  error(("sqlite: %s: %s"):format(what, ffi.string(C.sqlite3_errmsg(db))), 3)
end

--- Open (and create) a database file.
function M.open(path, opts)
  if not C then M.setup(opts and opts.dir) end
  local out = ffi.new("sqlite3*[1]")
  local rc = C.sqlite3_open_v2(path, out,
                               bit.bor(OPEN_READWRITE, OPEN_CREATE), nil)
  if rc ~= OK then
    error(("sqlite: cannot open %s (rc=%d)"):format(path, rc))
  end

  local self = setmetatable({ _db = out[0], _cache = {} }, Db)

  -- WAL survives a hard kill with the database intact, which matters for an app whose whole job is
  -- launching another program that may take the machine down with it. The busy timeout covers the
  -- brief overlap when a second hub instance starts before the first has exited.
  self:exec("PRAGMA journal_mode = WAL")
  self:exec("PRAGMA busy_timeout = 3000")
  self:exec("PRAGMA foreign_keys = ON")
  return self
end

--- Run SQL with no results and no parameters (DDL, pragmas, transaction control).
function Db:exec(sql)
  local err = ffi.new("char*[1]")
  if C.sqlite3_exec(self._db, sql, nil, nil, err) ~= OK then
    local msg = err[0] ~= nil and ffi.string(err[0]) or "unknown"
    C.sqlite3_free(err[0])
    error(("sqlite: exec failed: %s\n  %s"):format(msg, sql), 2)
  end
  return self
end

-- Prepared statements are cached by SQL text: the hot paths here re-run the same handful of queries
-- constantly, and re-preparing each time is the usual reason a SQLite layer feels slow.
function Db:prepare(sql)
  local cached = self._cache[sql]
  if cached then return cached end

  local out = ffi.new("sqlite3_stmt*[1]")
  if C.sqlite3_prepare_v2(self._db, sql, #sql, out, nil) ~= OK then
    db_error(self._db, "prepare failed for: " .. sql)
  end
  local st = setmetatable({ _s = out[0], _db = self._db, sql = sql }, Stmt)
  self._cache[sql] = st
  return st
end

function Stmt:bind(...)
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    local t = type(v)
    local rc
    if v == nil then                   rc = C.sqlite3_bind_null(self._s, i)
    elseif t == "number" then
      if v % 1 == 0 and math.abs(v) < 2 ^ 53 then
                                       rc = C.sqlite3_bind_int64(self._s, i, v)
      else                             rc = C.sqlite3_bind_double(self._s, i, v) end
    elseif t == "boolean" then         rc = C.sqlite3_bind_int64(self._s, i, v and 1 or 0)
    elseif t == "string" then
      rc = C.sqlite3_bind_text(self._s, i, v, #v, TRANSIENT)
    else
      error(("sqlite: cannot bind a %s at position %d"):format(t, i), 3)
    end
    if rc ~= OK then db_error(self._db, "bind failed") end
  end
  return self
end

--- The statement's column names, kept on the statement.
--
-- They are fixed for a given piece of SQL, and reading them back per column per row costs a Lua
-- string per cell. The count is still asked for each time and the cache dropped when it disagrees:
-- prepare_v2 silently re-prepares a statement whose schema changed under it, and a migration that
-- adds a column would otherwise keep filling in names that no longer describe the row.
local function columns(st)
  local n = C.sqlite3_column_count(st._s)
  local names = st._names
  if names and #names == n then return names, n end

  names = {}
  for i = 0, n - 1 do names[i + 1] = ffi.string(C.sqlite3_column_name(st._s, i)) end
  st._names = names
  return names, n
end

local function value_at(s, i)
  local ct = C.sqlite3_column_type(s, i)
  if ct == INTEGER then
    local v = C.sqlite3_column_int64(s, i)
    -- Back to a Lua number when it fits exactly; a boxed int64 compares and concatenates in ways
    -- that surprise every caller.
    return (v >= -2 ^ 53 and v <= 2 ^ 53) and tonumber(v) or v
  elseif ct == FLOAT  then return C.sqlite3_column_double(s, i)
  elseif ct == NULL_T then return nil
  end
  return ffi.string(C.sqlite3_column_text(s, i), C.sqlite3_column_bytes(s, i))
end

local function read_row(s, names, ncol)
  local row = {}
  for i = 0, ncol - 1 do row[names[i + 1]] = value_at(s, i) end
  return row
end

--- Bind and rewind, ready to step. Reset comes first because the previous caller left the statement
--- wherever its own loop ended.
local function armed(self, sql, ...)
  local st = self:prepare(sql)
  C.sqlite3_reset(st._s)
  st:bind(...)
  return st
end

--- Every row, as an array of name-keyed tables.
function Db:rows(sql, ...)
  local st = armed(self, sql, ...)
  local names, ncol = columns(st)

  local out, n = {}, 0
  while true do
    local rc = C.sqlite3_step(st._s)
    if rc == ROW then
      n = n + 1
      out[n] = read_row(st._s, names, ncol)
    elseif rc == DONE then
      break
    else
      C.sqlite3_reset(st._s)
      db_error(self._db, "step failed for: " .. sql)
    end
  end
  C.sqlite3_reset(st._s)
  return out
end

--- First row or nil. Stepped once rather than run through `rows`, so a lookup that happens to match
--- a thousand rows still reads one.
function Db:row(sql, ...)
  local st = armed(self, sql, ...)
  local row
  local rc = C.sqlite3_step(st._s)
  if rc == ROW then
    local names, ncol = columns(st)
    row = read_row(st._s, names, ncol)
  elseif rc ~= DONE then
    C.sqlite3_reset(st._s)
    db_error(self._db, "step failed for: " .. sql)
  end
  C.sqlite3_reset(st._s)
  return row
end

--- First column of the first row, or nil. For `SELECT count(*)`-shaped queries.
function Db:scalar(sql, ...)
  local st = armed(self, sql, ...)
  local v
  if C.sqlite3_step(st._s) == ROW then v = value_at(st._s, 0) end
  C.sqlite3_reset(st._s)
  return v
end

--- Statement with no result set. Returns rows affected.
function Db:run(sql, ...)
  local st = armed(self, sql, ...)
  local rc = C.sqlite3_step(st._s)
  if rc ~= DONE and rc ~= ROW then
    C.sqlite3_reset(st._s)
    db_error(self._db, "step failed for: " .. sql)
  end
  C.sqlite3_reset(st._s)
  return C.sqlite3_changes(self._db)
end

function Db:last_id()
  return tonumber(C.sqlite3_last_insert_rowid(self._db))
end

--- Run `fn` inside a transaction, rolling back if it raises.
function Db:transaction(fn)
  self:exec("BEGIN")
  local ok, err = pcall(fn, self)
  if ok then
    self:exec("COMMIT")
    return err
  end
  pcall(function() self:exec("ROLLBACK") end)
  error(err, 2)
end

--- Apply migrations in order, tracked by PRAGMA user_version.
--
-- `list` is an array of SQL strings; index N is the step from version N-1 to N. Never edit a
-- migration that has shipped; append a new one. The whole run is one transaction, so a failure
-- leaves the database at its previous version rather than half-migrated.
function Db:migrate(list)
  local at = self:scalar("PRAGMA user_version") or 0
  if at >= #list then return at end
  self:transaction(function()
    for v = at + 1, #list do
      self:exec(list[v])
      -- PRAGMA takes no bound parameters.
      self:exec(("PRAGMA user_version = %d"):format(v))
    end
  end)
  return #list
end

function Db:close()
  for _, st in pairs(self._cache) do C.sqlite3_finalize(st._s) end
  self._cache = {}
  if self._db ~= nil then
    C.sqlite3_close_v2(self._db)
    self._db = nil
  end
end

return M
