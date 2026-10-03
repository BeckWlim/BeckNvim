-- Persistent document backend: SQLite I/O, import, retries, and write coalescing.
-- Public consumers use config.state; this backend receives encoded JSON payloads.
local M = { persistent = true }
local sqlite = require('config.storage.sqlite')
local document = require('config.storage.document')
local decode, encode = document.decode, document.encode
local backend_path = assert(vim.api.nvim_get_runtime_file('lua/config/storage/sqlite.lua', false)[1])
local writers, work_requests = {}, {}
local setup_done, closing = false, false

function M.path(directory)
  return vim.fs.joinpath(directory, 'state.db')
end

local function report(store, failure)
  if not failure or closing then return end
  if store.on_error then store.on_error(failure)
  else vim.notify('State (' .. store.namespace .. '): ' .. failure, vim.log.levels.WARN) end
end

local function read_sql(store)
  local database_api = assert(sqlite, 'SQLite is unavailable')
  -- Bound the result before copying it from SQLite into Lua.
  return ('SELECT substr(payload, 1, %d) FROM preferences WHERE key = %s'):format(
    store.max_bytes + 1, database_api.quote(store.key))
end

local function write_sql(store, source, importing)
  local database_api = assert(sqlite, 'SQLite is unavailable')
  local suffix = importing and ' ON CONFLICT(key) DO NOTHING'
    or ' ON CONFLICT(key) DO UPDATE SET payload = excluded.payload'
  return 'INSERT INTO preferences(key, payload) VALUES ('
    .. database_api.quote(store.key) .. ', ' .. database_api.quote(source) .. ')' .. suffix
end

local function mkdir(directory, callback)
  vim.uv.fs_mkdir(directory, 448, function(failure)
    if not failure or failure:find('EEXIST', 1, true) then callback(nil); return end
    local parent = vim.fs.dirname(directory)
    if failure:find('ENOENT', 1, true) and parent and parent ~= directory then
      mkdir(parent, function(parent_error)
        if parent_error then callback(parent_error); return end
        mkdir(directory, callback)
      end)
    else callback(failure) end
  end)
end

local function prepare(path, callback)
  mkdir(vim.fs.dirname(path), function(directory_error)
    if directory_error then callback(directory_error); return end
    vim.uv.fs_open(path, 'a', 384, function(open_error, descriptor)
      if not descriptor then callback(open_error); return end
      vim.uv.fs_fchmod(descriptor, 384, function(mode_error)
        vim.uv.fs_close(descriptor, function(close_error) callback(mode_error or close_error) end)
      end)
    end)
  end)
end

local function prepare_sync(path)
  local made, failure = pcall(vim.fn.mkdir, vim.fs.dirname(path), 'p', 448)
  if not made then return false, tostring(failure) end
  local descriptor, open_error = vim.uv.fs_open(path, 'a', 384)
  if not descriptor then return false, open_error end
  local protected, mode_error = vim.uv.fs_fchmod(descriptor, 384)
  local closed, close_error = vim.uv.fs_close(descriptor)
  return protected and closed, mode_error or close_error
end

local function run_async(store, sql, callback)
  local function launch(attempt)
    if closing then return end
    local work
    work = vim.uv.new_work(function(path, database_path, statement, query)
      local succeeded, result, failure, code = pcall(function()
        return dofile(path).run(database_path, statement, query)
      end)
      if not succeeded then return nil, tostring(result), 0 end
      return result, failure, code
    end, function(result, failure, code)
      work_requests[work] = nil
      vim.schedule(function()
        if closing then return end
        if (code == 5 or code == 6) and attempt < 5 then
          -- SQLITE_BUSY / LOCKED: bounded retry without sleeping the editor.
          vim.defer_fn(function() launch(attempt + 1) end, 10 * 2 ^ attempt)
        else callback(result, failure) end
      end)
    end)
    work_requests[work] = true
    work:queue(backend_path, store.path, sql, read_sql(store))
  end
  prepare(store.path, function(failure)
    vim.schedule(function()
      if failure then callback(nil, failure) else launch(0) end
    end)
  end)
end

local function legacy_document(store, callback)
  vim.uv.fs_open(store.legacy_path, 'r', 384, function(open_error, descriptor)
    if not descriptor then
      vim.schedule(function()
        callback(nil, open_error and not open_error:find('ENOENT', 1, true) and open_error or nil)
      end)
      return
    end
    vim.uv.fs_fstat(descriptor, function(stat_error, statistics)
      if not statistics or statistics.type ~= 'file' or statistics.size > store.max_bytes then
        vim.uv.fs_close(descriptor, function() end)
        vim.schedule(function() callback(nil, stat_error or 'saved state is unreadable or too large') end)
        return
      end
      vim.uv.fs_read(descriptor, statistics.size, 0, function(read_error, source)
        vim.uv.fs_close(descriptor, function() end)
        vim.schedule(function()
          if read_error then callback(nil, read_error) else callback(decode(store, source)) end
        end)
      end)
    end)
  end)
