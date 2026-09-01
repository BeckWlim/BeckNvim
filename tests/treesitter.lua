local original_treesitter_plugin = package.loaded['nvim-treesitter']
local original_treesitter_config = package.loaded['config.syntax.treesitter']
local original_start = vim.treesitter.start

local setup_called = false
local installed_filter
local requested_parsers
local installation_callback
local start_calls = {}

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

vim.treesitter.start = function(buffer_number)
  start_calls[#start_calls + 1] = buffer_number
  error('parser is not installed yet')
end

local test_buffer = vim.api.nvim_create_buf(false, true)
vim.bo[test_buffer].filetype = 'cpp'

require('config.syntax.treesitter').setup()

assert(setup_called, 'nvim-treesitter setup was not called')
assert(installed_filter == 'parsers', 'query-only languages were treated as installed parsers')
assert(
  vim.deep_equal(requested_parsers, { 'cpp' }),
  'missing parser installation did not use parser-only detection'
)
assert(type(installation_callback) == 'function', 'parser installation completion was not observed')

vim.api.nvim_exec_autocmds('FileType', { buffer = test_buffer })
assert(#start_calls == 1, 'FileType did not attempt to start Treesitter highlighting')

installation_callback(nil, true)
assert(vim.wait(500, function()
  return #start_calls == 2
end), 'highlighting was not retried after parser installation completed')
assert(start_calls[2] == test_buffer, 'parser completion retried the wrong buffer')

vim.api.nvim_del_augroup_by_name('config-treesitter-highlight')
vim.api.nvim_buf_delete(test_buffer, { force = true })
vim.treesitter.start = original_start
package.loaded['config.syntax.treesitter'] = original_treesitter_config
package.loaded['nvim-treesitter'] = original_treesitter_plugin
