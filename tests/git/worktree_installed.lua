-- nvim --headless -u init.lua -i NONE '+luafile tests/git/worktree_installed.lua' '+qa!'
local graph = require('config.git.graph')
local diffview = require('config.git.diffview')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function wait_for(check, message)
  assert(vim.wait(5000, check, 20), message)
end
git('init', '--initial-branch=main')
git('config', 'user.name', 'Worktree Test')
git('config', 'user.email', 'worktree@example.invalid')
vim.fn.writefile({ 'base' }, root .. '/base.txt')
vim.fn.writefile({ 'stage' }, root .. '/staged.txt')
git('add', '.')
git('commit', '-m', 'feat: base')
local base = git('rev-parse', 'HEAD')
git('branch', 'other')
git('commit', '--allow-empty', '-m', 'feat: main')
local head = git('rev-parse', 'HEAD')
vim.fn.writefile({ 'unstaged' }, root .. '/base.txt')
vim.fn.writefile({ 'staged' }, root .. '/staged.txt')
git('add', 'staged.txt')
vim.fn.writefile({ 'new' }, root .. '/new file.txt')
local before = git('status', '--porcelain')

assert(graph.open(root, 'WORKTREE'))
wait_for(function() return vim.api.nvim_get_current_line():find('Working tree changes', 1, true) end,
  'Worktree item did not become selectable')
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[2]:find(head:sub(1, 8), 1, true), 'Worktree is not directly above HEAD')
assert(graph.focus_preview())
local preview = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(preview:find('# .M base.txt', 1, true) and preview:find('# M. staged.txt', 1, true)
  and preview:find('# ?? new file.txt', 1, true), 'Worktree preview omitted file states')
assert(graph.open_detail())
local view = require('diffview.lib').get_current_view()
wait_for(function() return view.update_needed == false and view.files:len() == 3
  and view.cur_entry and view.cur_entry.opened end,
  'Native worktree detail omitted staged, unstaged, or untracked files')
local rev_type = require('diffview.vcs.rev').RevType
assert(view.left.type == rev_type.STAGE and view.right.type == rev_type.LOCAL
  and view.git_detail_commit.kind == 'worktree'
  and view.git_history_options.revision == 'HEAD', 'Worktree detail used a synthetic Git revision')
assert(diffview.checkout_selected_commit() == false, 'Worktree item allowed synthetic checkout')
assert(git('status', '--porcelain') == before and git('rev-parse', 'HEAD') == head,
  'Worktree review mutated the checkout')
local closed = false
assert(diffview.close(nil, function() closed = true end))
wait_for(function() return closed end, 'Detail close did not settle')
assert(graph.resume(root))
wait_for(function()
  local restored = require('diffview.lib').get_current_view()
  return restored and restored.git_detail_commit.kind == 'worktree' and not restored.update_needed
    and restored.cur_entry and restored.cur_entry.opened
end, 'Session did not restore the worktree detail')
assert(diffview.toggle_history_layout())
wait_for(function() return graph.is_active()
  and vim.api.nvim_get_current_line():find('Working tree changes', 1, true) end,
  'Detail return lost the worktree selection')
assert(graph.close())

assert(graph.open(root, base, nil, 'refs/heads/other'))
wait_for(function() return vim.api.nvim_get_current_line():find(base:sub(1, 8), 1, true) end,
  'Other branch did not load')
assert(not table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('Working tree changes', 1, true),
  'Worktree attached to a branch that does not contain HEAD')
assert(graph.close())
assert(graph.open(root, 'WORKTREE'))
wait_for(function() return vim.api.nvim_get_current_line():find('Working tree changes', 1, true) end,
  'Worktree did not reopen before cleanup')
assert(graph.focus_preview())
assert(graph.close())
git('add', '.')
git('commit', '-m', 'fix: save worktree')
assert(graph.resume(root))
wait_for(function() return vim.api.nvim_get_current_line():find('fix: save worktree', 1, true) end,
  'Clean checkout did not fall back to HEAD')
assert(not table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('Working tree changes', 1, true),
  'Clean checkout retained the worktree item')
assert(graph.close())
vim.fn.delete(root, 'rf')
print('Installed Git worktree tests passed')