end

function M.read_sync(self)
  local prepared, preparation_error = prepare_sync(self.path)
  if not prepared then return nil, preparation_error end
  local legacy_source
  local statistics = vim.uv.fs_stat(self.legacy_path)
  if statistics then
    if statistics.type ~= 'file' or statistics.size > self.max_bytes then
      return nil, 'saved state is unreadable or too large'
    end
    local descriptor, open_error = vim.uv.fs_open(self.legacy_path, 'r', 384)
    if not descriptor then return nil, open_error end
    local source, read_error = vim.uv.fs_read(descriptor, statistics.size, 0)
    vim.uv.fs_close(descriptor)
    if not source then return nil, read_error end
    local document, decode_error = decode(self, source)
    if not document then return nil, decode_error end
    local encoded_source, encoding_error = encode(self, document)
    if not encoded_source then return nil, encoding_error end
    legacy_source = encoded_source
  end
  local sql = legacy_source and write_sql(self, legacy_source, true) or ''
  local source, failure = sqlite.run(self.path, sql, read_sql(self))
  if failure then return nil, failure end
  local _, decode_error = decode(self, source)
  if decode_error then return nil, decode_error end
  if legacy_source then
    local removed, removal_error = vim.uv.fs_unlink(self.legacy_path)
    if not removed then return nil, removal_error end
  end
  return source
end

function M.read(self, callback)
  local cancelled = false
  local function deliver(source, failure)
    if not cancelled then callback(source, failure) end
  end
  legacy_document(self, function(saved_document, legacy_error)
    if legacy_error then deliver(nil, legacy_error); return end
    local source, encoding_error
    if saved_document then source, encoding_error = encode(self, saved_document) end
    if encoding_error then deliver(nil, encoding_error); return end
    run_async(self, source and write_sql(self, source, true) or '', function(result, failure)
      if failure then deliver(nil, failure); return end
      local _, decode_error = decode(self, result)
      if decode_error then deliver(nil, decode_error); return end
      if source then
        vim.uv.fs_unlink(self.legacy_path, function(removal_error)
          vim.schedule(function()
            if removal_error and not removal_error:find('ENOENT', 1, true) then
              deliver(nil, removal_error)
            else deliver(result) end
          end)
        end)
      else deliver(result) end
    end)
  end)
  return function() cancelled = true end
end

local function drain(writer)
  if writer.active or not writer.pending then return end
  local request = writer.pending
  writer.pending = nil
  writer.active = true
  run_async(request.store, write_sql(request.store, request.source), function(_, failure)
    writer.active = false
    writer.error = failure
    report(request.store, failure)
    if writer.pending then drain(writer)
    else
      local callbacks = writer.callbacks
      writer.callbacks = {}
      for _, callback in ipairs(callbacks) do callback(not failure, failure) end
    end
  end)
end

function M.write(self, source)
  local writer_key = self.path .. ':' .. self.key
  local writer = writers[writer_key] or { callbacks = {} }
  writers[writer_key] = writer
  writer.pending = { source = source, store = self }
  writer.error = nil
  drain(writer)
  return true
end

-- Completion subscription, never a polling flush or an exit-time wait.
function M.when_idle(self, callback)
  local writer = writers[self.path .. ':' .. self.key]
  if writer and (writer.active or writer.pending) then
    writer.callbacks[#writer.callbacks + 1] = callback
  else vim.schedule(function() callback(not (writer and writer.error), writer and writer.error) end) end
end

function M.write_sync(self, source)
  local writer = writers[self.path .. ':' .. self.key]
  if writer and (writer.active or writer.pending) then return false, 'state write is in progress' end
  local prepared, preparation_error = prepare_sync(self.path)
  if not prepared then return false, preparation_error end
  local _, execution_error = sqlite.run(self.path, write_sql(self, source), read_sql(self))
  return not execution_error, execution_error
end

function M.setup()
  if setup_done then return end
  setup_done = true
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('sqlite_state_storage', { clear = true }),
    callback = function()
      closing = true
    end,
    desc = 'Stop SQLite callbacks without blocking exit',
  })
end

return M
