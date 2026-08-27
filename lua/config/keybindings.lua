local M = {}

local function map(lhs, rhs, description)
  vim.keymap.set('n', lhs, rhs, { silent = true, desc = description })
end

function M.setup()
  local folds = require('config.folds')
  local navigation = require('config.navigation')
  local diagnostics = require('config.diagnostics')
  local lsp_locations = require('config.lsp_locations')
  local treesitter_context = require('config.treesitter_context')

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
  map('<Space>mp', '<cmd>RenderMarkdown toggle<CR>', 'Toggle markdown preview')
  map('<Space>t', require('config.translation').open, 'Open translation query')

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

  map('<Space>i', lsp_locations.implementations, 'Find implementations')
  map('<Space>D', lsp_locations.type_definitions, 'Find type definitions')
  map('<Space>rn', vim.lsp.buf.rename, 'Rename symbol')
  map('gd', lsp_locations.definitions, 'Find definitions')
  map('gD', lsp_locations.declarations, 'Find declarations')
  map('K', vim.lsp.buf.hover, 'Show hover documentation')
  map(
    '<Space>lp',
    require('config.lsp').toggle_third_party_checks,
    'Toggle basedpyright third-party checks'
  )
end

return M
