-- Real NvimTree API: standard actions and temporary filename-search expansion.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local lazy = vim.fn.stdpath('data') .. '/lazy/'
vim.opt.runtimepath:append(lazy .. 'nvim-tree.lua')
vim.opt.runtimepath:append(lazy .. 'nvim-web-devicons')
local copied_lines = {}
vim.g.clipboard = {
  name = 'Tree path-copy test',
  copy = {
    ['+'] = function(lines) copied_lines = vim.deepcopy(lines) end,
    ['*'] = function() end,
  },
  paste = {
    ['+'] = function() return copied_lines, 'v' end,
    ['*'] = function() return {}, 'v' end,
  },
}
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/alpha/deep', 'p')
vim.fn.mkdir(root .. '/beta/deep', 'p')
vim.fn.writefile({ 'a' }, root .. '/alpha/deep/needle.txt')
vim.fn.writefile({ 'b' }, root .. '/beta/deep/needle.txt')
local function input(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
  vim.wait(200)
end
local function check(group_empty)
  require('nvim-tree').setup({
    on_attach = require('config.ui.filetree').on_attach,
    renderer = { group_empty = group_empty },
    git = { enable = false },
    filesystem_watchers = { enable = false },
  })
  local api = require('nvim-tree.api')
  api.tree.open({ path = root })
  vim.cmd('lcd ' .. vim.fn.fnameescape(root))
  local function check_copy(path, expected_path)
    api.tree.find_file({ buf = path, open = false, focus = true })
    local selected_node = api.tree.get_node_under_cursor()
    local selected_cursor = vim.api.nvim_win_get_cursor(0)
    local was_open = selected_node.open
    input('Y')
    assert(copied_lines[1] == expected_path,
      'Y must copy the full filesystem path: expected ' .. expected_path .. ', got ' .. vim.inspect(copied_lines))
    assert(vim.fn.getregtype('+') == 'v', 'Path copy must be characterwise')
    assert(api.tree.get_node_under_cursor() == selected_node
      and selected_node.open == was_open
      and vim.deep_equal(vim.api.nvim_win_get_cursor(0), selected_cursor),
      'Path copy changed the selected node or its expansion')
  end
  check_copy(root .. '/alpha', root .. (group_empty and '/alpha/deep/' or '/alpha/'))
  check_copy(root .. '/alpha/deep/needle.txt', root .. '/alpha/deep/needle.txt')
  input('zM')
  input('/needle<CR>')
  assert(api.tree.get_node_under_cursor().absolute_path == root .. '/alpha/deep/needle.txt', 'First hidden match missing')
  input('n')
  assert(api.tree.get_node_under_cursor().absolute_path == root .. '/beta/deep/needle.txt', 'Next hidden match missing')
  local function visible_matches()
    local count = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find('needle.txt', 1, true) then count = count + 1 end
    end
    return count
  end
  assert(visible_matches() == 1, 'Search left previous temporary parent expanded')
  input('N')
  assert(api.tree.get_node_under_cursor().absolute_path == root .. '/alpha/deep/needle.txt')
  input('/beta<ESC>')
  assert(api.tree.get_node_under_cursor().absolute_path == root .. '/alpha/deep/needle.txt', 'Cancel did not restore selection')
  input('zM')
  assert(visible_matches() == 0, 'zM did not collapse all')
  local folded_lines = vim.api.nvim_buf_line_count(0)
  api.tree.find_file({ buf = root .. '/alpha' })
  input('zo')
  local opened_lines = vim.api.nvim_buf_line_count(0)
  assert(opened_lines > folded_lines, 'zo did not expand')
  input('zo')
  assert(vim.api.nvim_buf_line_count(0) == opened_lines, 'zo toggled instead of expanding')
  input('zc')
  assert(vim.api.nvim_buf_line_count(0) == folded_lines, 'zc did not collapse')
  input('za')
  assert(vim.api.nvim_buf_line_count(0) == opened_lines, 'za did not toggle')
  input('zR')
  assert(visible_matches() == 2, 'zR did not expand all')
  input('/needle<CR>')
  input('n')
  assert(visible_matches() == 2, 'Search collapsed manually expanded folders')
  api.tree.close()
end
local ok, err = xpcall(function() check(false); check(true) end, debug.traceback)
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print('Installed tree actions and search tests passed')
