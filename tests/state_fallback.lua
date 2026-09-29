-- Separate process: nvim --headless -u NONE -i NONE -l tests/state_fallback.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.preload['config.storage.sqlite'] = function() error('simulated missing SQLite library') end
local messages = {}
rawset(vim, 'notify', function(message) messages[#messages + 1] = message end)
local state = require('config.state')
assert(not state.persistent_available())
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.fn.writefile({ 'existing database must remain untouched' }, directory .. '/state.db')
vim.fn.writefile({ '{"version":1,"name":"saved"}' }, directory .. '/theme.json')
local store = state.open('theme', { directory = directory })
assert(store:read_sync() == nil, 'Memory fallback tried to read disk state')
assert(store:write({ name = 'temporary', nested = { value = 1 } }))
local document = assert(store:read_sync())
document.nested.value = 2
assert(store:read_sync().nested.value == 1, 'Memory fallback exposed its mutable document')
assert(state.open('theme', { directory = directory }):read_sync().name == 'temporary')
assert(state.open('theme', { directory = directory .. '/other' }):read_sync() == nil,
  'Fallback directories shared a namespace')
local first = state.open('layout', { directory = directory, scope = 'project', project_root = '/one' })
local second = state.open('layout', { directory = directory, scope = 'project', project_root = '/two' })
assert(first:write_sync({ width = 30 }))
assert(second:read_sync() == nil, 'Fallback projects shared a namespace')
local completed = false
store:read(function(selection, failure)
  assert(not failure and selection.name == 'temporary' and not vim.in_fast_event())
  completed = true
end)
assert(vim.wait(1000, function() return completed and #messages == 1 end))
state.setup()
assert(#messages == 1, 'Missing SQLite emitted repeated warnings')
assert(vim.fn.readfile(directory .. '/state.db')[1] == 'existing database must remain untouched')
assert(vim.fn.readfile(directory .. '/theme.json')[1] == '{"version":1,"name":"saved"}')
assert(vim.fn.isdirectory(directory .. '/other') == 0, 'Fallback created a storage directory')
vim.fn.delete(directory, 'rf')
print('Memory-only fallback, scope isolation, and saved-file preservation passed')
