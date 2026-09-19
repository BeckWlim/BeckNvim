return {
  {
    'folke/neoconf.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    priority = 1000,
    dependencies = { 'neovim/nvim-lspconfig' },
    opts = {
      import = {
        vscode = true,
      },
    },
    config = function(_, opts)
      vim.schedule(function()
        require('neoconf').setup(opts)
      end)
    end,
  },
}
