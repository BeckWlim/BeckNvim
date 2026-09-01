return {
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    lazy = true,
    config = function()
      require('config.git.diffview').setup()
    end,
  },
}
