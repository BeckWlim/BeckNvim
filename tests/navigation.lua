-- Shared launch context and native window-local history across entry points.
local navigation = require('config.navigation')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local source, target = directory .. '/source.txt', directory .. '/target.txt'
vim.fn.writefile({ 'first', 'second', 'third', 'fourth', 'fifth' }, source)
vim.fn.writefile({ 'target', 'second target' }, target)
local original_tab = vim.api.nvim_get_current_tabpage()
local original_hidden = vim.o.hidden
vim.o.hidden = true
vim.api.nvim_cmd({ cmd = 'tabnew', args = { source } }, {})
local focused = vim.api.nvim_get_current_win()
vim.api.nvim_cmd({ cmd = 'vsplit', args = { target } }, {})
local unrelated = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(unrelated, 25)
vim.api.nvim_set_current_win(focused)
vim.cmd('clearjumps')
vim.api.nvim_win_set_cursor(focused, { 2, 2 })
local context = navigation.capture()
local unrelated_buffer = vim.api.nvim_win_get_buf(unrelated)
local unrelated_cursor = vim.api.nvim_win_get_cursor(unrelated)
local layout = vim.fn.winlayout()
local width = vim.api.nvim_win_get_width(focused)
navigation.open(target, { context = context, line = 2, column = 3, push_cursor = true })
assert(navigation.back() and vim.api.nvim_buf_get_name(0) == source
  and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), 'Back lost the native opening origin')
assert(navigation.forward() and vim.api.nvim_buf_get_name(0) == target
  and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), 'Forward lost the file destination')
assert(vim.api.nvim_get_current_win() == focused and vim.deep_equal(vim.fn.winlayout(), layout)
  and vim.api.nvim_win_get_width(focused) == width
  and vim.api.nvim_win_get_buf(unrelated) == unrelated_buffer
  and vim.deep_equal(vim.api.nvim_win_get_cursor(unrelated), unrelated_cursor),
  'History reused or changed another pane displaying the same file')
-- An asynchronously selected search must not commit into a changed launch view.
local stale = navigation.capture()
vim.api.nvim_cmd({ cmd = 'edit', args = { source } }, {})
assert(navigation.open(target, { context = stale }) == nil and vim.api.nvim_buf_get_name(0) == source,
  'A stale launch context replaced the new file view')
vim.cmd('clearjumps')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! /third\r')
vim.cmd('normal! /fifth\r')
assert(navigation.jump('back', { count = 2 }) and vim.fn.line('.') == 1,
  'Counted history did not include native slash searches')
assert(navigation.jump('forward', { count = 2 }) and vim.fn.line('.') == 5,
  'Counted forward navigation lost native search ordering')
local own_jumps = vim.fn.getjumplist()
navigation.jump('back', { window = unrelated })
assert(vim.api.nvim_get_current_win() == focused and vim.deep_equal(vim.fn.getjumplist(), own_jumps),
  'Navigation in another pane changed the focused pane history')
vim.cmd('tabclose!')
vim.api.nvim_set_current_tabpage(original_tab)
vim.o.hidden = original_hidden
for _, path in ipairs({ source, target }) do
  local buffer = vim.fn.bufnr(path)
  if buffer ~= -1 then vim.api.nvim_buf_delete(buffer, { force = true }) end
end
vim.fn.delete(directory, 'rf')
print('Shared navigation context, stale selection, pane isolation, and native counted search history pass')
