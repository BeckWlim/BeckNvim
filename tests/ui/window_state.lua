-- Focused tests for config.ui.window_state.
local window_state = require('config.ui.window_state')
local test_window = vim.api.nvim_get_current_win()
local test_buffer = vim.api.nvim_create_buf(false, true)
local original_buffer = vim.api.nvim_win_get_buf(test_window)
local original_number = vim.wo[test_window].number
local original_relativenumber = vim.wo[test_window].relativenumber

vim.api.nvim_win_set_buf(test_window, test_buffer)
vim.bo[test_buffer].filetype = 'window-state-test'
vim.wo[test_window].number = false
vim.wo[test_window].relativenumber = false
window_state.register('window-state-test', function(winid)
  assert(winid == test_window, 'window-state gate resolved the wrong window')
  return {
    number = true,
    relativenumber = true,
  }
end)

assert(
  vim.deep_equal(
    window_state.resolve(test_window, { 'number', 'relativenumber' }),
    { number = true, relativenumber = true }
  ),
  'registered window state did not override the surface-local presentation'
)

vim.bo[test_buffer].filetype = ''
assert(
  vim.deep_equal(
    window_state.resolve(test_window, { 'number', 'relativenumber' }),
    { number = false, relativenumber = false }
  ),
  'unregistered window state did not fall back to the current window options'
)

vim.api.nvim_win_set_buf(test_window, original_buffer)
vim.wo[test_window].number = original_number
vim.wo[test_window].relativenumber = original_relativenumber
vim.api.nvim_buf_delete(test_buffer, { force = true })

local original_equalalways = vim.o.equalalways
local state_directory = vim.fn.tempname()
window_state.setup({ state_directory = state_directory })
assert(not vim.o.equalalways, 'New splits still equalize unrelated windows')
vim.cmd.vsplit()
local panel_window = vim.api.nvim_get_current_win()
local panel_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(panel_window, panel_buffer)
vim.bo[panel_buffer].filetype = 'window-state-panel'
assert(window_state.panel_size('window-state-panel', 'width', 30) == 30)
window_state.track_panel(panel_window)
local panel_width = math.max(1, math.floor(vim.o.columns / 5))
vim.api.nvim_win_set_width(panel_window, panel_width)
vim.api.nvim_exec_autocmds('WinResized', {})
assert(window_state.panel_size('window-state-panel', 'width', 30) == panel_width)
vim.api.nvim_win_close(panel_window, true)
vim.wait(20)
assert(window_state.panel_size('window-state-panel', 'width', 30) == panel_width,
  'Closing a registered panel discarded its size')
vim.cmd('tabnew')
assert(window_state.panel_size('window-state-panel', 'width', 30) == panel_width,
  'A new tab did not inherit the last panel preference')
vim.cmd('tabclose')
vim.wait(20)
vim.api.nvim_del_augroup_by_name('workspace_window_proportions')
vim.api.nvim_buf_delete(panel_buffer, { force = true })
vim.o.equalalways = original_equalalways
local preference = window_state.prepare_panel('window-state-panel', 'width')
assert(preference.store:flush(1000))
window_state.setup({ state_directory = state_directory })
assert(vim.wait(1000, function()
  return window_state.panel_size('window-state-panel', 'width', 30) == panel_width
end), 'A fresh window-state lifecycle did not restore persisted proportions')

-- A saved ratio arriving late must not undo a new manual resize.
window_state.setup({ state_directory = state_directory })
vim.cmd.vsplit()
local late_window = vim.api.nvim_get_current_win()
local late_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(late_window, late_buffer)
vim.bo[late_buffer].filetype = 'window-state-panel'
window_state.panel_size('window-state-panel', 'width', 30)
window_state.track_panel(late_window)
local latest_width = math.max(1, math.floor(vim.o.columns / 3))
vim.api.nvim_win_set_width(late_window, latest_width)
vim.api.nvim_exec_autocmds('WinResized', {})
vim.wait(50)
assert(vim.api.nvim_win_get_width(late_window) == latest_width,
  'A late preference read replaced a new manual resize')
vim.api.nvim_win_close(late_window, true)
vim.api.nvim_buf_delete(late_buffer, { force = true })
assert(window_state.prepare_panel('window-state-panel', 'width').store:flush(1000))
vim.wait(20)
vim.api.nvim_del_augroup_by_name('workspace_window_proportions')
vim.o.equalalways = original_equalalways
vim.fn.delete(state_directory, 'rf')
