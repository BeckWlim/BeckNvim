-- Surface settings must follow each window's buffer, including native opens.
local window_state = require('config.ui.window_state')
local source_tab = vim.api.nvim_get_current_tabpage()
vim.cmd('tabnew')
local source_window = vim.api.nvim_get_current_win()
local surface = vim.api.nvim_create_buf(false, true)
local editor_options = {
  number = true, relativenumber = true, signcolumn = 'yes', cursorline = true,
  colorcolumn = '99', wrap = true,
}
window_state.register('window-context-surface', function() return editor_options end, {
  number = false, relativenumber = false, signcolumn = 'no', cursorline = false,
  colorcolumn = '', wrap = false,
})
vim.api.nvim_win_set_buf(source_window, surface)
vim.bo[surface].buftype = 'nofile'
local defaults_before = window_state.defaults()
vim.bo[surface].filetype = 'window-context-surface'
window_state.apply(source_window, editor_options)
assert(vim.deep_equal(window_state.defaults(), defaults_before),
  'Surface presentation changed the defaults inherited by later windows')

local function assert_editor(window)
  for name, value in pairs(editor_options) do
    assert(vim.wo[window][name] == value, 'Surface leaked ' .. name .. ' into the editor')
  end
end
local function assert_surface(window)
  assert(not vim.wo[window].number and not vim.wo[window].relativenumber,
    'A preserved surface displayed editor line numbers')
  assert(vim.wo[window].signcolumn == 'no' and vim.wo[window].colorcolumn == '',
    'A preserved surface displayed editor gutters')
end

for _, command in ipairs({ 'split', 'vsplit', 'new', 'vnew', 'tab split' }) do
  vim.api.nvim_set_current_win(source_window)
  vim.cmd(command)
  local opened_window = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(opened_window) == surface then assert_surface(opened_window) end
  vim.cmd('enew')
  assert_editor(opened_window)
  assert_surface(source_window)
  -- Subsequent editor changes must survive buffer replacement and focus changes.
  vim.api.nvim_set_option_value('number', false, { win = opened_window, scope = 'local' })
  vim.cmd('enew')
  vim.api.nvim_set_current_win(source_window)
  vim.api.nvim_set_current_win(opened_window)
  assert(not vim.wo[opened_window].number, 'Reconciliation reset an editor-local preference')
  vim.api.nvim_win_close(opened_window, true)
end

-- One buffer can be shown with a different underlying intent in each pane.
vim.api.nvim_set_current_win(source_window)
vim.cmd('split')
local second_window = vim.api.nvim_get_current_win()
window_state.apply(second_window, vim.tbl_extend('force', editor_options, { relativenumber = false }))
vim.cmd('split')
local third_window = vim.api.nvim_get_current_win()
vim.cmd('enew')
assert(vim.wo.number and not vim.wo.relativenumber,
  'A nested split inherited intent from another view of the surface buffer')
vim.api.nvim_win_close(third_window, true)
vim.api.nvim_set_current_win(second_window)
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
assert(vim.wo[second_window].number and not vim.wo[second_window].relativenumber,
  'A split lost its own editor intent')
assert_surface(source_window)
vim.api.nvim_win_close(second_window, true)

local path = vim.fn.tempname() .. '.txt'
vim.fn.writefile({ 'file opened directly from a surface' }, path)
vim.api.nvim_set_current_win(source_window)
vim.cmd.split(vim.fn.fnameescape(path))
local file_window = vim.api.nvim_get_current_win()
assert_editor(file_window)
assert_surface(source_window)
local file_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_win_close(file_window, true)
vim.api.nvim_set_current_win(source_window)
vim.cmd.edit(vim.fn.fnameescape(path))
assert_editor(source_window)

local scratch_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(surface)
local scratch_window = vim.api.nvim_open_win(scratch_buffer, false, { split = 'below', win = source_window })
assert_editor(scratch_window)
assert_surface(source_window)
vim.api.nvim_win_close(scratch_window, true)
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
vim.api.nvim_set_current_buf(surface)
assert_surface(source_window)
vim.cmd('enew')
assert_editor(source_window)

-- A native split from a registered panel carries its resolved editor settings.
window_state.register('window-context-panel', function()
  return { number = true, relativenumber = false }
end)
local panel = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(panel)
vim.bo[panel].filetype = 'window-context-panel'
vim.api.nvim_set_option_value('number', false, { win = source_window, scope = 'local' })
vim.cmd('new')
local panel_split = vim.api.nvim_get_current_win()
assert(vim.wo.number and not vim.wo.relativenumber, 'Panel split inherited its hidden gutter')
assert(not vim.wo[source_window].number, 'Panel split changed the source presentation')
vim.api.nvim_win_close(panel_split, true)

vim.cmd('tabclose!')
for _, buffer in ipairs({ surface, file_buffer, panel, scratch_buffer }) do
  if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
end
vim.fn.delete(path)
assert(vim.api.nvim_get_current_tabpage() == source_tab)
assert(vim.deep_equal(window_state.defaults(), defaults_before),
  'Context transitions changed global editor defaults')
print('Window surface context transitions passed')
