local M = {}

-- Keymaps are assembled here so every normal-mode binding lives in one place.
-- Telescope builtins are required lazily inside each callback to preserve
-- telescope.nvim's lazy loading at startup.
local function telescope_builtin(name)
  return function(...)
    return require('telescope.builtin')[name](...)
  end
end

local function telescope_builtin_in_vertical_split(name)
  return function()
    local actions = require('telescope.actions')
    require('telescope.builtin')[name]({
      attach_mappings = function(_, map)
        map('i', '<CR>', actions.file_vsplit)
        map('n', '<CR>', actions.file_vsplit)
        return true
      end,
    })
  end
end

local function map(lhs, rhs, description, extra_options)
  local options = vim.tbl_extend('force', {
    silent = true,
    desc = description,
  }, extra_options or {})
  vim.keymap.set('n', lhs, rhs, options)
end

local function map_windows()
  map('<Space>wi', '<C-w>k', 'Window up')
  map('<Space>wj', '<C-w>h', 'Window left')
  map('<Space>wk', '<C-w>j', 'Window down')
  map('<Space>wl', '<C-w>l', 'Window right')
  map('<Space>wv', '<C-w>v', 'Vertical split')
  map('<Space>ws', '<C-w>s', 'Horizontal split')
  map('<Space>wq', '<C-w>q', 'Close window')
  map('<Space>wo', '<C-w>o', 'Only window')

  map('<Space>ri', '<C-w>3+', 'Taller (push up)')
  map('<Space>rk', '<C-w>3-', 'Shorter (push down)')
  map('<Space>rj', '<C-w>5<', 'Narrower (push left)')
  map('<Space>rl', '<C-w>5>', 'Wider (push right)')
  map('<Space>r=', '<C-w>=', 'Equalize windows')

  map('<Tab>', '<C-w>w', 'Next window')
  map('<S-Tab>', '<C-w>W', 'Previous window')
  map('<Space>o', function()
    if require('config.git').return_to_inspector() then
      return
    end
    vim.api.nvim_feedkeys(vim.keycode('<C-o>'), 'n', false)
  end, 'Jump back')
  map('<Space>p', '<C-i>', 'Jump forward')
end

local function map_editing_aids()
  local folds = require('config.syntax.folds')
  local navigation = require('config.search.navigation')
  local treesitter_context = require('config.syntax.treesitter_context')

  map('<Space>zz', folds.toggle, 'Toggle code fold')
  map('<Space>zc', 'zM', 'Close all code folds')
  map('<Space>zo', 'zR', 'Open all code folds')
  map('<Space>cc', treesitter_context.go_to_nearest_context, 'Go to nearest enclosing context')

  map('<Space>gf', navigation.goto_referenced_file, 'Go to referenced file')
  map('<Space>gv', function()
    navigation.goto_referenced_file_in_split('vsplit')
  end, 'Go to referenced file (vertical split)')
  map('<Space>gx', function()
    navigation.goto_referenced_file_in_split('split')
  end, 'Go to referenced file (horizontal split)')

  map('<F3>', '<cmd>NvimTreeToggle<CR>', 'Toggle file tree')
  map('<Space>h', require('config.ui.dashboard').open, 'Open dashboard')
  map('<Space>mp', '<cmd>RenderMarkdown toggle<CR>', 'Toggle markdown preview')
  map('<Space>t', require('config.translation').open, 'Open translation query')
end

local function map_finders()
  local workspace_symbols = require('config.search.workspace_symbols')

  map('<Space>ff', telescope_builtin('find_files'), 'Find files')
  map('<Space>fv', telescope_builtin_in_vertical_split('find_files'), 'Find files (vertical split)')
  map('<Space>fg', telescope_builtin('live_grep'), 'Live grep')
  map('<Space>fb', telescope_builtin('buffers'), 'Find buffers')
  map('<Space>fr', function()
    require('telescope.builtin').oldfiles({ cwd = vim.fn.getcwd() })
  end, 'Recent files')
  map('<Space>bv', telescope_builtin_in_vertical_split('buffers'), 'Find buffers (vertical split)')
  map('<Space>fh', telescope_builtin('help_tags'), 'Search help')
  map('<Space>fk', telescope_builtin('keymaps'), 'Search keymaps')
  map('<Space>fs', telescope_builtin('lsp_document_symbols'), 'Document symbols')
  map('<Space>fw', workspace_symbols.open, 'Project workspace symbols')
  map('<Space>ft', workspace_symbols.open_for_cursor, 'Project definitions of cursor word')
  local git = require('config.git')
  map('<Space>de', git.search_repository, 'Enter Git mode and search repository')
  map('<Space>df', git.history_file, 'Git history for current file')
  map('<Space>ds', git.history_symbol, 'Git history for cursor symbol')
  map('<Space>dr', git.history_repository, 'Git history for repository')
end

local function map_diagnostics()
  local diagnostics = require('config.lsp.diagnostics')

  diagnostics.setup()
  map('<Space>e', diagnostics.open_float, 'Show diagnostic float')
  map('[d', function()
    vim.diagnostic.jump({
      count = -1,
      on_jump = function()
        vim.diagnostic.open_float()
      end,
    })
  end, 'Previous diagnostic')
  map(']d', function()
    vim.diagnostic.jump({
      count = 1,
      on_jump = function()
        vim.diagnostic.open_float()
      end,
    })
  end, 'Next diagnostic')
  map('<Space>q', diagnostics.open_picker, 'Find document diagnostics')
  map('<Space>gq', require('config.audit.diagnostic').open, 'Find project files with diagnostics')
  map(
    '<Space>gs',
    require('config.audit.project').run_or_open,
    'Run project audit / show active log'
  )
end

local function map_lsp()
  local lsp_locations = require('config.search.lsp_locations')
  local type_hierarchy = require('config.type_hierarchy')

  map('gd', lsp_locations.definitions, 'Find definitions')
  map('gD', lsp_locations.declarations, 'Find declarations')
  map('gr', lsp_locations.references, 'Find references', { nowait = true })
  map('gI', lsp_locations.implementations, 'Find implementations')
  map('<Space>i', lsp_locations.implementations, 'Find implementations')
  map('<Space>D', lsp_locations.type_definitions, 'Find type definitions')
  map('<Space>cd', type_hierarchy.open_subtypes, 'Find derived classes')
  map('<Space>cb', type_hierarchy.open_supertypes, 'Find base classes')
  map('<Space>ci', type_hierarchy.open_implementations, 'Find method implementations')
  map('<Space>rn', vim.lsp.buf.rename, 'Rename symbol')
  map('K', vim.lsp.buf.hover, 'Show hover documentation')
  map('<Space>k', require('config.lsp.type_information').toggle, 'Toggle type information')
  map(
    '<Space>lp',
    require('config.lsp').toggle_third_party_checks,
    'Toggle basedpyright third-party checks'
  )
end

function M.setup()
  map_windows()
  map_editing_aids()
  map_finders()
  map_diagnostics()
  map_lsp()
end

return M
