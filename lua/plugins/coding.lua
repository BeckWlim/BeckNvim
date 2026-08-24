return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = { ':TSUpdate', ':TSInstall python' },
  },
  {
    'nvim-telescope/telescope.nvim',
    branch = 'master',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope-ui-select.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
      },
    },
    config = function()
      require('config.telescope').setup()
    end,
  },
  {
    'numToStr/Comment.nvim',
    opts = {},
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {
      check_ts = true,
      ts_config = {
        lua = { 'string', 'source' },
        javascript = { 'string', 'template_string' },
      },
      fast_wrap = {
        map = '<M-e>',
        chars = { '{', '[', '(', '"', "'" },
        pattern = [=[[%'%"%)%>%]%)%}%,]]=],
        end_key = '$',
        keys = 'qwfpgjluyzxcvbkmarstdheio',
        check_comma = true,
        highlight = 'Search',
        highlight_grey = 'Comment',
      },
    },
  },
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
  },
}
