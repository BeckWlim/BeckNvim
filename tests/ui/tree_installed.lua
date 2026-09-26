-- Real NvimTree API: standard actions and temporary filename-search expansion.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local lazy = vim.fn.stdpath('data') .. '/lazy/'
vim.opt.runtimepath:append(lazy .. 'nvim-tree.lua')
vim.opt.runtimepath:append(lazy .. 'nvim-web-devicons')
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
