local actions = require('config.keybindings')
local calls = {}
local adapter = {
  before_action = function(action) calls[#calls + 1] = 'before:' .. action end,
  expand = function() calls[#calls + 1] = 'expand' end,
  select = function() calls[#calls + 1] = 'select' end,
}
assert(not actions.dispatch(adapter, 'unsupported'))
assert(#calls == 0)
assert(actions.dispatch(adapter, 'expand'))
assert(vim.deep_equal(calls, { 'before:expand', 'expand' }))
local maps = actions.mappings('tree', adapter)
assert(#maps == 3 and maps[1][2] == '<cr>' and maps[2][2] == 'o' and maps[3][2] == 'zo')
maps[1][3]()
assert(calls[3] == 'before:select' and calls[4] == 'select')
local directions = actions.mappings('directions', {
  left = '<C-w>h', down = '<C-w>j', up = '<C-w>k', right = '<C-w>l',
}, { prefix = '<Space>w', description = 'Window ' })
assert(#directions == 4)
for index, key in ipairs({ 'h', 'j', 'k', 'l' }) do
  assert(directions[index][2] == '<Space>w' .. key)
  assert(directions[index][3] == '<C-w>' .. key)
end
local received
local cursor = actions.mappings('directions', {
  down = function(value) received = value end,
}, { key_format = '<C-%s>', mode = 'i' })
assert(#cursor == 1 and cursor[1][1] == 'i' and cursor[1][2] == '<C-j>')
cursor[1][3](42)
assert(received == 42, 'Semantic dispatch discarded plugin arguments')
