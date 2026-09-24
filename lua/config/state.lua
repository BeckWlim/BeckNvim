-- Shared storage for small preference documents. One namespace is one atomic
-- record; independent preferences never share a read/modify/write file.
local M = {}
local Store = {}
Store.__index = Store
local writers = {}
local sessions = {}
local sequence = 0
local setup_done = false

local function valid_name(name)
  return type(name) == 'string' and #name > 0 and #name <= 128
    and name:match('^[%w_-][%w_.-]*$') ~= nil
end

local function decode(store, source)
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
  if not failure then return end
  vim.schedule(function()
    if store.on_error then
      store.on_error(failure)
    else
      vim.notify('State (' .. store.namespace .. '): ' .. failure, vim.log.levels.WARN)
    end
  end)
end

-- Recursive directory creation is asynchronous, including fresh XDG roots.
local function mkdir(directory, callback)
  vim.uv.fs_mkdir(directory, 448, function(failure)
    if not failure or failure:find('EEXIST', 1, true) then callback(nil); return end
    local parent = vim.fs.dirname(directory)
    if failure:find('ENOENT', 1, true) and parent and parent ~= directory then
      mkdir(parent, function(parent_error)
        if parent_error then callback(parent_error); return end
        mkdir(directory, callback)
      end)
    else
      callback(failure)
    end
  end)
end

local function temporary_path(path)
  sequence = sequence + 1
  return path .. '.' .. vim.uv.os_getpid() .. '.' .. sequence .. '.tmp'
end

local drain
drain = function(path)
  local writer = writers[path]
  if not writer or writer.active or not writer.pending then return end
  local request = writer.pending
  writer.pending = nil
  writer.active = true
  local temporary = temporary_path(path)
  local function finish(failure)
    local function complete()
      writer.active = false
      writer.error = failure
      report(request.store, failure)
      if writer.pending then drain(path) end
    end
    if failure then
      vim.uv.fs_unlink(temporary, function() complete() end)
    else
      complete()
    end
  end
  mkdir(vim.fs.dirname(path), function(directory_error)
    if directory_error then finish(directory_error); return end
    vim.uv.fs_open(temporary, 'wx', 384, function(open_error, descriptor)
      if open_error then finish(open_error); return end
      vim.uv.fs_write(descriptor, request.source, 0, function(write_error, written)
        vim.uv.fs_close(descriptor, function(close_error)
          if write_error or close_error or written ~= #request.source then
            finish(write_error or close_error or 'incomplete state write')
            return
          end
          vim.uv.fs_rename(temporary, path, finish)
        end)
      end)
    end)
  end)
end

-- Synchronous reads are reserved for startup dependencies such as proxy
-- configuration, which must be applied before any plugin starts a process.
function Store:read_sync()
  if self.scope == 'session' then return vim.deepcopy(sessions[self.key]) end
  local descriptor, open_error = vim.uv.fs_open(self.path, 'r', 384)
  if not descriptor then
    return nil, open_error and not open_error:find('ENOENT', 1, true) and open_error or nil
  end
  local statistics, stat_error = vim.uv.fs_fstat(descriptor)
  if not statistics or statistics.type ~= 'file' or statistics.size > self.max_bytes then
    vim.uv.fs_close(descriptor)
    return nil, stat_error or 'saved state is unreadable or too large'
  end
  local source, read_error = vim.uv.fs_read(descriptor, statistics.size, 0)
  vim.uv.fs_close(descriptor)
  if not source then return nil, read_error end
  return decode(self, source)
end

