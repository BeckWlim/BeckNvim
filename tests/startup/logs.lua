local logs = require('config.startup.logs')
local original_stdpath = vim.fn.stdpath
local original_logfile = vim.env.NVIM_LOG_FILE
local original_snippet_path = vim.env.LUASNIP_OVERRIDE_LOGPATH
local original_lsp_path = vim.lsp.log.get_filename()
local root = vim.fn.tempname()
vim.fn.stdpath = function(kind)
  if kind == 'state' then return root end
  return original_stdpath(kind)
end
logs.setup()
assert(vim.fn.isdirectory(root .. '/logs') == 1, 'Log folder must exist before plugins load')
assert(vim.env.NVIM_LOG_FILE == root .. '/logs/nvim.log')
assert(vim.env.LUASNIP_OVERRIDE_LOGPATH == root .. '/logs')
assert(vim.lsp.log.get_filename() == root .. '/logs/lsp.log')
logs.setup()
assert(vim.deep_equal(vim.fn.readdir(root), { 'logs' }), 'Setup created redundant root log files or links')
vim.fn.stdpath = original_stdpath
vim.env.NVIM_LOG_FILE = original_logfile
vim.env.LUASNIP_OVERRIDE_LOGPATH = original_snippet_path
vim.lsp.log._set_filename(original_lsp_path)
vim.fn.delete(root, 'rf')
