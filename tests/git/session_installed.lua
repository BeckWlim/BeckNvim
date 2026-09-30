-- nvim --headless -u init.lua -i NONE '+luafile tests/git/session_installed.lua' '+qa!'
local graph = require('config.git.graph')
local diffview = require('config.git.diffview')
local session = require('config.git.session')
local editor_tab = vim.api.nvim_get_current_tabpage()
local workspace = vim.fn.tempname()
local root = workspace .. '/first'
local other = workspace .. '/second'

local function git(directory, ...)
  local command = { 'git', '-C', directory }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

for _, directory in ipairs({ root, other }) do
  vim.fn.mkdir(directory, 'p')
  git(directory, 'init', '--initial-branch=main')
  git(directory, 'config', 'user.name', 'Session Test')
  git(directory, 'config', 'user.email', 'session@example.invalid')
  vim.fn.writefile({ 'first', 'second', 'third', 'fourth' }, directory .. '/a.txt')
  vim.fn.writefile({ 'one', 'two', 'three', 'four' }, directory .. '/b.txt')
  git(directory, 'add', '.')
  git(directory, 'commit', '-m', 'feat: initial files')
end
local first = git(root, 'rev-parse', 'HEAD')
git(root, 'switch', '-c', 'topic')
git(root, 'commit', '--allow-empty', '-m', 'feat: topic checkpoint')
git(root, 'switch', 'main')

local function wait_for(check, message)
  assert(vim.wait(5000, check, 20), message)
end

local function window_for(filetype)
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == filetype then return window end
  end
end

local function graph_ready()
  wait_for(function()
    local window = window_for('gitgraph')
    return window and table.concat(vim.api.nvim_buf_get_lines(
      vim.api.nvim_win_get_buf(window), 0, -1, false), '\n'):find(first:sub(1, 8), 1, true)
  end, 'Graph did not restore its commit')
end

assert(graph.open(root, first, true, 'refs/heads/topic'))
graph_ready()
wait_for(function()
  return vim.api.nvim_get_current_line():find('topic', 1, true)
end, 'Branch picker did not load')
local list = window_for('gitgraph')
local branches = window_for('gitbranch')
vim.api.nvim_win_set_width(list, 33)
vim.api.nvim_win_set_height(branches, 4)
vim.api.nvim_set_current_win(list)
assert(graph.focus_preview())
local preview = window_for('gitcommit')
wait_for(function()
  local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(preview), 0, -1, false), '\n')
  return text:find(first, 1, true) and not text:find('loading…', 1, true)
end, 'Preview did not load')
vim.api.nvim_win_set_cursor(preview, { 4, 2 })
assert(graph.close())
local saved = session.read(root)
assert(saved.layout == 'graph' and saved.graph.selected_hash == first
  and saved.graph.history_ref == 'refs/heads/topic' and saved.graph.branches_open,
  'Graph snapshot lost scope, commit, or branch picker')
assert(require('config.state').open('git-view', { scope = 'session', session_id = root }).path == nil,
  'Git session store has a disk path')

-- A different repository starts clean and cannot overwrite the first snapshot.
assert(graph.resume(other))
wait_for(function() return vim.api.nvim_get_current_line():find('feat: initial files', 1, true) end,
  'Second repository did not open')
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'Repository state leaked across roots')
assert(graph.close())
assert(vim.deep_equal(saved, session.read(root)), 'Second repository changed the first snapshot')

assert(graph.resume(root))
graph_ready()
wait_for(function()
  return vim.bo.filetype == 'gitcommit' and vim.api.nvim_win_get_cursor(0)[1] == 4
end, 'Preview focus/cursor did not restore after asynchronous loading')
assert(#vim.api.nvim_tabpage_list_wins(0) == 3
  and vim.api.nvim_win_get_width(window_for('gitgraph')) == 33
  and vim.api.nvim_win_get_height(window_for('gitbranch')) == 4,
  'Graph split dimensions or picker visibility did not restore')

assert(graph.open_detail())
---@return any
local function detail_ready()
  local view = require('diffview.lib').get_current_view()
  return view and view.git_detail_commit and view.update_needed == false
    and view.cur_entry and view.cur_entry.opened and view
