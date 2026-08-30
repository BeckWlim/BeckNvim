local M = {}

function M.setup()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local workspace_symbols = require('config.search.workspace_symbols')
  local contextual_previewer = require('config.search.grep_preview').new
  telescope.setup({
    defaults = {
      grep_previewer = contextual_previewer,
      qflist_previewer = contextual_previewer,
      mappings = {
        i = { ['<C-q>'] = actions.close },
        n = { ['<C-q>'] = actions.close },
      },
      path_display = { 'smart' },
      vimgrep_arguments = {
        'rg',
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
        '--smart-case',
        '--hidden',
        '--no-ignore-vcs',
      },
      file_ignore_patterns = { '.git/', 'node_modules/', '__pycache__/' },
    },
    extensions = {
      ['ui-select'] = require('telescope.themes').get_dropdown({
        previewer = false,
        layout_config = { width = 0.55, height = 0.45 },
      }),
    },
  })
  pcall(telescope.load_extension, 'fzf')
  telescope.load_extension('ui-select')
  require('config.python.hierarchy_index').setup()
  workspace_symbols.setup()
end

return M
