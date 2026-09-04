local original_treesitter_plugin = package.loaded['nvim-treesitter']
local original_treesitter_config = package.loaded['config.syntax.treesitter']
local original_rainbow_library = package.loaded['rainbow-delimiters.lib']
local original_start = vim.treesitter.start
local original_rainbow_loaded = vim.g.loaded_rainbow_delimiters

local setup_called = false
local installed_filter
local requested_parsers
local installation_callback
local start_calls = {}
local rainbow_attach_calls = {}

package.loaded['nvim-treesitter'] = {
  setup = function()
    setup_called = true
  end,
  get_installed = function(filter)
    installed_filter = filter
    return { 'python' }
  end,
  install = function(parsers)
    requested_parsers = parsers
    return {
      await = function(_, callback)
        installation_callback = callback
      end,
    }
  end,
}
package.loaded['config.syntax.treesitter'] = nil
package.loaded['rainbow-delimiters.lib'] = {
  attach = function(buffer_number)
    rainbow_attach_calls[#rainbow_attach_calls + 1] = buffer_number
  end,
}
vim.g.loaded_rainbow_delimiters = true

vim.treesitter.start = function(buffer_number)
  start_calls[#start_calls + 1] = buffer_number
  error('parser is not installed yet')
end

local test_buffer = vim.api.nvim_create_buf(false, true)
vim.bo[test_buffer].filetype = 'cpp'

local treesitter_config = require('config.syntax.treesitter')
treesitter_config.setup()

assert(setup_called, 'nvim-treesitter setup was not called')
assert(installed_filter == 'parsers', 'query-only languages were treated as installed parsers')
assert(
  vim.deep_equal(requested_parsers, { 'cpp' }),
  'missing parser installation did not use parser-only detection'
)
assert(type(installation_callback) == 'function', 'parser installation completion was not observed')

vim.api.nvim_exec_autocmds('FileType', { buffer = test_buffer })
assert(#start_calls == 1, 'FileType did not attempt to start Treesitter highlighting')

treesitter_config.ensure_highlighting(test_buffer)
assert(
  #start_calls == 2
    and start_calls[2] == test_buffer
    and rainbow_attach_calls[1] == test_buffer,
  'Explicit syntax synchronization did not retry Tree-sitter and rainbow highlighting'
)
treesitter_config.ensure_highlighting(test_buffer)
assert(
  #rainbow_attach_calls == 1,
  'Repeated syntax synchronization attached rainbow parsing more than once per buffer'
)

local hidden_diffview_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(hidden_diffview_buffer, 'diffview://history/large.cpp')
vim.bo[hidden_diffview_buffer].filetype = 'cpp'
local starts_before_hidden_diff = #start_calls
vim.api.nvim_exec_autocmds('FileType', { buffer = hidden_diffview_buffer })
treesitter_config.ensure_highlighting(hidden_diffview_buffer)
assert(
  #start_calls == starts_before_hidden_diff,
  'Hidden Diffview prewarm buffers started synchronous Tree-sitter work'
)

local starts_before_installation = #start_calls
installation_callback(nil, true)
assert(vim.wait(500, function()
  for start_index = starts_before_installation + 1, #start_calls do
    if start_calls[start_index] == test_buffer then
      return true
    end
  end
  return false
end), 'highlighting was not retried after parser installation completed')
for start_index = starts_before_installation + 1, #start_calls do
  assert(
    start_calls[start_index] ~= hidden_diffview_buffer,
    'Parser installation eagerly parsed a hidden Diffview prewarm buffer'
  )
end

vim.api.nvim_del_augroup_by_name('config-treesitter-highlight')
vim.api.nvim_buf_delete(hidden_diffview_buffer, { force = true })
vim.api.nvim_buf_delete(test_buffer, { force = true })
vim.treesitter.start = original_start
package.loaded['config.syntax.treesitter'] = original_treesitter_config
package.loaded['rainbow-delimiters.lib'] = original_rainbow_library
package.loaded['nvim-treesitter'] = original_treesitter_plugin
vim.g.loaded_rainbow_delimiters = original_rainbow_loaded