end
wait_for(detail_ready, 'Detail did not load')
local view = detail_ready()
local file
for _, entry in ipairs(view.panel:ordered_file_list()) do
  if entry.path == 'b.txt' then file = entry end
end
assert(file, 'Detail fixture is missing b.txt')
view:set_file(file, false)
wait_for(function() return view.cur_entry == file and file.opened end, 'Second detail file did not open')
vim.api.nvim_win_set_height(view.panel.winid, 5)
vim.api.nvim_set_current_win(view.cur_layout.b.id)
vim.api.nvim_win_set_cursor(0, { 3, 1 })
assert(diffview.close())
wait_for(function() return not diffview.is_active() end, 'Detail did not close')
assert(session.read(root).layout == 'detail', 'Detail layout was not saved')
assert(graph.resume(root))
wait_for(function()
  local restored = detail_ready()
  return restored and restored.cur_entry.path == 'b.txt'
    and vim.api.nvim_get_current_win() == restored.cur_layout.b.id
    and vim.api.nvim_win_get_cursor(0)[1] == 3
end, 'Detail did not restore file, code focus, and cursor')
view = detail_ready()
assert(view.git_detail_commit.hash == first and vim.api.nvim_win_get_height(view.panel.winid) == 5,
  'Detail commit or panel height did not restore')
local editor_entries = 0
local return_watch = vim.api.nvim_create_autocmd('TabEnter', {
  callback = function()
    if vim.api.nvim_get_current_tabpage() == editor_tab then
      editor_entries = editor_entries + 1
    end
  end,
})
local detail_tab = view.tabpage
assert(diffview.toggle_history_layout())
assert(graph.is_current(), 'Detail return did not mount the graph immediately')
wait_for(graph.is_active, 'Detail did not return to graph')
graph_ready()
wait_for(function() return not vim.api.nvim_tabpage_is_valid(detail_tab) end,
  'Detail return did not dispose the old Diffview tab')
vim.api.nvim_del_autocmd(return_watch)
assert(editor_entries == 0, 'Detail return exposed the editor/homepage between Git panels')
assert(graph.is_current(), 'Diffview disposal moved focus away from the restored graph')
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Detail return lost the branch picker')
branches = window_for('gitbranch')
vim.api.nvim_set_current_win(branches)
wait_for(function() return vim.api.nvim_get_current_line():find('topic', 1, true) end,
  'Detail return lost the selected branch')
assert(graph.close())
assert(graph.resume(root))
graph_ready()
wait_for(function()
  local window = window_for('gitcommit')
  local text = window and table.concat(vim.api.nvim_buf_get_lines(
    vim.api.nvim_win_get_buf(window), 0, -1, false), '\n') or ''
  return vim.bo.filetype == 'gitbranch' and vim.api.nvim_get_current_line():find('topic', 1, true)
    and text:find('topic checkpoint', 1, true) and not text:find('loading…', 1, true)
end, 'Branch focus, selection, or preview did not restore')
assert(graph.close())

-- Return before the initial file render settles. A late native update must not
-- focus the retired detail panel over the replacement graph.
assert(graph.resume(root))
graph_ready()
vim.api.nvim_set_current_win(window_for('gitgraph'))
assert(graph.open_detail())
local retiring_detail = require('diffview.lib').get_current_view()
assert(diffview.toggle_history_layout())
local returned_tab = vim.api.nvim_get_current_tabpage()
assert(graph.is_current(), 'Early detail return did not mount the graph immediately')
retiring_detail.emitter:emit('files_updated')
assert(vim.api.nvim_get_current_tabpage() == returned_tab,
  'Late file update refocused the retired detail panel')
wait_for(function() return not vim.api.nvim_tabpage_is_valid(retiring_detail.tabpage) end,
  'Early detail return did not dispose its Diffview tab')
graph_ready()
assert(graph.is_current(), 'Initial file render stole focus after early detail return')
assert(graph.close())

-- A deleted review ref falls back to the current checkout without failing open.
git(root, 'branch', '-D', 'topic')
assert(graph.resume(root))
graph_ready()
assert(graph.close())
assert(session.read(root).graph.history_ref == 'HEAD', 'Missing branch did not fall back to HEAD')
vim.fn.delete(workspace, 'rf')
print('Installed Git session tests passed')
