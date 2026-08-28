local original_telescope_builtin = package.loaded['telescope.builtin']
local original_diagnostics = package.loaded['config.diagnostics']
local original_detail_window = package.loaded['config.detail_window']

local picker_options
package.loaded['telescope.builtin'] = {
  diagnostics = function(options)
    picker_options = options
  end,
}
package.loaded['config.detail_window'] = nil
package.loaded['config.diagnostics'] = nil

local diagnostics = require('config.diagnostics')
local diagnostic_namespace = vim.api.nvim_create_namespace('diagnostic-detail-test')
local diagnostic_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(diagnostic_buffer)
vim.api.nvim_buf_set_lines(diagnostic_buffer, 0, -1, false, { 'broken()' })
vim.diagnostic.set(diagnostic_namespace, diagnostic_buffer, {
  { lnum = 0, col = 0, message = 'broken call', severity = vim.diagnostic.severity.ERROR },
})
diagnostics.open_float()
local diagnostic_window = vim.api.nvim_get_current_win()
local diagnostic_float_buffer = vim.api.nvim_get_current_buf()
local diagnostic_window_config = vim.api.nvim_win_get_config(diagnostic_window)
local diagnostic_lines = vim.api.nvim_buf_get_lines(
  diagnostic_float_buffer,
  0,
  -1,
  false
)
assert(diagnostic_window_config.relative ~= '', 'diagnostic detail did not open a float')
assert(
  diagnostic_window_config.title[1][1] == ' Diagnostic details ',
  'diagnostic detail did not use the shared titled-dialog style'
)
assert(vim.wo[diagnostic_window].linebreak, 'diagnostic details lack word-aware wrapping')
assert(vim.wo[diagnostic_window].showbreak == '↳ ', 'diagnostic wraps lack continuation marks')
assert(not vim.wo[diagnostic_window].cursorline, 'single diagnostic retained selection background')
assert(
  diagnostic_lines[1]:find('<Space>e/q close', 1, true),
  'diagnostic detail omitted its quick-button hint line'
)
assert(
  diagnostic_lines[2]:find('1', 1, true) and diagnostic_lines[2]:find('broken call', 1, true),
  'diagnostic detail did not render a numbered entry'
)
local close_detail_mapping = vim.fn.maparg('<Space>e', 'n', false, true)
assert(type(close_detail_mapping.callback) == 'function', 'diagnostic detail has no same-key close')
close_detail_mapping.callback()
assert(not vim.api.nvim_win_is_valid(diagnostic_window), '<Space>e did not close diagnostic detail')

diagnostics.open_picker()

assert(picker_options, 'diagnostic picker was not opened')
assert(picker_options.bufnr == 0, 'diagnostic picker did not target the current buffer')

package.loaded['telescope.builtin'] = original_telescope_builtin
package.loaded['config.detail_window'] = original_detail_window
package.loaded['config.diagnostics'] = original_diagnostics
