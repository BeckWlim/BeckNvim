local operations = require('config.navigation')
local original_select = operations.select_window
local original_dirty_select = vim.ui.select
local original_confirm = vim.fn.confirm
local original_notify = vim.notify
local original_hidden = vim.o.hidden
local original_tab = vim.api.nvim_get_current_tabpage()
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local target = root .. '/a space | % #.txt'
vim.fn.writefile({ 'first', 'second' }, target)
vim.fn.writefile({ 'other' }, root .. '/other.txt')
local choices, on_choice
rawset(operations, 'select_window', function(items, callback) choices = items; on_choice = callback end)
vim.o.hidden = true
vim.cmd('tabnew')
local first = vim.api.nvim_get_current_win()
operations.open(target)
vim.cmd('vnew')
local second = vim.api.nvim_get_current_win()
operations.open(target)
assert(vim.api.nvim_get_current_win() == second and vim.api.nvim_win_get_buf(first) == vim.api.nvim_win_get_buf(second),
  'Editor-origin :edit policy jumped to another pane showing the file')
vim.api.nvim_win_set_width(first, math.max(4, math.floor(vim.o.columns / 3)))
local focused_widths = { [first] = vim.api.nvim_win_get_width(first), [second] = vim.api.nvim_win_get_width(second) }
local unrelated_buffer = vim.api.nvim_win_get_buf(first)
operations.open(root .. '/other.txt', { on_open = function()
  vim.api.nvim_win_set_width(first, math.max(4, math.floor(vim.o.columns / 2)))
end })
assert(vim.api.nvim_get_current_win() == second and vim.api.nvim_win_get_buf(first) == unrelated_buffer,
  'A file callback replaced an unrelated editor pane')
for window, width in pairs(focused_widths) do
  assert(vim.api.nvim_win_get_width(window) == width, 'A file callback changed native split proportions')
end
operations.open(target)
vim.cmd('vnew')
local panel = vim.api.nvim_get_current_win()
local panel_buffer = vim.api.nvim_get_current_buf()
vim.bo.buftype, vim.bo.filetype = 'nofile', 'NvimTree'
require('config.ui.window_state').register('NvimTree', function() return { number = true, relativenumber = true } end)
local layout = vim.fn.winlayout()
local before_first, before_second = vim.api.nvim_win_get_buf(first), vim.api.nvim_win_get_buf(second)
operations.open(root .. '/other.txt')
assert(#choices == 2 and vim.deep_equal(vim.fn.winlayout(), layout), 'Panel did not ask before changing panes')
on_choice(nil)
assert(vim.api.nvim_get_current_win() == panel and vim.api.nvim_win_get_buf(first) == before_first
  and vim.api.nvim_win_get_buf(second) == before_second, 'Cancelling destination changed editor state')
operations.open(root .. '/other.txt', { keep_focus = true })
on_choice(second)
assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(second)) == root .. '/other.txt'
  and vim.api.nvim_get_current_win() == panel, 'Choice did not target the requested pane and restore panel focus')
assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Choice changed split structure')
operations.open(target)
local stale_choice = on_choice
operations.open(root .. '/other.txt')
stale_choice(first)
assert(vim.api.nvim_get_current_win() == panel, 'Superseded choice moved focus')
on_choice(nil)
operations.open(target)
vim.api.nvim_win_call(second, function() vim.cmd('enew') end)
on_choice(second)
assert(vim.api.nvim_get_current_win() == panel, 'Stale target buffer was replaced')
operations.open(target)
vim.api.nvim_win_set_buf(panel, vim.api.nvim_create_buf(false, true))
on_choice(first)
assert(vim.api.nvim_get_current_win() == panel, 'A changed source committed a pending open')
vim.api.nvim_win_set_buf(panel, panel_buffer)
vim.wo[first].winfixbuf = true
operations.open(target)
assert(vim.api.nvim_get_current_win() == second, 'Protected pane was offered as a destination')
vim.wo[first].winfixbuf = false
vim.api.nvim_set_current_win(panel)
vim.api.nvim_win_close(second, true)
vim.api.nvim_win_close(first, true)
operations.open(target, { line = 2, column = 3 })
local created = vim.api.nvim_get_current_win()
assert(created ~= panel and #vim.api.nvim_tabpage_list_wins(0) == 2, 'Tree-only open did not create one editor')
assert(vim.wo.number and vim.wo.relativenumber, 'Created editor inherited panel presentation')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), 'Location cursor was lost')
local selected_buffer = vim.api.nvim_get_current_buf()
operations.open('', { buffer = selected_buffer, command = 'vsplit' })
local buffer_split = vim.api.nvim_get_current_win()
assert(buffer_split ~= created and vim.api.nvim_get_current_buf() == selected_buffer,
  'Buffer split did not use the selected loaded buffer')
