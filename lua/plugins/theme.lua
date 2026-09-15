return {
  {
    'crusoexia/vim-monokai',
    priority = 1000,
    lazy = false,
  },
  { 'Mofiqul/vscode.nvim', lazy = true },
  { 'folke/tokyonight.nvim', lazy = true },
  { 'catppuccin/nvim', name = 'catppuccin', lazy = true, opts = { auto_integrations = false } },
  { 'ellisonleao/gruvbox.nvim', lazy = true },
  {
    'xiantang/darcula-dark.nvim',
    lazy = true,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
  },
  {
    'glepnir/dashboard-nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = require('config.ui.dashboard').options(),
  },
}
