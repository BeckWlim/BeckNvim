local terminal = require('config.ui.terminal')

local terminal_buffer = vim.api.nvim_create_buf(false, true)
terminal.setup_buffer(terminal_buffer)

local terminal_mappings = vim.api.nvim_buf_get_keymap(terminal_buffer, 't')
local escape_mapping = vim.iter(terminal_mappings):find(function(mapping)
  return mapping.lhs == '<Esc>'
end)
assert(escape_mapping, 'ToggleTerm buffer has no terminal-mode escape mapping')
assert(
  escape_mapping.rhs == '<C-\\><C-N>',
  'terminal escape does not return to Normal mode'
)
assert(escape_mapping.nowait == 1, 'terminal escape waits for another key')

vim.api.nvim_buf_delete(terminal_buffer, { force = true })
