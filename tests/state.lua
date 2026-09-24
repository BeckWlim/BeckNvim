local state = require('config.state')
local directory = vim.fn.tempname()
local errors = {}
local first = state.open('first', {
  directory = directory .. '/nested/state',
  on_error = function(failure) errors[#errors + 1] = failure end,
})
assert(first:read_sync() == nil, 'Missing state should not create a file')
local session = state.open('selection', { scope = 'session', session_id = 'one', directory = directory })
assert(session:write({ selected = { 'alpha' } }))
local session_value = assert(session:read_sync())
session_value.selected[1] = 'changed'
assert(session:read_sync().selected[1] == 'alpha', 'Session reads exposed mutable storage')
assert(state.open('selection', { scope = 'session', session_id = 'two' }):read_sync() == nil)
assert(not vim.uv.fs_stat(session.path), 'Session scope wrote to disk')

assert(first:write({ ratio = 0.1 }))
for index = 1, 30 do assert(first:write({ ratio = index / 100 })) end
assert(first:flush(2000), 'Coalesced writes did not finish')
local saved = assert(state.open('first', { directory = directory .. '/nested/state' }):read_sync())
assert(saved.version == 1 and saved.ratio == 0.3, 'An earlier save overwrote the last value')
assert(bit.band(vim.uv.fs_stat(first.path).mode, 511) == 384, 'Preference file permissions are not private')

local second = state.open('second', { directory = directory .. '/nested/state' })
assert(second:write_sync({ name = 'independent' }))
assert(first:read_sync().ratio == 0.3, 'Another namespace overwrote a preference')
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
vim.wait(30)
assert(not cancelled_callback, 'Cancelled state read delivered a stale result')

local legacy = state.open('legacy', { directory = directory, accept_unversioned = true, max_bytes = 128 })
vim.fn.writefile({ '{"name":"old"}' }, legacy.path)
assert(legacy:read_sync().name == 'old', 'Unversioned legacy preference was not read')
assert(legacy:write_sync({ name = 'new' }))
assert(legacy:read_sync().version == 1, 'New save did not add a version')
for _, source in ipairs({ '{broken', '[]', '{"version":999}', string.rep('x', 129) }) do
  vim.fn.writefile({ source }, legacy.path)
  local document, failure = legacy:read_sync()
  assert(document == nil and failure, 'Invalid state did not return a recoverable error')
end
assert(not legacy:write({ value = string.rep('x', 129) }), 'Oversized state was accepted')
assert(not legacy:write({ invalid = function() end }), 'Non-JSON state was accepted')

-- Failed writes preserve the old file and leave no temporary files behind.
local original_rename = vim.uv.fs_rename
vim.uv.fs_rename = function(source, target, callback)
  if target == first.path then
    if callback then vim.schedule(function() callback('injected rename failure') end); return end
    return nil, 'injected rename failure'
  end
  return original_rename(source, target, callback)
end
assert(first:write({ ratio = 0.8 }))
local flushed, failure = first:flush(1000)
vim.uv.fs_rename = original_rename
assert(not flushed and failure, 'Write failure was hidden')
assert(first:read_sync().ratio == 0.3, 'Failed atomic write damaged the old preference')
assert(#vim.fn.glob(first.path .. '.*.tmp', false, true) == 0, 'Failed write leaked a temporary file')
assert(vim.wait(1000, function() return #errors == 1 end), 'Async error was not reported')
assert(first:write_sync({ ratio = 0.4 }), 'A failed save prevented retry')
assert(first:read_sync().ratio == 0.4)
vim.fn.delete(directory, 'rf')
