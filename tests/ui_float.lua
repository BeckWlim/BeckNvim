local float = require('config.ui.float')

assert(float.input_close_key == '<C-q>', 'float input close key changed')
assert(float.normal_close_key == 'q', 'float normal close key changed')
float.setup()

local background_window = vim.api.nvim_get_current_win()
local dialog_buffer = vim.api.nvim_create_buf(false, true)
local dialog_window = vim.api.nvim_open_win(dialog_buffer, true, {
  relative = 'editor',
  row = 1,
  col = 1,
  width = 20,
  height = 2,
  focusable = true,
  style = 'minimal',
})
vim.api.nvim_set_current_win(background_window)
assert(vim.wait(100, function()
  return vim.api.nvim_get_current_win() == dialog_window
end, 1), 'background pane retained focus while a floating dialog was active')

local nested_buffer = vim.api.nvim_create_buf(false, true)
local nested_window = vim.api.nvim_open_win(nested_buffer, true, {
  relative = 'editor',
  row = 4,
  col = 1,
  width = 20,
  height = 2,
  focusable = true,
  style = 'minimal',
})
assert(
  vim.api.nvim_get_current_win() == nested_window,
  'focus lock rejected another floating dialog window'
)
vim.api.nvim_win_close(nested_window, true)
vim.api.nvim_win_close(dialog_window, true)
assert(vim.wait(100, function()
  return vim.api.nvim_get_current_win() == background_window
end, 1), 'closing floating dialogs did not release the background pane')

local input_buffer = vim.api.nvim_create_buf(false, true)
local close_calls = 0
float.bind_close({
  accepts_input = true,
  buffer = input_buffer,
  close = function()
    close_calls = close_calls + 1
  end,
  description = 'Close test input float',
})

local function buffer_mapping(buffer_number, mode, lhs)
  return vim.iter(vim.api.nvim_buf_get_keymap(buffer_number, mode)):find(function(keymap)
    return keymap.lhs == lhs
  end)
end

local normal_q_mapping = buffer_mapping(input_buffer, 'n', 'q')
local insert_ctrl_q_mapping = buffer_mapping(input_buffer, 'i', '<C-Q>')
assert(normal_q_mapping and normal_q_mapping.callback, 'normal q does not close an input float')
assert(insert_ctrl_q_mapping and insert_ctrl_q_mapping.callback, 'insert Ctrl-Q does not close')
assert(not buffer_mapping(input_buffer, 'i', 'q'), 'insert q was captured by the float policy')
assert(
  not buffer_mapping(input_buffer, 'n', '<C-Q>'),
  'normal Ctrl-Q was captured instead of preserving Visual Block'
)
normal_q_mapping.callback()
insert_ctrl_q_mapping.callback()
assert(close_calls == 2, 'float close mappings did not invoke the supplied callback')

local mapped_keys = {}
float.bind_close({
  accepts_input = true,
  close = function() end,
  map = function(mode, lhs, _callback)
    mapped_keys[mode] = lhs
  end,
})
assert(mapped_keys.i == '<C-q>', 'custom float mapper omitted the input close key')
assert(mapped_keys.n == 'q', 'custom float mapper omitted the normal close key')

vim.api.nvim_buf_delete(input_buffer, { force = true })
