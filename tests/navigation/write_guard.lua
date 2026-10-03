-- Write policy is an optional boundary extension, shared by opens and history.
local navigation = require('config.navigation')
local guard = require('config.navigation.write_guard')
guard.setup()
local original_tab = vim.api.nvim_get_current_tabpage()
local original_hidden, original_confirm, original_notify = vim.o.hidden, vim.fn.confirm, vim.notify
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local source, target = directory .. '/source.txt', directory .. '/target.txt'
vim.fn.writefile({ 'saved source', 'second', 'third' }, source)
vim.fn.writefile({ 'saved target' }, target)
vim.o.hidden = true
vim.api.nvim_cmd({ cmd = 'tabnew', args = { source } }, {})
local window, buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local answer, questions, notification = 2, 0, nil
rawset(vim, 'notify', function(message) notification = message end)
rawset(vim.fn, 'confirm', function(message, choices, default)
  questions = questions + 1
  assert(message:find('Write this file now?', 1, true) and choices == '&Yes\n&No' and default == 2,
    'Write policy did not offer the default-No y/n question')
  return answer
end)
vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'unwritten source' })
local layout, history = vim.fn.winlayout(), vim.fn.getjumplist()
assert(navigation.open(target).cancelled and questions == 1
  and vim.api.nvim_get_current_buf() == buffer and vim.bo.modified
  and vim.fn.readfile(source)[1] == 'saved source'
  and vim.deep_equal(vim.fn.winlayout(), layout) and vim.deep_equal(vim.fn.getjumplist(), history),
  'No changed the file, pane, disk contents, or native history')
navigation.open(source, { line = 2, push_cursor = true })
assert(questions == 1 and vim.fn.line('.') == 2 and vim.bo.modified,
  'A same-file cursor jump asked to write')
answer = 1
navigation.open(target, { push_cursor = true })
assert(vim.api.nvim_buf_get_name(0) == target and vim.fn.readfile(source)[1] == 'unwritten source',
  'Yes failed to write the source before replacement')
local target_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(target_buffer, 0, 1, false, { 'unwritten target' })
answer = 2
history = vim.fn.getjumplist()
assert(not navigation.back() and vim.api.nvim_get_current_buf() == target_buffer and vim.bo.modified
  and vim.deep_equal(vim.fn.getjumplist(), history), 'No advanced cross-file history or replaced the dirty view')
answer = 1
assert(navigation.back() and vim.api.nvim_get_current_buf() == buffer
  and vim.fn.readfile(target)[1] == 'unwritten target', 'Yes did not write before the native history jump')
vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'readonly unsaved source' })
vim.bo.readonly = true
assert(navigation.open(target).cancelled and vim.api.nvim_get_current_buf() == buffer
  and vim.bo.modified and notification, 'An unsuccessful write replaced the pane')
vim.bo.readonly = false
rawset(vim.fn, 'confirm', function()
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'newer source contents' })
  return 1
end)
assert(navigation.open(target).cancelled and vim.api.nvim_get_current_buf() == buffer
  and vim.bo.modified and vim.fn.readfile(source)[1] == 'unwritten source',
  'A stale Yes wrote newer contents or changed the view')
-- The core can run with this policy detached; it contains no write-question UI.
local detach = guard.setup()
detach()
local seen
local remove = navigation.register_boundary('test_veto', function(transition)
  seen = transition
  return false
end)
assert(navigation.open(target).cancelled and seen.action == 'open' and seen.window == window
  and seen.buffer == buffer, 'The manager bypassed an independently registered boundary')
remove()
navigation.open(target)
assert(vim.api.nvim_buf_get_name(0) == target and vim.bo[buffer].modified,
  'The core retained write policy after the extension was detached')
guard.setup()
rawset(vim.fn, 'confirm', original_confirm)
rawset(vim, 'notify', original_notify)
vim.cmd('tabclose!')
vim.api.nvim_set_current_tabpage(original_tab)
vim.o.hidden = original_hidden
for _, file in ipairs({ source, target }) do
  local remaining = vim.fn.bufnr(file)
  if remaining ~= -1 then vim.api.nvim_buf_delete(remaining, { force = true }) end
end
vim.fn.delete(directory, 'rf')
print('Optional write boundary: No, Yes, failed writes, stale choices, and native history pass')
