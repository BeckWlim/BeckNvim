local M = {}

local function detected_project_label(root)
  if not root then
    return 'No detected project'
  end
  return vim.fn.fnamemodify(root, ':~')
end

function M.confirm_project_change(current_path, target_path, confirm)
  local project = require('config.project')
  local current_project = project.resolve_path(current_path)
  local target_project = project.resolve_path(target_path)
  if current_project == target_project or (not current_project and not target_project) then
    return true
  end

  local confirm_change = confirm or vim.fn.confirm
  local message = table.concat({
    'Switch file-tree project?',
    '',
    detected_project_label(current_project),
    '  ->  ' .. detected_project_label(target_project),
  }, '\n')
  return confirm_change(message, '&Switch\n&Cancel', 2) == 1
end

local function current_tree_root()
  local window_directory = vim.fn.getcwd(0)
  if type(window_directory) ~= 'string' or window_directory == '' then
    return
  end
  return vim.fs.normalize(window_directory)
end

local function parent_path(path)
  return vim.fs.dirname(path)
end

local function node_target_path(node, tree_root)
  if not node or node.name == '..' or not node.parent then
    return parent_path(tree_root)
  end
  if node.type == 'file' or (node.type == 'link' and type(node.nodes) ~= 'table') then
    return parent_path(node.absolute_path)
  end
  return vim.fs.normalize(node.absolute_path)
end

function M.on_attach(bufnr)
  local api = require('nvim-tree.api')
  api.map.on_attach.default(bufnr)
  pcall(vim.keymap.del, 'n', '<Tab>', { buffer = bufnr })
  pcall(vim.keymap.del, 'n', '<Esc>', { buffer = bufnr })
  pcall(vim.keymap.del, 'n', '<C-[>', { buffer = bufnr })
  pcall(vim.keymap.del, 'n', '-', { buffer = bufnr })
  pcall(vim.keymap.del, 'n', '<C-]>', { buffer = bufnr })

  vim.keymap.set('n', '<CR>', function()
    local selected_node = api.tree.get_node_under_cursor()
    if selected_node and selected_node.name ~= '..' then
      api.node.open.edit(selected_node)
    end
  end, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'nvim-tree: Open except parent entry',
  })
  vim.keymap.set('n', 'gh', function()
    local tree_root = current_tree_root()
    if not tree_root or M.confirm_project_change(tree_root, parent_path(tree_root)) then
      api.tree.change_root_to_parent()
    end
  end, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'nvim-tree: Root back',
  })
  vim.keymap.set('n', 'gl', function()
    local selected_node = api.tree.get_node_under_cursor()
    local tree_root = current_tree_root()
    if not tree_root then
      api.tree.change_root_to_node(selected_node)
      return
    end
    local target_path = node_target_path(selected_node, tree_root)
    if M.confirm_project_change(tree_root, target_path) then
      api.tree.change_root_to_node(selected_node)
    end
  end, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'nvim-tree: Root ahead',
  })
end

return M
