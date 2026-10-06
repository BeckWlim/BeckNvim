return {
  {
    'folke/neoconf.nvim',
    lazy = true,
    dependencies = { 'neovim/nvim-lspconfig' },
    opts = {
      import = {
        vscode = true,
      },
    },
  },
}
