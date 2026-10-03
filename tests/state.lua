local state = require('config.state')
local sqlite = require('config.storage.sqlite')
local directory = vim.fn.tempname()
local errors = {}
local first = state.open('first', {
  directory = directory .. '/nested/state',
  on_error = function(failure) errors[#errors + 1] = failure end,
})
local function idle(store)
  local completed, saved, failure = false, false, nil
  store:when_idle(function(succeeded, save_error)
    completed, saved, failure = true, succeeded, save_error
  end)
  assert(vim.wait(2000, function() return completed end), 'SQLite completion callback missing')
  return saved, failure
end
assert(first:read_sync() == nil)
local session = state.open('selection', { scope = 'session', session_id = 'one', directory = directory })
assert(session:write({ selected = { 'alpha' } }))
local session_value = assert(session:read_sync())
session_value.selected[1] = 'changed'
assert(session:read_sync().selected[1] == 'alpha', 'Session reads exposed mutable storage')
assert(state.open('selection', { scope = 'session', session_id = 'two' }):read_sync() == nil)
assert(session.path == nil and not vim.uv.fs_stat(directory .. '/state.db'),
  'Session state wrote to disk')
local explicit_memory = state.open('explicit-memory', { backend = 'memory', directory = directory })
assert(explicit_memory.path == nil and explicit_memory:write({ transient = true })
    and explicit_memory:read_sync().transient, 'Explicit memory backend was not process-local')

assert(first:write({ ratio = 0.1 }))
for index = 1, 30 do assert(first:write({ ratio = index / 100 })) end
assert(idle(first), 'Coalesced writes did not finish')
local saved = assert(state.open('first', { directory = directory .. '/nested/state' }):read_sync())
assert(saved.version == 1 and saved.ratio == 0.3, 'An earlier save overwrote the last value')
assert(bit.band(vim.uv.fs_stat(first.path).mode, 511) == 384, 'Database permissions are not private')
local database = assert(sqlite.open(first.path))
assert(database:query('PRAGMA integrity_check') == 'ok', 'SQLite database failed integrity check')
database:close()

local second = state.open('second', { directory = directory .. '/nested/state' })
assert(second.path == first.path, 'Namespaces created redundant databases')
assert(second:write_sync({ name = "quote ' and Unicode 中文" }))
assert(first:read_sync().ratio == 0.3, 'Another namespace overwrote a preference')
assert(second:read_sync().name == "quote ' and Unicode 中文", 'SQLite text escaping damaged a value')
local project_one = state.open('layout', {
  scope = 'project', project_root = '/projects/one', directory = directory,
})
local project_two = state.open('layout', {
  scope = 'project', project_root = '/projects/two', directory = directory,
})
assert(project_one:write_sync({ ratio = 0.2 }))
assert(project_two:read_sync() == nil, 'Project preferences leaked across roots')
assert(state.open('layout', {
  scope = 'project', project_root = '/projects/one/', directory = directory,
}):read_sync().ratio == 0.2, 'Equivalent project roots used different storage')
assert(project_one.path == project_two.path, 'Project scopes created separate databases')
assert(not pcall(state.open, '../escape'), 'Namespace allowed directory traversal')
assert(not pcall(state.open, 'layout', { scope = 'project', project_root = 'relative' }))

local callback_received = false
first:read(function(document, failure)
  assert(not vim.in_fast_event(), 'Read completion ran outside the main loop')
  assert(not failure and document.ratio == 0.3)
  callback_received = true
end)
assert(vim.wait(1000, function() return callback_received end))
local cancelled_callback = false
local cancel = first:read(function() cancelled_callback = true end)
cancel()
vim.wait(50)
assert(not cancelled_callback, 'Cancelled state read delivered a stale result')

local legacy = state.open('legacy', { directory = directory, accept_unversioned = true, max_bytes = 128 })
vim.fn.writefile({ '{"name":"old"}' }, legacy.legacy_path)
assert(legacy:read_sync().name == 'old', 'Legacy preference was not imported')
assert(not vim.uv.fs_stat(legacy.legacy_path), 'Committed legacy preference was not removed')
assert(legacy:read_sync().version == 1, 'Migration did not version the document')
assert(legacy:write_sync({ name = 'new' }))
-- An interrupted cleanup must not import stale data over a newer SQLite record.
vim.fn.writefile({ '{"name":"stale"}' }, legacy.legacy_path)
assert(legacy:read_sync().name == 'new', 'Repeated migration overwrote newer state')
assert(not vim.uv.fs_stat(legacy.legacy_path))

for index, source in ipairs({ '{broken', '[]', '{"version":999}', string.rep('x', 129) }) do
  local invalid = state.open('invalid-' .. index, { directory = directory, max_bytes = 128 })
  vim.fn.writefile({ source }, invalid.legacy_path)
  local document, failure = invalid:read_sync()
  assert(document == nil and failure, 'Invalid legacy state did not return a recoverable error')
  assert(vim.uv.fs_stat(invalid.legacy_path), 'Failed migration deleted its source')
end
assert(not legacy:write({ value = string.rep('x', 129) }), 'Oversized state was accepted')
assert(not legacy:write({ invalid = function() end }), 'Non-JSON state was accepted')

-- Another connection may hold a transaction. Never sleep the editor waiting for it.
local locked = assert(sqlite.open(first.path))
assert(locked:exec('BEGIN EXCLUSIVE'))
assert(first:write({ ratio = 0.8 }))
local heartbeat = false
vim.schedule(function() heartbeat = true end)
local completed, failure = idle(first)
assert(heartbeat and not completed and failure and #errors == 1, 'Busy write did not fail asynchronously')
assert(locked:exec('ROLLBACK'))
locked:close()
assert(first:read_sync().ratio == 0.3, 'Failed transaction damaged committed state')
assert(first:write_sync({ ratio = 0.4 }), 'Failed save prevented retry')
assert(first:read_sync().ratio == 0.4)

local backend_documents = {}
local replacement_backend = { persistent = true }
function replacement_backend.read_sync(store)
  return backend_documents[store.key]
end
function replacement_backend.write_sync(store, source)
  backend_documents[store.key] = source
  return true
end
function replacement_backend.read(store, callback)
  local cancelled = false
  vim.schedule(function()
    if not cancelled then callback(backend_documents[store.key]) end
  end)
  return function() cancelled = true end
end
function replacement_backend.write(store, source)
  backend_documents[store.key] = source
  return true
end
function replacement_backend.when_idle(_, callback)
  vim.schedule(function() callback(true) end)
end
state.register_backend('sqlite', replacement_backend)
local replacement = state.open('replacement', { directory = directory })
assert(replacement:write_sync({ source = 'replaceable' }))
assert(replacement:read_sync().source == 'replaceable', 'Registered storage backend did not persist data')
local replacement_callback
replacement:read(function(document, failure)
  assert(not failure and document.source == 'replaceable')
  replacement_callback = true
end)
assert(vim.wait(1000, function() return replacement_callback end),
  'Registered storage backend did not deliver asynchronous reads')
state.register_backend('sqlite', nil)

local imported = state.open('async-import', { directory = directory, accept_unversioned = true })
vim.fn.writefile({ '{"name":"async"}' }, imported.legacy_path)
local imported_document
imported:read(function(document, read_error)
  assert(not read_error, read_error)
  imported_document = document
end)
assert(vim.wait(2000, function() return imported_document ~= nil end))
assert(imported_document.name == 'async' and not vim.uv.fs_stat(imported.legacy_path),
  'Async import did not commit before removing the legacy file')
vim.fn.delete(directory, 'rf')
