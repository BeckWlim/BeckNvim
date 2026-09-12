-- Focused tests for config.syntax.selection.
local syntax_selection = require('config.syntax.selection')

local original_buffer = vim.api.nvim_get_current_buf()
local selection_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(selection_buffer)
vim.api.nvim_buf_set_lines(selection_buffer, 0, -1, false, {
  'key_strs, buffer_ptrs, buffer_sizes = self._batch_preprocess(keys, host_indices)',
})
vim.bo[selection_buffer].filetype = 'python'
vim.treesitter.get_parser(selection_buffer):parse()

local function selected_text()
  local anchor_position = vim.fn.getpos('v')
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local anchor_row = anchor_position[2] - 1
  local anchor_column = anchor_position[3] - 1
  local cursor_row = cursor_position[1] - 1
  local cursor_column = cursor_position[2]
  local start_row = anchor_row
  local start_column = anchor_column
  local end_row = cursor_row
  local end_column = cursor_column
  if cursor_row < anchor_row or (cursor_row == anchor_row and cursor_column < anchor_column) then
    start_row = cursor_row
    start_column = cursor_column
    end_row = anchor_row
    end_column = anchor_column
  end
  local selected_end_line = vim.api.nvim_buf_get_lines(
    selection_buffer,
    end_row,
    end_row + 1,
    false
  )[1] or ''
  local final_character_text = selected_end_line:sub(end_column + 1)
  local final_character_width = vim.str_byteindex(final_character_text, 'utf-32', 1, false)
  return table.concat(vim.api.nvim_buf_get_text(
    selection_buffer,
    start_row,
    start_column,
    end_row,
    end_column + final_character_width,
    {}
  ), '\n')
end

vim.api.nvim_win_set_cursor(0, { 1, 0 })
syntax_selection.select_next()
assert(vim.api.nvim_get_mode().mode == 'v', 'Symbol selection did not enter Visual mode')
assert(selected_text() == 'key_strs', 'Symbol selection did not start at the cursor identifier')

for _, expected_symbol in ipairs({
  'buffer_ptrs',
  'buffer_sizes',
  'self',
  '_batch_preprocess',
  'keys',
  'host_indices',
}) do
  syntax_selection.select_next()
  assert(
    selected_text() == expected_symbol,
    'Symbol selection did not advance to ' .. expected_symbol
  )
end

syntax_selection.select_previous()
assert(selected_text() == 'keys', 'Symbol selection did not return to the previous identifier')

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(selection_buffer, { force = true })
