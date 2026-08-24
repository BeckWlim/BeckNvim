return {
  {
    'stevearc/overseer.nvim',
    lazy = false,
    opts = {
      task_win = {
        padding = 2,
        border = 'rounded',
      },
      task_list = {
        direction = 'bottom',
        min_height = 12,
        max_height = 20,
      },
    },
  },
  {
    'Civitasv/cmake-tools.nvim',
    lazy = false,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'stevearc/overseer.nvim',
    },
    opts = {
      cmake_executor = {
        name = 'overseer',
        opts = {
          new_task_opts = {
            strategy = { 'jobstart', use_terminal = false },
          },
        },
      },
      cmake_compile_commands_options = {
        action = 'lsp',
      },
    },
  },
}
