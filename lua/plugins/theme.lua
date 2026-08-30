return {
  {
    'crusoexia/vim-monokai',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme('monokai')
      require('config.syntax.highlights').setup()
    end,
  },
  {
    'glepnir/dashboard-nvim',
    event = 'VimEnter',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = require('config.ui.dashboard').options(),
  },
}
