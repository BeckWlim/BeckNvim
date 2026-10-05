return {
  {
    'folke/flash.nvim',
    keys = {
      {
        '<Space>s',
        function() require('config.search.flash').jump() end,
        mode = { 'n', 'x', 'o' },
        silent = true,
        desc = 'Flash jump to visible text',
      },
      {
        '<Space>fn',
        function() require('config.search.flash').treesitter() end,
        mode = { 'n', 'x', 'o' },
        silent = true,
        desc = 'Flash select syntax region',
      },
    },
    opts = {
      search = {
        -- Flash applies exclusion filters only with multi_window enabled.
        -- The shared window owner resolves projected views to their source file.
        multi_window = true,
        exclude = {
          function(win)
            return win ~= vim.api.nvim_get_current_win()
              or vim.bo[require('config.ui.window_state').file_buffer(win)].buftype ~= ''
              or not vim.api.nvim_win_get_config(win).focusable
          end,
        },
      },
      label = { uppercase = false },
      -- Match native search motions: operators stop before the text target.
      jump = { inclusive = false },
      highlight = {
        backdrop = false,
        groups = {
          match = 'TelescopeMatching',
          current = 'TelescopePreviewMatch',
          label = 'FilePaneLabel',
        },
      },
      modes = {
        search = { enabled = false },
        -- Keep native character motions and panel-local f/t actions.
        char = { enabled = false },
        treesitter = { jump = { autojump = false } },
      },
      actions = {
        ['<C-q>'] = function(state)
          state:restore()
          return false
        end,
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('config.syntax.treesitter').setup()
    end,
  },
  {
    'HiPhish/rainbow-delimiters.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    event = { 'BufReadPost', 'BufNewFile' },
    submodules = false,
    config = function()
      require('config.syntax.visuals').setup_rainbow()
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',
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
      require('config.startup.logs').configure('telescope')
      require('config.search.telescope').setup()
    end,
  },
  {
    'numToStr/Comment.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
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
    event = { 'BufReadPost', 'BufNewFile' },
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
