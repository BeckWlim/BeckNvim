return {
  {
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy',
    config = function()
      require('config.ui.statusline').setup()
    end,
  },
  {
    'nvim-tree/nvim-tree.lua',
    cmd = {
      'NvimTreeToggle',
      'NvimTreeOpen',
      'NvimTreeFocus',
      'NvimTreeFindFile',
    },
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      on_attach = require('config.ui.filetree').on_attach,
      sort = { sorter = 'case_sensitive' },
      view = { width = 30 },
      renderer = { group_empty = true },
      filters = { dotfiles = true },
      actions = {
        change_dir = {
          enable = true,
          global = false,
        },
      },
    },
    config = function(_, opts)
      require('nvim-tree').setup(opts)
      require('config.ui.filetree').setup()
    end,
  },
  {
    'akinsho/toggleterm.nvim',
    event = 'VeryLazy',
    opts = {
      open_mapping = [[<C-t>]],
      start_in_insert = true,
      direction = 'horizontal',
      shade_terminals = false,
      on_open = function(terminal)
        require('config.ui.terminal').setup_buffer(terminal.bufnr)
      end,
    },
  },
  {
    'BeckWlim/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      { 'BeckWlim/termaid', optional = true },
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons',
    },
    opts = {
      debounce = 1,
      preset = 'lazy',
      render_modes = { 'n', 'c', 't', 'v', 'V', '\22' },
      win_options = {
        concealcursor = { default = '', rendered = 'nvic' },
        breakindent = { default = false, rendered = true },
        breakindentopt = {
          default = '',
          rendered = 'shift:2,min:20',
        },
        linebreak = { default = false, rendered = true },
        showbreak = { default = '', rendered = '↳ ' },
        smoothscroll = { default = false, rendered = true },
        wrap = { default = false, rendered = true },
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('config.syntax.treesitter_context').setup()
      require('config.syntax.visuals').setup_scopes()
    end,
  },
}
