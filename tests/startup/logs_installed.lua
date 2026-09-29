-- Use disposable XDG_STATE_HOME and XDG_CACHE_HOME; run with -u init.lua.
local logs = require('config.startup.logs')
assert(vim.env.NVIM_LOG_FILE == logs.path('nvim'))
assert(vim.lsp.log.get_filename() == logs.path('lsp'))
vim.lsp.log.error('log routing fixture')
require('lazy').load({ plugins = { 'mason.nvim', 'telescope.nvim', 'LuaSnip', 'overseer.nvim' } })
assert(require('mason-core.log').outfile == logs.path('mason'))
require('mason-core.log').error('log routing fixture')
require('telescope.log').info('log routing fixture')
require('luasnip.util.log').ping()
assert(require('overseer.log').get_logfile() == logs.path('overseer'))
require('overseer.log').error('log routing fixture')
for _, name in ipairs({ 'lsp', 'mason', 'telescope', 'luasnip', 'overseer' }) do
  assert(vim.fn.filereadable(logs.path(name)) == 1, name .. ' log missing')
  assert(not vim.uv.fs_lstat(vim.fn.stdpath('state') .. '/' .. name .. '.log'), name .. ' root log reappeared')
end
print('Installed log writers use the log subfolder without root links')
vim.cmd('qa!')
