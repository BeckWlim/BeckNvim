return {
  {
    'sindrets/diffview.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<Space>dv', '<cmd>DiffviewOpen<CR>', desc = 'Diffview: current branch vs HEAD' },
      { '<Space>dvm', '<cmd>DiffviewOpen main<CR>', desc = 'Diffview: vs main' },
      { '<Space>dvh', '<cmd>DiffviewFileHistory %<CR>', desc = 'Diffview: file history' },
      { '<Space>dvc', '<cmd>DiffviewClose<CR>', desc = 'Diffview: close' },
    },
  },
}
