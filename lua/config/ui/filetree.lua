local M = {}
local sync_lifecycle = 0
local pending_roots_by_tabpage = {}

local tree_glyphs = {
  arrow_closed = '',
  arrow_open = '',
  folder = '',
  folder_open = '',
  folder_empty = '',
  folder_empty_open = '',
  symlink = '',
  default = '',
}

function M.preview_node_icon(name, kind, expanded, has_children)
  if kind == 'd' then
    local arrow = expanded and tree_glyphs.arrow_open or tree_glyphs.arrow_closed
    local folder_icon
    if has_children then
      folder_icon = expanded and tree_glyphs.folder_open or tree_glyphs.folder
    else
      folder_icon = expanded and tree_glyphs.folder_empty_open or tree_glyphs.folder_empty
    end
    local highlight = expanded and 'NvimTreeOpenedFolderIcon' or 'NvimTreeFolderIcon'
    return arrow .. ' ' .. folder_icon, highlight
  end
  if kind == 'l' then
    return '  ' .. tree_glyphs.symlink, 'NvimTreeSymlinkIcon'
  end
  local loaded, devicons = pcall(require, 'nvim-web-devicons')
  if loaded then
    local extension = vim.fn.fnamemodify(name, ':e')
    local icon, highlight = devicons.get_icon(name, extension, { default = true })
    if icon then
      return '  ' .. icon, highlight or 'NvimTreeFileIcon'
    end
  end
  return '  ' .. tree_glyphs.default, 'NvimTreeFileIcon'
end

function M.preview_node_glyph(name, kind, expanded, has_children)
  return M.preview_node_icon(name, kind, expanded, has_children)
end

function M.sync_root(root, tabpage)
  local normalized_root = vim.fs.normalize(root)
  local api_loaded, api = pcall(require, 'nvim-tree.api')
  if not api_loaded or type(api.tree) ~= 'table'
      or type(api.tree.change_root) ~= 'function' then
    return false
  end

  local selected_tabpage = type(tabpage) == 'number' and tabpage or 0
  local winid_succeeded, resolved_tree_winid = pcall(function()
    if type(api.tree.winid) == 'function' then
      return api.tree.winid({ tabpage = selected_tabpage })
    end
  end)
  local tree_winid = winid_succeeded and resolved_tree_winid or nil
  local function apply_root()
    if tree_winid and vim.api.nvim_win_is_valid(tree_winid) then
      vim.cmd('lcd ' .. vim.fn.fnameescape(normalized_root))
    end
    api.tree.change_root(normalized_root)
  end

  if tree_winid and vim.api.nvim_win_is_valid(tree_winid) then
    local sync_succeeded = pcall(vim.api.nvim_win_call, tree_winid, apply_root)
    return sync_succeeded
  end
  local sync_succeeded = pcall(apply_root)
  return sync_succeeded
end

function M.setup()
  local project = require('config.project')
  sync_lifecycle = sync_lifecycle + 1
  local current_lifecycle = sync_lifecycle
  pending_roots_by_tabpage = {}
  local sync_group = vim.api.nvim_create_augroup('project_filetree_sync', { clear = true })

  local function enqueue_root(activation)
    if type(activation) ~= 'table'
        or type(activation.root) ~= 'string'
        or type(activation.tabpage) ~= 'number'
        or type(activation.generation) ~= 'number' then
      return
    end
    pending_roots_by_tabpage[activation.tabpage] = activation
    vim.schedule(function()
      if sync_lifecycle ~= current_lifecycle then
        return
      end
      local pending_activation = pending_roots_by_tabpage[activation.tabpage]
      if pending_activation ~= activation then
        return
      end
      pending_roots_by_tabpage[activation.tabpage] = nil
      if not vim.api.nvim_tabpage_is_valid(activation.tabpage) then
        return
      end
      local authoritative_activation = project.current_activation(activation.tabpage)
      if not authoritative_activation
          or authoritative_activation.generation ~= activation.generation
          or authoritative_activation.root ~= activation.root then
        return
      end
      M.sync_root(activation.root, activation.tabpage)
    end)
  end

  vim.api.nvim_create_autocmd('User', {
    group = sync_group,
    pattern = project.root_changed_pattern,
    callback = function(event)
      enqueue_root(event.data)
    end,
    desc = 'Synchronize the file tree with the active project root',
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = sync_group,
    callback = function()
      for tabpage in pairs(pending_roots_by_tabpage) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
          pending_roots_by_tabpage[tabpage] = nil
        end
      end
    end,
    desc = 'Release queued file-tree project transitions',
  })

  local active_activation = project.current_activation()
  if active_activation then
    enqueue_root(active_activation)
  end
end

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
