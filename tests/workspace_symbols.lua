local python_symbols = require('config.python_symbols')
local repository_root = vim.fs.normalize(vim.fn.getcwd())
local command = python_symbols.command('run_server', repository_root)
local pattern = command[#command - 1]

assert(command[1] == 'rg', 'Python symbols do not use the expected search backend')
assert(command[#command] == repository_root, 'Python symbols use the wrong project root')
assert(pattern:find('run_server', 1, true), 'Python symbol query is missing from the pattern')

local fixture_root = vim.fs.joinpath(repository_root, 'tests', 'fixtures', 'python_project')
local fixture_command = python_symbols.command('indexed_symbol', fixture_root)
local search_result = vim.system(fixture_command, { text = true }):wait()
assert(search_result.code == 0, 'Python symbol backend did not find the fixture symbol')
assert(
  search_result.stdout:find('def indexed_symbol', 1, true),
  'Python symbol backend returned the wrong fixture result'
)

local current_bufnr = vim.api.nvim_get_current_buf()
vim.bo[current_bufnr].filetype = 'python'

local opened_root
local original_python_symbols = package.loaded['config.python_symbols']
package.loaded['config.python_symbols'] = {
  open = function(root)
    opened_root = root
  end,
}

package.loaded['config.workspace_symbols'] = nil
require('config.workspace_symbols').open()
package.loaded['config.python_symbols'] = original_python_symbols

assert(opened_root == repository_root, 'Python symbol provider was not selected')
