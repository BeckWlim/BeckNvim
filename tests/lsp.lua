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

package.loaded['cmp_nvim_lsp'] = {
  default_capabilities = function()
    return {}
  end,
}
package.loaded.mason = { setup = function() end }
package.loaded['mason-lspconfig'] = { setup = function() end }
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

vim.lsp.config = original_lsp_config
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
