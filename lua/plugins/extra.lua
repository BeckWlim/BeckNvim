return {
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('config.ui.statusline').setup()
    end,
  },
  {
    'nvim-tree/nvim-tree.lua',
    event = 'VimEnter',
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
  },
  {
    'akinsho/toggleterm.nvim',
    opts = {
      open_mapping = [[<C-t>]],
      start_in_insert = true,
      direction = 'horizontal',
      on_open = function(terminal)
        require('config.ui.terminal').setup_buffer(terminal.bufnr)
      end,
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
      debounce = 1,
      custom_handlers = {
        markdown = require('config.syntax.markdown').handler,
      },
      file_types = { 'markdown' },
      on = {
        attach = require('config.syntax.markdown').attach,
        clear = require('config.syntax.markdown').clear,
        render = require('config.syntax.markdown').render,
      },
      pipe_table = {
        enabled = false,
      },
      preset = 'lazy',
      win_options = {
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
    config = function()
      require('config.syntax.treesitter_context').setup()
      require('config.syntax.visuals').setup_scopes()
    end,
  },
}