-- Completion always runs on the main loop. The returned function cancels
-- delivery; in-flight descriptors are still closed by their callbacks.
function Store:read(callback)
  local cancelled = false
  local function deliver(document, failure)
    vim.schedule(function()
      if not cancelled then callback(document, failure) end
    end)
  end
  if self.scope == 'session' then
    deliver(vim.deepcopy(sessions[self.key]))
  else
    vim.uv.fs_open(self.path, 'r', 384, function(open_error, descriptor)
      if open_error then
        deliver(nil, not open_error:find('ENOENT', 1, true) and open_error or nil)
        return
      end
      vim.uv.fs_fstat(descriptor, function(stat_error, statistics)
        if not statistics or statistics.type ~= 'file' or statistics.size > self.max_bytes then
          vim.uv.fs_close(descriptor, function() end)
          deliver(nil, stat_error or 'saved state is unreadable or too large')
          return
        end
        vim.uv.fs_read(descriptor, statistics.size, 0, function(read_error, source)
          vim.uv.fs_close(descriptor, function() end)
          if read_error then deliver(nil, read_error); return end
          -- JSON conversion also belongs on the main loop.
          vim.schedule(function()
            if not cancelled then callback(decode(self, source)) end
          end)
        end)
      end)
    end)
  end
  return function() cancelled = true end
end

function Store:write(document)
  local source, encode_error = encode(self, document)
  if not source then return false, encode_error end
  if self.scope == 'session' then
    sessions[self.key] = decode(self, source)
    return true
  end
  local writer = writers[self.path] or { active = false }
  writers[self.path] = writer
  writer.pending = { source = source, store = self }
  writer.error = nil
  drain(self.path)
  return true
end

function Store:flush(timeout_ms)
  if self.scope == 'session' then return true end
  local finished = vim.wait(timeout_ms or 500, function()
    local writer = writers[self.path]
    return not writer or (not writer.active and not writer.pending)
  end, 10)
  if not finished then return false, 'state write timed out' end
  local writer = writers[self.path]
  return not (writer and writer.error), writer and writer.error or nil
end

-- Preserve immediate persistence/error reporting for explicit proxy changes.
function Store:write_sync(document)
  local source, encode_error = encode(self, document)
  if not source then return false, encode_error end
  if self.scope == 'session' then
    sessions[self.key] = decode(self, source)
    return true
  end
  local writer = writers[self.path]
  if writer and (writer.active or writer.pending) then
    self:flush()
    if writer.active or writer.pending then return false, 'state write timed out' end
  end
  local made, mkdir_error = pcall(vim.fn.mkdir, vim.fs.dirname(self.path), 'p', 448)
  if not made then return false, tostring(mkdir_error) end
  local temporary = temporary_path(self.path)
  local descriptor, open_error = vim.uv.fs_open(temporary, 'wx', 384)
  if not descriptor then return false, open_error end
  local written, write_error = vim.uv.fs_write(descriptor, source, 0)
  local closed, close_error = vim.uv.fs_close(descriptor)
  if written ~= #source or not closed then
    vim.uv.fs_unlink(temporary)
    return false, write_error or close_error or 'incomplete state write'
  end
  local renamed, rename_error = vim.uv.fs_rename(temporary, self.path)
  if not renamed then vim.uv.fs_unlink(temporary); return false, rename_error end
  if writer then writer.error = nil end
  return true
end

function M.setup()
  if setup_done then return end
  setup_done = true
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('shared_state_storage', { clear = true }),
    callback = function()
      local finished = vim.wait(500, function()
        for _, writer in pairs(writers) do
          if writer.active or writer.pending then return false end
        end
        return true
      end, 10)
      if not finished then vim.notify('State: pending writes did not finish before exit', vim.log.levels.WARN) end
    end,
  })
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
  local base_directory = settings.directory or vim.fn.stdpath('state')
  local project_root = settings.project_root
  local directory = base_directory
  if scope == 'project' then
    assert(type(project_root) == 'string' and project_root:match('^/'), 'project scope requires an absolute root')
    directory = vim.fs.joinpath(directory, 'projects', vim.fn.sha256(vim.fs.normalize(project_root)))
  end
  M.setup()
  return setmetatable({
    namespace = namespace,
    scope = scope,
    key = namespace .. ':' .. session_id,
    path = settings.path or vim.fs.joinpath(directory, namespace .. '.json'),
    version = version,
    accept_unversioned = settings.accept_unversioned == true,
    max_bytes = max_bytes,
    on_error = settings.on_error,
  }, Store)
end

return M
