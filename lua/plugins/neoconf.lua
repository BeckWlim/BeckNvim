return {
  {
    'folke/neoconf.nvim',
    priority = 1000,
    dependencies = { 'neovim/nvim-lspconfig' },
    opts = {
      import = {
        vscode = true,
      },
    },
  },
}
