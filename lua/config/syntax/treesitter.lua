local M = {}

-- Parsers the config features depend on beyond Neovim's bundled set.
local required_parsers = { 'python', 'cpp' }

function M.setup()
  local treesitter = require('nvim-treesitter')
  treesitter.setup()

  local installed = treesitter.get_installed()
  local missing = vim.tbl_filter(function(language)
    return not vim.list_contains(installed, language)
  end, required_parsers)
  if #missing > 0 then
    treesitter.install(missing)
  end

  -- The main branch no longer starts highlighting itself; Neovim owns it.
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('config-treesitter-highlight', { clear = true }),
    callback = function()
      pcall(vim.treesitter.start)
    end,
  })
end

return M
