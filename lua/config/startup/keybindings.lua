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

local function module_function(module_name, function_name)
  return function(...)
    return require(module_name)[function_name](...)
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
  map('<Space>o', '<C-o>', 'Jump back')
  map('<Space>p', '<C-i>', 'Jump forward')
end

local function map_editing_aids()
  local syntax_selection = require('config.syntax.selection')
  syntax_selection.setup()

  map('a', '<Nop>', 'Disable append mode')
  vim.keymap.set('x', 'q', '<Esc>', {
    silent = true,
    desc = 'Exit Visual mode',
  })
  map('<Space>zz', module_function('config.syntax.folds', 'toggle'), 'Toggle code fold')
  map('<Space>zc', 'zM', 'Close all code folds')
  map('<Space>zo', 'zR', 'Open all code folds')
  map('<Space>cc', module_function('config.syntax.treesitter_context', 'go_to_nearest_context'),
    'Go to nearest enclosing context')
  vim.keymap.set({ 'n', 'x' }, '<Space>vj', module_function('config.syntax.selection', 'select_previous'), {
    silent = true,
    desc = 'Select current or previous source symbol',
  })
  vim.keymap.set({ 'n', 'x' }, '<Space>vl', module_function('config.syntax.selection', 'select_next'), {
    silent = true,
    desc = 'Select current or next source symbol',
  })

  map('<Space>gf', module_function('config.search.navigation', 'goto_referenced_file'),
    'Go to referenced file')
  map('<Space>gv', function()
    require('config.search.navigation').goto_referenced_file_in_split('vsplit')
  end, 'Go to referenced file (vertical split)')
  map('<Space>gx', function()
    require('config.search.navigation').goto_referenced_file_in_split('split')
  end, 'Go to referenced file (horizontal split)')
  map('gx', module_function('config.ui.open_target', 'open_at_cursor'), 'Open filepath or URI')
  vim.keymap.set('x', 'gx', module_function('config.ui.open_target', 'open_selection'), {
    silent = true,
    desc = 'Open selected filepath or URI',
  })

  map('<F3>', '<cmd>NvimTreeToggle<CR>', 'Toggle file tree')
  map('<Space>h', module_function('config.ui.dashboard', 'open'), 'Open dashboard')
  map('<Space>mp', function()
    require('render-markdown').preview()
  end, 'Toggle Markdown rendered view and source')
  map('<Space>t', module_function('config.translation', 'open'), 'Open translation query')
end

local function map_finders()
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
  map('<Space>fw', module_function('config.search.workspace_symbols', 'open'),
    'Project workspace symbols')
  map('<Space>ft', module_function('config.search.workspace_symbols', 'open_for_cursor'),
    'Project definitions of cursor word')
  map('<Space>fp', module_function('config.ui.folder_picker', 'open_project'), 'Switch project')
  map('<Space>de', module_function('config.git', 'search_repository'),
    'Search Git branches, commits, and issues')
  map('<Space>df', module_function('config.git', 'history_file'), 'Git history for current file')
  map('<Space>ds', module_function('config.git', 'history_symbol'), 'Git history for cursor symbol')
  map('<Space>dr', module_function('config.git', 'history_repository'),
    'Git history for repository')
end

local function map_diagnostics()
  local diagnostics = require('config.lsp.diagnostics')
  diagnostics.setup()
  map(
    '<Space>e',
    module_function('config.lsp.diagnostics', 'open_float'),
    'Show diagnostic float'
  )
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
  map(
    '<Space>q',
    module_function('config.lsp.diagnostics', 'open_picker'),
    'Find document diagnostics'
  )
  map('<Space>gq', module_function('config.audit.diagnostic', 'open'),
    'Find project files with diagnostics')
  map('<Space>gs', module_function('config.audit.project', 'run_or_open'),
    'Run project audit / show active log')
end

local function map_lsp()
  map('gd', module_function('config.search.lsp_locations', 'definitions'), 'Find definitions')
  map('gD', module_function('config.search.lsp_locations', 'declarations'), 'Find declarations')
  map(
    'gr',
    module_function('config.search.lsp_locations', 'references'),
    'Find references',
    { nowait = true }
  )
  map('gI', module_function('config.search.lsp_locations', 'implementations'),
    'Find implementations')
  map('<Space>i', module_function('config.search.lsp_locations', 'implementations'),
    'Find implementations')
  map('<Space>D', module_function('config.search.lsp_locations', 'type_definitions'),
    'Find type definitions')
  map('<Space>cd', module_function('config.type_hierarchy', 'open_subtypes'), 'Find derived classes')
  map('<Space>cb', module_function('config.type_hierarchy', 'open_supertypes'), 'Find base classes')
  map(
    '<Space>ci',
    module_function('config.type_hierarchy', 'open_implementations'),
    'Find method implementations'
  )
  map('<Space>rn', module_function('vim.lsp.buf', 'rename'), 'Rename symbol')
  map('K', module_function('vim.lsp.buf', 'hover'), 'Show hover documentation')
  map('<Space>k', module_function('config.lsp.type_information', 'toggle'),
    'Toggle type information')
  map('<Space>lp', module_function('config.lsp', 'toggle_third_party_checks'),
    'Toggle basedpyright third-party checks')
end

function M.setup()
  map_windows()
  map_editing_aids()
  map_finders()
  map_diagnostics()
  map_lsp()
end

return M
