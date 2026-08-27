local M = {}

local function open_in_vertical_split(builtin_function)
  return function()
    local actions = require('telescope.actions')
    builtin_function({
      attach_mappings = function(_, map)
        map('i', '<CR>', actions.file_vsplit)
        map('n', '<CR>', actions.file_vsplit)
        return true
      end,
    })
  end
end

local function setup_mappings()
  local builtin = require('telescope.builtin')
  local lsp_locations = require('config.lsp_locations')
  local type_hierarchy = require('config.type_hierarchy')
  local workspace_symbols = require('config.workspace_symbols')
  local function map(lhs, rhs, description, extra_options)
    local options = vim.tbl_extend('force', {
      silent = true,
      desc = description,
    }, extra_options or {})
    vim.keymap.set('n', lhs, rhs, options)
  end

  map('<Space>ff', builtin.find_files, 'Find files')
  map('<Space>fv', open_in_vertical_split(builtin.find_files), 'Find files (vertical split)')
  map('<Space>fg', builtin.live_grep, 'Live grep')
  map('<Space>fb', builtin.buffers, 'Find buffers')
  map('<Space>fr', function()
    builtin.oldfiles({ cwd = vim.fn.getcwd() })
  end, 'Recent files')
  map('<Space>bv', open_in_vertical_split(builtin.buffers), 'Find buffers (vertical split)')
  map('<Space>fh', builtin.help_tags, 'Search help')
  map('<Space>fk', builtin.keymaps, 'Search keymaps')
  map('<Space>fs', builtin.lsp_document_symbols, 'Document symbols')
  map('<Space>fw', workspace_symbols.open, 'Project workspace symbols')
  map('<Space>cd', type_hierarchy.open_subtypes, 'Find derived classes')
  map('<Space>cb', type_hierarchy.open_supertypes, 'Find base classes')
  map('<Space>ci', type_hierarchy.open_implementations, 'Find method implementations')
  map('gr', lsp_locations.references, 'Find references', { nowait = true })
  map('gI', lsp_locations.implementations, 'Find implementations')
end

function M.setup()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local workspace_symbols = require('config.workspace_symbols')
  local contextual_previewer = require('config.grep_preview').new
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
  setup_mappings()
end

return M
