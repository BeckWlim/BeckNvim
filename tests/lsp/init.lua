-- Focused tests for config.lsp setup.
local replaced_modules = {
  'cmp_nvim_lsp',
  'config.lsp',
  'mason',
  'mason-lspconfig',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end
local original_lsp_config = vim.lsp.config
local configured_servers = {}
local mason_options

package.loaded['cmp_nvim_lsp'] = {
  default_capabilities = function()
    return {}
  end,
}
package.loaded.mason = { setup = function() end }
package.loaded['mason-lspconfig'] = { setup = function(options) mason_options = options end }
package.loaded['config.lsp'] = nil
vim.lsp.config = function(server_name, server_config)
  configured_servers[server_name] = server_config
end

require('config.lsp').setup()
local clangd_config = assert(configured_servers.clangd, 'clangd was not configured')
local clangd_command = clangd_config.cmd
assert(vim.list_contains(clangd_command, 'clangd'), 'clangd command omitted the server executable')
assert(
  vim.list_contains(clangd_command, '--background-index')
    and vim.list_contains(clangd_command, '--background-index-priority=background')
    and vim.list_contains(clangd_command, '-j=1')
    and vim.list_contains(clangd_command, '--pch-storage=memory')
    and not vim.list_contains(clangd_command, '-j=2')
    and not vim.list_contains(clangd_command, '--pch-storage=disk'),
  'clangd command did not retain indexing with bounded CPU and disk pressure'
)
if vim.fn.executable('ionice') == 1 then
  assert(
    clangd_command[1] == 'ionice'
      and vim.list_contains(clangd_command, 'idle')
      and vim.list_contains(clangd_command, '--ignore'),
    'clangd did not use available idle-class I/O scheduling'
  )
end
if vim.fn.executable('nice') == 1 then
  assert(
    vim.list_contains(clangd_command, 'nice') and vim.list_contains(clangd_command, '10'),
    'clangd did not use available low-priority CPU scheduling'
  )
end

local original_executable = vim.fn.executable
for _, scenario in ipairs({
  { node = false, npm = false, python = false, exclude = { 'bashls', 'vimls' } },
  { node = true, npm = false, python = false },
  { node = false, npm = true, python = false },
  { node = true, npm = true, python = false },
  { node = false, npm = false, python = true },
  { node = true, npm = true, python = true },
}) do
  vim.fn.executable = function(command)
    if command == 'node' then return scenario.node and 1 or 0 end
    if command == 'npm' then return scenario.npm and 1 or 0 end
    if command == 'python3' then return scenario.python and 1 or 0 end
    return original_executable(command)
  end
  require('config.lsp').setup()
  assert(mason_options == nil,
    'BeckNvim duplicated Mason installation or activation policy')
end
vim.fn.executable = original_executable

vim.lsp.config = original_lsp_config
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
