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
  local function map(lhs, rhs, description)
    vim.keymap.set('n', lhs, rhs, { silent = true, desc = description })
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
  map('<Space>fw', require('config.workspace_symbols').open, 'Project workspace symbols')
  map('gr', builtin.lsp_references, 'Find references')
  map('gd', builtin.lsp_definitions, 'Go to definition')
  map('gD', vim.lsp.buf.declaration, 'Go to declaration')
  map('gI', builtin.lsp_implementations, 'Go to implementation')
end

function M.setup()
  local telescope = require('telescope')
  telescope.setup({
    defaults = {
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
  setup_mappings()
end

return M
