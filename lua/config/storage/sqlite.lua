-- SQLite boundary shared by the main Lua VM and libuv worker VMs. No Neovim APIs.
local ffi = require('ffi')
ffi.cdef([[
  typedef struct sqlite3 sqlite3;
  typedef struct sqlite3_stmt sqlite3_stmt;
  int sqlite3_open_v2(const char *, sqlite3 **, int, const char *);
  int sqlite3_close(sqlite3 *);
  const char *sqlite3_errmsg(sqlite3 *);
  int sqlite3_exec(sqlite3 *, const char *, void *, void *, char **);
  int sqlite3_prepare_v2(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
  int sqlite3_step(sqlite3_stmt *);
  int sqlite3_finalize(sqlite3_stmt *);
  const unsigned char *sqlite3_column_text(sqlite3_stmt *, int);
  int sqlite3_column_bytes(sqlite3_stmt *, int);
]])
local library = ffi.load(ffi.os == 'Linux' and 'libsqlite3.so.0' or 'sqlite3')
local M = {}
local Database = {}
Database.__index = Database

function M.quote(value)
  assert(not value:find('\0', 1, true), 'SQLite text contains a NUL byte')
  return "'" .. value:gsub("'", "''") .. "'"
end

function Database:exec(sql)
  local code = library.sqlite3_exec(self.handle, sql, nil, nil, nil)
  if code ~= 0 then return false, ffi.string(library.sqlite3_errmsg(self.handle)), code end
  return true
end

function Database:query(sql)
  local statement = ffi.new('sqlite3_stmt *[1]')
  local prepared = library.sqlite3_prepare_v2(self.handle, sql, #sql, statement, nil)
  if prepared ~= 0 then return nil, ffi.string(library.sqlite3_errmsg(self.handle)), prepared end
  local code = library.sqlite3_step(statement[0])
  local value
  local failure
  if code == 100 then -- SQLITE_ROW
    local data = library.sqlite3_column_text(statement[0], 0)
    if data ~= nil then value = ffi.string(data, library.sqlite3_column_bytes(statement[0], 0)) end
  elseif code ~= 101 then -- SQLITE_DONE
    failure = ffi.string(library.sqlite3_errmsg(self.handle))
  end
  library.sqlite3_finalize(statement[0])
  return value, failure, failure and code or nil
end

function Database:close()
  if self.handle then
    ffi.gc(self.handle, nil)
    library.sqlite3_close(self.handle)
    self.handle = nil
  end
end

function M.open(path)
  local handles = ffi.new('sqlite3 *[1]')
  local code = library.sqlite3_open_v2(path, handles, 6, nil) -- READWRITE | CREATE
  if code ~= 0 then
    local failure = handles[0] ~= nil and ffi.string(library.sqlite3_errmsg(handles[0])) or 'SQLite allocation failed'
    if handles[0] ~= nil then library.sqlite3_close(handles[0]) end
    return nil, failure, code
  end
  local database = setmetatable({ handle = ffi.gc(handles[0], library.sqlite3_close) }, Database)
  -- No busy timeout: contention is returned to the event-driven caller.
  local initialized, failure, initialization_code = database:exec([[
    CREATE TABLE IF NOT EXISTS preferences (
      key TEXT PRIMARY KEY NOT NULL,
      payload TEXT NOT NULL
    ) WITHOUT ROWID;
  ]])
  if not initialized then database:close(); return nil, failure, initialization_code end
  return database
end

function M.run(path, sql, query)
  local database, failure, code = M.open(path)
  if not database then return nil, failure, code end
  local succeeded, execution_error, execution_code = database:exec(sql)
  if not succeeded then database:close(); return nil, execution_error, execution_code end
  local value, query_error, query_code = database:query(query)
  database:close()
  return value, query_error, query_code
end

return M
