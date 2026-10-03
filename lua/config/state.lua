-- Plugin-facing document API. Lifetime and scope are independent of the backend.
local M = {}
local Store = {}
Store.__index = Store
local document = require('config.storage.document')
local builtins = { memory = require('config.storage.memory') }
local overrides = {}
local initialized = {}
local default_backend = 'sqlite'
local warned = false

local function valid_name(name)
  return type(name) == 'string' and #name > 0 and #name <= 128
    and name:match('^[%w_-][%w_.-]*$') ~= nil
end

local function backend_named(name)
  if overrides[name] then return overrides[name] end
  if builtins[name] then return builtins[name] end
  if name == 'sqlite' then
    local loaded, backend = pcall(require, 'config.storage.sqlite_store')
    if loaded then builtins.sqlite = backend; return backend end
    return nil
  end
  error('storage backend is not registered: ' .. name)
end

-- Backends receive the store descriptor and encoded JSON strings. Registration
-- affects newly opened stores; existing stores retain their backend instance.
function M.register_backend(name, backend)
  assert(valid_name(name), 'invalid storage backend name')
  if backend == nil then overrides[name] = nil; return end
  assert(type(backend) == 'table' and type(backend.persistent) == 'boolean',
    'storage backend must declare persistent = true or false')
  for _, method in ipairs({ 'read_sync', 'write_sync', 'read', 'write', 'when_idle' }) do
    assert(type(backend[method]) == 'function', 'storage backend is missing ' .. method)
  end
  overrides[name] = backend
end

function M.setup(options)
  if options and options.backend then
    assert(backend_named(options.backend), 'default storage backend is unavailable')
    default_backend = options.backend
  end
  if not backend_named(default_backend) and not warned then
    warned = true
    vim.schedule(function()
      vim.notify('SQLite unavailable: preferences last only for this Neovim process', vim.log.levels.WARN)
    end)
  end
end

function M.persistent_available()
  local backend = backend_named(default_backend)
  return backend ~= nil and backend.persistent
end

function Store:read_sync()
  local source, failure = self.backend.read_sync(self)
  if failure then return nil, failure end
  return document.decode(self, source)
end

function Store:read(callback)
  local cancelled = false
  local cancel = self.backend.read(self, function(source, failure)
    -- The API owns main-loop delivery even when a replacement backend completes
    -- synchronously or from a fast callback.
    vim.schedule(function()
      if cancelled then return end
      if failure then callback(nil, failure); return end
      local decoded, decode_error = document.decode(self, source)
      callback(decoded, decode_error)
    end)
  end)
  return function()
    cancelled = true
    if cancel then cancel() end
  end
end

function Store:write(value)
  local source, failure = document.encode(self, value)
  if not source then return false, failure end
  return self.backend.write(self, source)
end

function Store:write_sync(value)
  local source, failure = document.encode(self, value)
  if not source then return false, failure end
  return self.backend.write_sync(self, source)
end

function Store:when_idle(callback)
  return self.backend.when_idle(self, function(succeeded, failure)
    vim.schedule(function() callback(succeeded, failure) end)
  end)
end

function M.open(namespace, options)
  assert(valid_name(namespace), 'invalid state namespace')
  local settings = options or {}
  local scope = settings.scope or 'global'
  assert(scope == 'global' or scope == 'project' or scope == 'session', 'invalid state scope')
  local requested_backend = settings.backend
  local requested = requested_backend and backend_named(requested_backend) or nil
  local storage = settings.storage
    or (requested and (requested.persistent and 'persistent' or 'memory'))
    or (scope == 'session' and 'memory' or 'persistent')
  assert(storage == 'memory' or storage == 'persistent', 'invalid storage lifetime')
  assert(scope ~= 'session' or storage == 'memory', 'session scope requires memory storage')
  requested_backend = requested_backend or (storage == 'memory' and 'memory' or default_backend)
  assert(valid_name(requested_backend), 'invalid storage backend')
  requested = requested or backend_named(requested_backend)
  assert(not requested or requested.persistent == (storage == 'persistent'),
    'storage backend does not match the requested lifetime')
  local backend = requested or builtins.memory
  local backend_name = requested and requested_backend or 'memory'
  if not requested then storage = 'memory' end
  local version = settings.version or 1
  local max_bytes = settings.max_bytes or 65536
  assert(type(version) == 'number' and version >= 1 and version % 1 == 0, 'invalid state version')
  assert(type(max_bytes) == 'number' and max_bytes >= 1 and max_bytes % 1 == 0, 'invalid state size limit')
  local session_id = settings.session_id or 'default'
  assert(type(session_id) == 'string', 'session ID must be text')
  local directory = settings.directory
    or (settings.path and vim.fs.dirname(settings.path)) or vim.fn.stdpath('state')
  local project_root = settings.project_root
  if scope == 'project' then
    assert(type(project_root) == 'string' and project_root:match('^/'), 'project scope requires an absolute root')
  end
  local context = scope == 'project' and vim.fn.sha256(vim.fs.normalize(project_root))
    or scope == 'session' and session_id or ''
  local legacy_directory = scope == 'project' and vim.fs.joinpath(directory, 'projects', context)
    or directory
  M.setup()
  if not initialized[backend] then
    if backend.setup then backend.setup() end
    initialized[backend] = true
  end
  return setmetatable({
    namespace = namespace, scope = scope, storage = storage,
    backend_name = backend_name, backend = backend,
    key = vim.json.encode({ scope, context, namespace }),
    memory_key = vim.json.encode({ directory, storage, scope, context, namespace }),
    directory = directory,
    path = backend.path and backend.path(directory) or nil,
    legacy_path = settings.path or vim.fs.joinpath(legacy_directory, namespace .. '.json'),
    version = version, max_bytes = max_bytes,
    accept_unversioned = settings.accept_unversioned == true,
    on_error = settings.on_error,
  }, Store)
end

function M.memory(namespace, options)
  return M.open(namespace, vim.tbl_extend('force', options or {}, {
    storage = 'memory', backend = 'memory',
  }))
end

function M.persistent(namespace, options)
  return M.open(namespace, vim.tbl_extend('force', options or {}, { storage = 'persistent' }))
end

return M
