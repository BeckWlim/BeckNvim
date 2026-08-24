return {
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('config.statusline').setup()
    end,
  },
  {
    'nvim-tree/nvim-tree.lua',
    event = 'VimEnter',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      sort = { sorter = 'case_sensitive' },
      view = { width = 30 },
      renderer = { group_empty = true },
      filters = { dotfiles = true },
    },
  },
  {
    'akinsho/toggleterm.nvim',
    opts = {
      open_mapping = [[<C-t>]],
      start_in_insert = true,
      direction = 'horizontal',
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons',
    },
    opts = {
      file_types = { 'markdown' },
      preset = 'lazy',
    },
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {
      enable = true,
      max_lines = 3,
      multiline_threshold = 2,
      mode = 'cursor',
      trim_scope = 'outer',
    },
  },
}
