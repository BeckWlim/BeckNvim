-- Shared SQLite documents. Disk work runs in libuv workers; transient settings
-- stay in process memory. Only startup dependencies use synchronous disk I/O.
local M = {}
local Store = {}
Store.__index = Store
local sqlite_loaded, sqlite_module = pcall(require, 'config.storage.sqlite')
local sqlite = sqlite_loaded and sqlite_module or nil
local backend_path = assert(vim.api.nvim_get_runtime_file('lua/config/storage/sqlite.lua', false)[1])
local writers = {}
local work_requests = {}
local sessions = {}
local setup_done = false
local closing = false

local function valid_name(name)
  return type(name) == 'string' and #name > 0 and #name <= 128
    and name:match('^[%w_-][%w_.-]*$') ~= nil
end

local function decode(store, source)
  if not source then return nil end
  if #source > store.max_bytes then return nil, 'saved state exceeds the size limit' end
  local succeeded, document = pcall(vim.json.decode, source)
  if not succeeded or type(document) ~= 'table' or vim.islist(document) then
    return nil, 'saved state is not a JSON object'
  end
  if document.version ~= store.version
      and not (document.version == nil and store.accept_unversioned) then
    return nil, 'unsupported saved state version'
  end
  return document
end

local function encode(store, document)
  if type(document) ~= 'table' or (vim.islist(document) and next(document) ~= nil) then
    return nil, 'state must be an object'
  end
  local saved_document = vim.deepcopy(document)
  saved_document.version = store.version
  local succeeded, source = pcall(vim.json.encode, saved_document)
  if not succeeded then return nil, 'state is not JSON serializable' end
  if #source > store.max_bytes then return nil, 'state exceeds the size limit' end
  return source
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

function Store:read_sync()
  if self.scope == 'session' or not sqlite then
    return vim.deepcopy(sessions[self.memory_key])
  end
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
  local document, decode_error = decode(self, source)
  if decode_error then return nil, decode_error end
  if legacy_source then
    local removed, removal_error = vim.uv.fs_unlink(self.legacy_path)
    if not removed then return nil, removal_error end
  end
  return document
end

function Store:read(callback)
  local cancelled = false
  local function deliver(document, failure)
    if not cancelled then callback(document, failure) end
  end
  if self.scope == 'session' or not sqlite then
    vim.schedule(function() deliver(self:read_sync()) end)
  else
    legacy_document(self, function(document, legacy_error)
      if legacy_error then deliver(nil, legacy_error); return end
      local source, encoding_error
      if document then source, encoding_error = encode(self, document) end
      if encoding_error then deliver(nil, encoding_error); return end
      run_async(self, source and write_sql(self, source, true) or '', function(result, failure)
        if failure then deliver(nil, failure); return end
        local saved_document, decode_error = decode(self, result)
        if decode_error then deliver(nil, decode_error); return end
        if source then
          vim.uv.fs_unlink(self.legacy_path, function(removal_error)
            vim.schedule(function()
              if removal_error and not removal_error:find('ENOENT', 1, true) then
                deliver(nil, removal_error)
              else deliver(saved_document) end
            end)
          end)
        else deliver(saved_document) end
      end)
    end)
  end
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

function Store:write(document)
  local source, failure = encode(self, document)
  if not source then return false, failure end
  if self.scope == 'session' or not sqlite then
    sessions[self.memory_key] = decode(self, source)
    return true
  end
  local writer_key = self.path .. ':' .. self.key
  local writer = writers[writer_key] or { callbacks = {} }
  writers[writer_key] = writer
  writer.pending = { source = source, store = self }
  writer.error = nil
  drain(writer)
  return true
end

-- Completion subscription, never a polling flush or an exit-time wait.
function Store:when_idle(callback)
  if self.scope == 'session' or not sqlite then vim.schedule(function() callback(true) end); return end
  local writer = writers[self.path .. ':' .. self.key]
  if writer and (writer.active or writer.pending) then
    writer.callbacks[#writer.callbacks + 1] = callback
  else vim.schedule(function() callback(not (writer and writer.error), writer and writer.error) end) end
end

function Store:write_sync(document)
  local source, failure = encode(self, document)
  if not source then return false, failure end
  if self.scope == 'session' or not sqlite then
    sessions[self.memory_key] = decode(self, source)
    return true
  end
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
  if not sqlite then
    vim.schedule(function()
      vim.notify('SQLite unavailable: preferences last only for this Neovim process', vim.log.levels.WARN)
    end)
  end
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('shared_state_storage', { clear = true }),
    callback = function()
      closing = true
      sessions = {}
    end,
    desc = 'Release session state; disk saves are best effort without blocking exit',
  })
end

function M.persistent_available()
  return sqlite ~= nil
end

function M.open(namespace, options)
  assert(valid_name(namespace), 'invalid state namespace')
  local settings = options or {}
  local scope = settings.scope or 'global'
  assert(scope == 'global' or scope == 'project' or scope == 'session', 'invalid state scope')
  local version = settings.version or 1
  local max_bytes = settings.max_bytes or 65536
  assert(type(version) == 'number' and version >= 1 and version % 1 == 0, 'invalid state version')
  assert(type(max_bytes) == 'number' and max_bytes >= 1 and max_bytes % 1 == 0, 'invalid state size limit')
  local session_id = settings.session_id or 'default'
  assert(type(session_id) == 'string', 'session ID must be text')
  local base_directory = settings.directory
    or (settings.path and vim.fs.dirname(settings.path)) or vim.fn.stdpath('state')
  local project_root = settings.project_root
  if scope == 'project' then
    assert(type(project_root) == 'string' and project_root:match('^/'), 'project scope requires an absolute root')
  end
  local context = scope == 'project' and vim.fn.sha256(vim.fs.normalize(project_root))
    or scope == 'session' and session_id or ''
  local legacy_directory = scope == 'project' and vim.fs.joinpath(base_directory, 'projects', context)
    or base_directory
  M.setup()
  return setmetatable({
    namespace = namespace,
    scope = scope,
    key = vim.json.encode({ scope, context, namespace }),
    memory_key = vim.json.encode({ base_directory, scope, context, namespace }),
    path = scope ~= 'session' and sqlite and vim.fs.joinpath(base_directory, 'state.db') or nil,
    legacy_path = settings.path or vim.fs.joinpath(legacy_directory, namespace .. '.json'),
    version = version,
    accept_unversioned = settings.accept_unversioned == true,
    max_bytes = max_bytes,
    on_error = settings.on_error,
  }, Store)
end

return M
