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
