local original_nvim_tree_api = package.loaded['nvim-tree.api']
local original_filetree = package.loaded['config.ui.filetree']
local original_project = package.loaded['config.project']

local tree_buffer = vim.api.nvim_create_buf(false, true)
local selected_node = { name = '..' }
local opened_node
local parent_change_count = 0
local node_change_count = 0
package.loaded['nvim-tree.api'] = {
  node = {
    open = {
      edit = function(node)
        opened_node = node
      end,
    },
  },
  tree = {
    change_root_to_parent = function()
      parent_change_count = parent_change_count + 1
    end,
    change_root_to_node = function()
      node_change_count = node_change_count + 1
    end,
    get_node_under_cursor = function()
      return selected_node
    end,
  },
  map = {
    on_attach = {
      default = function(bufnr)
        vim.keymap.set('n', '<Tab>', '<cmd>echo "preview"<CR>', { buffer = bufnr })
        vim.keymap.set('n', '<Esc>', '<cmd>echo "up"<CR>', { buffer = bufnr })
        vim.keymap.set('n', '-', '<cmd>echo "root up"<CR>', { buffer = bufnr })
        vim.keymap.set('n', '<C-]>', '<cmd>echo "root in"<CR>', { buffer = bufnr })
        vim.keymap.set('n', '<CR>', '<cmd>echo "open"<CR>', { buffer = bufnr })
      end,
    },
  },
}
package.loaded['config.project'] = {
  resolve_path = function(path)
    if path:sub(1, 13) == '/projects/one' then
      return '/projects/one'
    end
    if path:sub(1, 13) == '/projects/two' then
      return '/projects/two'
    end
    return '/shared-project'
  end,
}
package.loaded['config.ui.filetree'] = nil

local filetree = require('config.ui.filetree')
filetree.on_attach(tree_buffer)
local tree_mappings = vim.api.nvim_buf_get_keymap(tree_buffer, 'n')
assert(
  not vim.iter(tree_mappings):any(function(mapping)
    return mapping.lhs == '<Tab>'
  end),
  'file tree retained its buffer-local <Tab> preview mapping'
)
assert(
  vim.iter(tree_mappings):any(function(mapping)
    return mapping.lhs == '<CR>'
  end),
  'file tree discarded unrelated default mappings'
)

local enter_mapping
local root_back_mapping
local root_ahead_mapping
local escape_mapping
local legacy_parent_mapping
local legacy_child_mapping
vim.api.nvim_buf_call(tree_buffer, function()
  enter_mapping = vim.fn.maparg('<CR>', 'n', false, true)
  root_back_mapping = vim.fn.maparg('gh', 'n', false, true)
  root_ahead_mapping = vim.fn.maparg('gl', 'n', false, true)
  escape_mapping = vim.fn.maparg('<Esc>', 'n', false, true)
  legacy_parent_mapping = vim.fn.maparg('-', 'n', false, true)
  legacy_child_mapping = vim.fn.maparg('<C-]>', 'n', false, true)
end)
assert(vim.tbl_isempty(escape_mapping), 'file tree retained Escape as root-up navigation')
assert(vim.tbl_isempty(legacy_parent_mapping), 'file tree retained the default - root-up mapping')
assert(vim.tbl_isempty(legacy_child_mapping), 'file tree retained the default <C-]> root-in mapping')
assert(type(enter_mapping.callback) == 'function', 'file tree did not override <CR> safely')
enter_mapping.callback()
assert(opened_node == nil, '<CR> still opened the parent entry')

selected_node = {
  name = 'child.py',
  absolute_path = vim.fs.joinpath(vim.fn.getcwd(), 'child.py'),
  parent = { name = vim.fs.basename(vim.fn.getcwd()) },
  type = 'file',
}
enter_mapping.callback()
assert(opened_node == selected_node, '<CR> no longer opens regular tree nodes')
assert(type(root_back_mapping.callback) == 'function', 'file tree has no gh root-back mapping')
root_back_mapping.callback()
assert(parent_change_count == 1, 'gh did not change to the parent root')
assert(type(root_ahead_mapping.callback) == 'function', 'file tree has no gl root-ahead mapping')
root_ahead_mapping.callback()
assert(node_change_count == 1, 'gl did not change root to the selected node')

local confirmation_message
local switch_allowed = filetree.confirm_project_change(
  '/projects/one/src',
  '/projects/two/src',
  function(message, choices, default_choice)
    confirmation_message = message
    assert(choices == '&Switch\n&Cancel', 'project confirmation has unexpected choices')
    assert(default_choice == 2, 'project confirmation did not default to cancel')
    return 2
  end
)
assert(not switch_allowed, 'cancelling a cross-project root change was ignored')
assert(
  confirmation_message and confirmation_message:find('/projects/one', 1, true),
  'project confirmation omitted the current project'
)
assert(
  confirmation_message and confirmation_message:find('/projects/two', 1, true),
  'project confirmation omitted the target project'
)
assert(
  filetree.confirm_project_change('/projects/one/src', '/projects/one/tests'),
  'a root change inside one project requested confirmation'
)

vim.api.nvim_buf_delete(tree_buffer, { force = true })
package.loaded['nvim-tree.api'] = original_nvim_tree_api
package.loaded['config.ui.filetree'] = original_filetree
package.loaded['config.project'] = original_project