operations.close()
assert(vim.api.nvim_buf_is_valid(selected_buffer), 'Closing the buffer split wiped the selected buffer')
vim.api.nvim_set_current_win(created)
local previous_tab = vim.api.nvim_get_current_tabpage()
operations.open('', { buffer = selected_buffer, command = 'tabedit' })
assert(vim.api.nvim_get_current_tabpage() ~= previous_tab and vim.api.nvim_get_current_buf() == selected_buffer,
  'Buffer tab-open did not create a tab for the selected buffer')
vim.cmd('tabclose')
vim.api.nvim_set_current_win(created)
vim.api.nvim_win_call(panel, function()
  local dashboard_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(panel, dashboard_buffer)
  vim.bo.buftype, vim.bo.filetype = 'nofile', 'dashboard'
  operations.open(root .. '/other.txt')
  assert(vim.api.nvim_get_current_win() == panel, 'Dashboard did not behave as an editor pane')
end)
vim.api.nvim_set_current_win(created)
vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'unsaved edit' })
vim.o.hidden = false
local failure
rawset(vim, 'notify', function(message) failure = message end)
rawset(vim.ui, 'select', function() error('Replacement opened a dirty-file decision flow') end)
local answer, question = 2, nil
rawset(vim.fn, 'confirm', function(message, choices_text, default)
  question = message
  assert(choices_text == '&Yes\n&No' and default == 2, 'Write boundary is not a default-No y/n question')
  return answer
end)
local covered_buffer = vim.api.nvim_get_current_buf()
local dirty_layout = vim.fn.winlayout()
local rejected = operations.open(root .. '/other.txt')
assert(rejected and rejected.cancelled and type(question) == 'string' and question:find('Write this file now?', 1, true)
  and vim.api.nvim_get_current_buf() == covered_buffer and vim.bo.modified
  and vim.deep_equal(vim.fn.winlayout(), dirty_layout), 'Unwritten destination was covered or opened a decision UI')
local forced = vim.api.nvim_parse_cmd('edit! ' .. vim.fn.fnameescape(root .. '/other.txt'), {})
assert(operations.open(root .. '/other.txt', { native_command = forced }).cancelled
  and vim.api.nvim_get_current_buf() == covered_buffer and vim.bo.modified,
  'A forced file open bypassed the write boundary')
vim.cmd('write')
operations.open('', { buffer = 987654321 })
assert(failure and failure:find('no longer available', 1, true)
  and vim.api.nvim_get_current_buf() == covered_buffer, 'Failed open removed the previous file')
operations.open(root .. '/other.txt')
assert(vim.fn.readfile(target)[1] == 'unsaved edit' and vim.api.nvim_buf_is_valid(covered_buffer)
  and not vim.bo[covered_buffer].buflisted, 'Writing did not enable replacement with retained history')
-- An unwritten file is protected even when another pane displays it.
local shared_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(shared_buffer, 0, 1, false, { 'shared unsaved edit' })
assert(operations.open(target).cancelled and vim.api.nvim_get_current_buf() == shared_buffer
  and vim.api.nvim_win_get_buf(panel) == shared_buffer and vim.bo[shared_buffer].modified,
  'A shared unwritten view bypassed the write boundary')
answer = 1
operations.open(target)
assert(vim.api.nvim_buf_is_valid(shared_buffer) and vim.api.nvim_win_get_buf(panel) == shared_buffer,
  'Replacing a written shared view removed another pane')
covered_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(covered_buffer, 0, 1, false, { 'write before replacing' })
vim.bo.readonly = true
assert(operations.open(root .. '/fresh.txt').cancelled and vim.api.nvim_get_current_buf() == covered_buffer,
  'An unsuccessful write enabled replacement')
vim.bo.readonly = false
operations.open(root .. '/fresh.txt')
assert(vim.api.nvim_buf_get_name(0) == root .. '/fresh.txt' and vim.api.nvim_buf_is_valid(covered_buffer)
  and not vim.bo[covered_buffer].buflisted and vim.fn.readfile(target)[1] == 'write before replacing',
  'Written file did not replace successfully or lost its history buffer')
vim.ui.select = original_dirty_select
rawset(vim.fn, 'confirm', original_confirm)
vim.o.hidden = true
local retained_buffer = vim.api.nvim_get_current_buf()
operations.close()
assert(not vim.api.nvim_win_is_valid(created) and vim.api.nvim_buf_is_valid(retained_buffer), 'Pane close deleted its file buffer')
local owned_buffer = vim.api.nvim_get_current_buf()
local owner_closed = 0
operations.register_close(owned_buffer, function() owner_closed = owner_closed + 1 end)
operations.close()
assert(owner_closed == 1 and vim.api.nvim_win_is_valid(panel), 'Close adapter did not retain lifecycle ownership')
vim.cmd('tabclose!')
vim.api.nvim_set_current_tabpage(original_tab)
rawset(operations, 'select_window', original_select)
vim.o.hidden = original_hidden
rawset(vim, 'notify', original_notify)
vim.fn.delete(root, 'rf')
