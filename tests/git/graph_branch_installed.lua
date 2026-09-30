-- Run with: nvim --headless -u init.lua -i NONE '+luafile tests/git/graph_branch_installed.lua' '+qa!'
local workspace = vim.fn.tempname()
local origin = workspace .. '/origin.git'
local checkout = workspace .. '/checkout'
vim.fn.mkdir(workspace, 'p')

local function git(command, cwd)
  local result = vim.system(command, { cwd = cwd, text = true }):wait()
  assert(result.code == 0, table.concat(command, ' ') .. ': ' .. (result.stderr or ''))
  return vim.trim(result.stdout or '')
end

git({ 'git', 'init', '--bare', '--initial-branch=main', origin })
git({ 'git', 'clone', origin, checkout })
git({ 'git', 'config', 'user.name', 'Graph Test' }, checkout)
git({ 'git', 'config', 'user.email', 'graph@example.invalid' }, checkout)
vim.fn.writefile({ 'base' }, checkout .. '/file.txt')
git({ 'git', 'add', 'file.txt' }, checkout)
git({ 'git', 'commit', '-m', 'Base commit' }, checkout)
local base_hash = git({ 'git', 'rev-parse', 'HEAD' }, checkout)
git({ 'git', 'push', '-u', 'origin', 'main' }, checkout)
git({ 'git', 'switch', '-c', 'topic' }, checkout)
vim.fn.writefile({ 'topic' }, checkout .. '/topic.txt')
git({ 'git', 'add', 'topic.txt' }, checkout)
local tagged_subject = '[Bugfix][Store] Return failure from PushOffloadingQueue on no-op enqueue (#3726)'
git({ 'git', 'commit', '-m', tagged_subject }, checkout)
local topic_hash = git({ 'git', 'rev-parse', 'HEAD' }, checkout)
git({ 'git', 'switch', 'main' }, checkout)
git({ 'git', 'merge', '--no-ff', 'topic', '-m', 'Merge topic' }, checkout)
local merge_hash = git({ 'git', 'rev-parse', 'HEAD' }, checkout)
git({ 'git', 'push', 'origin', 'main' }, checkout)
git({ 'git', 'switch', '-c', 'feature' }, checkout)
git({ 'git', 'commit', '--allow-empty', '-m', 'Empty checkpoint' }, checkout)
local empty_hash = git({ 'git', 'rev-parse', 'HEAD' }, checkout)
vim.fn.writefile({ 'feature' }, checkout .. '/file.txt')
git({ 'git', 'commit', '-am', 'Feature commit' }, checkout)
git({ 'git', 'push', '-u', 'origin', 'feature' }, checkout)
git({ 'git', 'switch', 'main' }, checkout)
git({ 'git', 'branch', '-D', 'feature' }, checkout)
local feature_hash = git({ 'git', 'rev-parse', 'refs/remotes/origin/feature' }, checkout)

local graph = require('config.git.graph')
for _, case in ipairs({
  { hash = topic_hash, path = 'topic.txt', pane = 'file' },
  { hash = topic_hash, path = 'topic.txt', pane = 'code' },
  { hash = base_hash, path = 'file.txt', pane = 'file' },
  { hash = merge_hash, path = 'topic.txt', pane = 'file' },
  { hash = feature_hash, path = 'file.txt', pane = 'file' },
  { hash = empty_hash, pane = 'file' },
}) do
  assert(graph.open(checkout, case.hash, nil, 'refs/remotes/origin/feature'))
  assert(vim.wait(5000, function()
    return vim.api.nvim_get_current_line():find(case.hash:sub(1, 8), 1, true)
  end, 20), 'Graph did not select the requested commit')
  if case.hash == topic_hash then
    local preview_buffer
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buffer = vim.api.nvim_win_get_buf(window)
      if vim.bo[buffer].filetype == 'gitcommit' then preview_buffer = buffer end
    end
    assert(vim.wait(5000, function()
      return vim.api.nvim_buf_get_lines(preview_buffer, 0, 1, false)[1] == tagged_subject
    end, 20), 'Historical preview lost the full subject')
    vim.api.nvim_buf_call(preview_buffer, function()
      for _, column in ipairs({ 1, 49, 50, 51, #tagged_subject }) do
        assert(vim.fn.synIDattr(vim.fn.synID(1, column, 1), 'name') == 'gitcommitSummary',
          'Historical subject color stopped at column ' .. column)
      end
    end)
  end
  assert(graph.open_detail(), 'Commit detail did not open')
  local detail_view = require('diffview.lib').get_current_view()
  assert(detail_view and detail_view.git_detail_commit.hash == case.hash
    and detail_view.rev_arg == case.hash .. '^!'
    and detail_view.right.commit == case.hash
    and not detail_view.panel.entries and not detail_view.git_footer_loader
    and detail_view.git_graph_return.history_ref == 'refs/remotes/origin/feature',
    'Detail view did not use an exact native diff with no history loader')
  assert(vim.wait(5000, function()
    return detail_view.update_needed == false
      and detail_view.files:len() == (case.path and 1 or 0)
  end, 20), 'Commit detail did not load its changed-file set')
  local detail_panel = detail_view.panel
  local panel_highlights = vim.wo[detail_panel.winid].winhl
  assert(panel_highlights:find('WinBar:Normal', 1, true)
    and panel_highlights:find('WinBarNC:Normal', 1, true)
    and panel_highlights:find('Normal:DiffviewNormal', 1, true),
    'Detail title does not share the editor background while retaining native panel highlights')
  assert(vim.bo[detail_panel.bufid].filetype == 'DiffviewFiles'
    and detail_panel.listing_style == 'list'
    and vim.api.nvim_win_get_position(detail_panel.winid)[1]
      > vim.api.nvim_win_get_position(detail_view.cur_layout.b.id)[1],
    'Detail footer is not the native flat file list below the diffs')
  if case.hash == merge_hash then
    assert(detail_view.left.commit == base_hash, 'Merge detail did not compare the first parent')
  end
  if case.path then
    assert(detail_view.files[1].path == case.path, "Detail includes another commit's files")
    vim.api.nvim_set_current_win(detail_panel.winid)
    detail_panel:highlight_file(detail_view.files[1])
    vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'mx', false)
    assert(vim.wait(5000, function()
      return detail_view.cur_entry and detail_view.cur_entry.path == case.path
        and detail_view.cur_entry.opened
    end, 20), "Enter did not open the current commit's file")
  end
  if case.hash == topic_hash then
    local title = vim.wo[detail_panel.winid].winbar
    assert(title:find('%#DiagnosticError#[Bugfix]', 1, true)
      and title:find('%#Identifier#[Store]', 1, true),
      'Detail header lost the shared bracket-tag colors')
  end
  if case.pane == 'code' then
    vim.api.nvim_set_current_win(detail_view.cur_layout.b.id)
  end
  assert(require('config.git.diffview').toggle_history_layout())
  assert(vim.wait(5000, function()
    return graph.is_active() and vim.api.nvim_get_current_line():find(case.hash:sub(1, 8), 1, true)
  end, 20), 'Detail-to-graph toggle lost its selected commit')
  graph.close()
end

-- A branch-tip preview can differ from the commit cursor in the graph.
assert(graph.open(checkout, nil, true))
assert(vim.wait(5000, function()
  return vim.bo.filetype == 'gitbranch' and vim.api.nvim_get_current_line() ~= 'Loading branches…'
end, 20))
assert(vim.fn.maparg('<Space>dv', 'n', false, true).buffer ~= 1,
  'Branch picker gained a commit-detail binding')
for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if line:find('Feature commit', 1, true) then
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    break
  end
end
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'gitcommit' then
    vim.api.nvim_set_current_win(window)
    break
  end
end
assert(vim.wait(5000, function()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find(feature_hash, 1, true)
end, 20))
vim.api.nvim_feedkeys(vim.keycode('<Space>dv'), 'mx', false)
local preview_detail = require('diffview.lib').get_current_view()
assert(preview_detail and preview_detail.git_detail_commit.hash == feature_hash
  and preview_detail.git_graph_return.history_ref == 'refs/remotes/origin/feature',
  'Preview detail used the graph cursor instead of the displayed remote commit')
assert(require('config.git.diffview').toggle_history_layout())
assert(vim.wait(5000, function()
  return graph.is_active() and vim.api.nvim_get_current_line():find(feature_hash:sub(1, 8), 1, true)
end, 20))
graph.close()

assert(graph.open(checkout, nil, true), 'Graph did not open branch fixture')
local list_window
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'gitgraph' then
    list_window = window
    break
  end
end
assert(list_window, 'Commit graph window is missing')
local list_buffer = vim.api.nvim_win_get_buf(list_window)
local graph_namespace = vim.api.nvim_get_namespaces()['config-git-graph-list']
local function row_badges(row_number)
  local parts = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
    list_buffer, graph_namespace, 0, -1, { details = true })) do
    if mark[2] == row_number - 1 and mark[4].virt_text then
      assert(mark[4].virt_text_pos == 'right_align',
        'Commit badge is not aligned to the right edge')
      for _, chunk in ipairs(mark[4].virt_text) do
        parts[#parts + 1] = chunk[1]
      end
    end
  end
  return table.concat(parts)
end
assert(vim.wait(5000, function()
  local selected_row = vim.api.nvim_win_get_cursor(list_window)[1]
  return row_badges(selected_row):find('[HEAD]', 1, true)
    and vim.wo[list_window].winbar:find('Git main', 1, true)
end, 20), 'Current branch is not pinned in the header or selected as HEAD')
local default_list = table.concat(vim.api.nvim_buf_get_lines(
  list_buffer, 0, -1, false), '\n')
assert(not default_list:find(feature_hash:sub(1, 8), 1, true)
  and not default_list:find('Feature commit', 1, true),
  'Default history still includes commits reachable only from another branch')
assert(default_list:find(topic_hash:sub(1, 8), 1, true)
  and default_list:find('◆', 1, true)
  and (default_list:find('╲', 1, true) or default_list:find('╱', 1, true)),
  'Merged branch topology is missing from the current branch history')
local topic_row
for index, line in ipairs(vim.api.nvim_buf_get_lines(list_buffer, 0, -1, false)) do
  if line:find(topic_hash:sub(1, 8), 1, true) then topic_row = index end
end
assert(topic_row and row_badges(topic_row):find('[topic]', 1, true),
  'Merged branch ref is missing from its commit row')
assert(vim.wait(5000, function()
  local selected_row = vim.api.nvim_win_get_cursor(list_window)[1]
  return row_badges(selected_row):find('[feature↗]', 1, true) ~= nil
end, 20), 'Unmerged feature branch was not marked at its fork commit')
assert(vim.wait(5000, function()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= 'Loading branches…'
end, 20), 'Branch list did not load')
local main_hash = git({ 'git', 'rev-parse', 'refs/heads/main' }, checkout)
git({ 'git', 'update-ref', 'refs/heads/fetched', main_hash }, origin)
local old_tab = vim.api.nvim_get_current_tabpage()
vim.api.nvim_feedkeys('f', 'mx', false)
assert(vim.wait(5000, function()
  return vim.system({ 'git', 'show-ref', '--verify', 'refs/remotes/origin/fetched' },
    { cwd = checkout }):wait().code == 0
end, 20), 'Branch fetch did not update the remote-tracking refs')
assert(vim.wait(5000, function()
  return vim.api.nvim_get_current_tabpage() ~= old_tab
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= 'Loading branches…'
end, 20), 'Branch pane did not reopen after fetching')
local branch_window = vim.api.nvim_get_current_win()
local branch_buffer = vim.api.nvim_win_get_buf(branch_window)
local branch_lines = vim.api.nvim_buf_get_lines(branch_buffer, 0, -1, false)
local remote_row
for index, line in ipairs(branch_lines) do
  if line:find('REMOTE', 1, true) and line:find('Feature commit', 1, true) then
    remote_row = index
  end
end
assert(remote_row, 'Remote feature branch is missing')
vim.api.nvim_win_set_cursor(branch_window, { remote_row, 0 })
vim.fn.writefile({ 'work in progress during remote review' }, checkout .. '/file.txt')
local dirty_status = git({ 'git', 'status', '--porcelain' }, checkout)
local review_tab = vim.api.nvim_get_current_tabpage()
local review_windows = vim.api.nvim_tabpage_list_wins(0)
local review_list_window
for _, window in ipairs(review_windows) do
  if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'gitgraph' then
    review_list_window = window
  end
end
local branch_height = vim.api.nvim_win_get_height(branch_window)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'mx', false)
assert(vim.wait(5000, function()
  local row = vim.api.nvim_win_get_cursor(review_list_window)[1]
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(review_list_window), row - 1, row, false)[1]
    :find(feature_hash:sub(1, 8), 1, true)
end, 20), 'Enter did not review the remote branch history')
assert(vim.api.nvim_get_current_tabpage() == review_tab
  and vim.deep_equal(vim.api.nvim_tabpage_list_wins(0), review_windows)
  and vim.api.nvim_get_current_win() == branch_window
  and vim.api.nvim_win_get_height(branch_window) == branch_height
  and vim.api.nvim_win_get_cursor(branch_window)[1] == remote_row,
  'Branch review changed the layout, picker selection, or focus')
local review_mapping = vim.fn.maparg('o', 'n', false, true)
for index, line in ipairs(branch_lines) do
  if line:find('LOCAL  main', 1, true) then
    vim.api.nvim_win_set_cursor(branch_window, { index, 0 })
    review_mapping.callback()
    break
  end
end
vim.api.nvim_win_set_cursor(branch_window, { remote_row, 0 })
review_mapping.callback()
assert(vim.wait(5000, function()
  local row = vim.api.nvim_win_get_cursor(review_list_window)[1]
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(review_list_window), row - 1, row, false)[1]
    :find(feature_hash:sub(1, 8), 1, true)
end, 20) and vim.deep_equal(vim.api.nvim_tabpage_list_wins(0), review_windows),
  'Rapid branch reviews lost the final selection or rebuilt the layout')
assert(git({ 'git', 'branch', '--show-current' }, checkout) == 'main'
  and git({ 'git', 'status', '--porcelain' }, checkout) == dirty_status
  and vim.system({ 'git', 'show-ref', '--verify', 'refs/heads/feature' },
    { cwd = checkout }):wait().code ~= 0,
  'Remote review changed HEAD, the worktree, or local tracking branches')
vim.fn.writefile({ 'base' }, checkout .. '/file.txt')
vim.api.nvim_set_current_win(review_list_window)
for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if line:find(topic_hash:sub(1, 8), 1, true) then
    vim.api.nvim_win_set_cursor(0, { index, 0 })
    break
  end
end
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
assert(graph.open_detail(), 'Reviewed remote branch did not open details')
assert(vim.wait(5000, function()
  local view = require('diffview.lib').get_current_view()
  return view and view.git_history_options
    and view.git_history_options.revision == topic_hash
    and view.git_graph_return.history_ref == 'refs/remotes/origin/feature'
    and view.git_detail_commit.hash == topic_hash
end, 20), 'Layout toggle replaced the reviewed remote scope with the checked-out branch')
assert(require('config.git.diffview').toggle_history_layout())
assert(vim.wait(5000, function()
  return graph.is_active() and vim.api.nvim_get_current_line():find(topic_hash:sub(1, 8), 1, true)
end, 20), 'Remote review did not retain its selected commit on return')
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Detail return lost the branch picker')
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'gitbranch' then
    vim.api.nvim_set_current_win(window)
    break
  end
end
assert(vim.wait(5000, function()
  return vim.bo.filetype == 'gitbranch'
    and vim.api.nvim_get_current_line():find('Feature commit', 1, true)
end, 20), 'Branch selector did not retain the reviewed remote ref')
local reviewed_tab = vim.api.nvim_get_current_tabpage()
vim.api.nvim_feedkeys('f', 'mx', false)
assert(vim.wait(5000, function()
  return vim.api.nvim_get_current_tabpage() ~= reviewed_tab
    and vim.bo.filetype == 'gitbranch'
    and vim.api.nvim_get_current_line():find('Feature commit', 1, true)
end, 20), 'Fetch lost the reviewed branch scope or branch selection')
local switch_mapping = vim.fn.maparg('<Space>dm', 'n', false, true)
assert(switch_mapping.buffer == 1 and switch_mapping.callback,
  'Branch mutation does not use the established checkout binding')
switch_mapping.callback()
assert(vim.wait(5000, function()
  return git({ 'git', 'branch', '--show-current' }, checkout) == 'feature'
end, 20), '<Space>dm did not create the local tracking branch')
assert(git({ 'git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }, checkout)
  == 'origin/feature', 'Tracked branch has the wrong upstream')
assert(graph.is_active(), 'Graph did not reopen after branch switch')
assert(vim.wait(5000, function()
  local current = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(current) do
    if line:find('● LOCAL  feature', 1, true) then return true end
  end
  return false
end, 20), 'Branch pane did not refresh after tracking')
vim.fn.writefile({ 'unsaved worktree change' }, checkout .. '/file.txt')
local main_row
for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if line:find('LOCAL  main', 1, true) then main_row = index end
end
assert(main_row, 'Local main branch is missing')
vim.api.nvim_win_set_cursor(0, { main_row, 0 })
vim.fn.maparg('<Space>dm', 'n', false, true).callback()
vim.wait(400, function() return false end, 20)
assert(git({ 'git', 'branch', '--show-current' }, checkout) == 'feature',
  'Dirty worktree was switched to another branch')
graph.close()
vim.fn.writefile({ 'feature' }, checkout .. '/file.txt')
assert(graph.open(checkout, topic_hash, nil, 'refs/remotes/origin/feature'))
assert(vim.wait(5000, function()
  return vim.api.nvim_get_current_line():find(topic_hash:sub(1, 8), 1, true)
end, 20))
assert(graph.open_detail())
local checkout_detail = require('diffview.lib').get_current_view()
assert(vim.wait(5000, function() return checkout_detail.update_needed == false end, 20))
assert(require('config.git.diffview').checkout_selected_commit())
assert(vim.wait(5000, function()
  return git({ 'git', 'rev-parse', 'HEAD' }, checkout) == topic_hash
    and checkout_detail.git_detached_head_commit == topic_hash
end, 20), 'Detail checkout did not complete')
assert(require('diffview.lib').get_current_view() == checkout_detail
  and checkout_detail.git_detail_commit.hash == topic_hash
  and not checkout_detail.panel.entries,
  'Checkout rebuilt branch history instead of retaining the commit file panel')
assert(require('config.git.diffview').toggle_history_layout())
assert(vim.wait(5000, function()
  return graph.is_active() and vim.api.nvim_get_current_line():find(topic_hash:sub(1, 8), 1, true)
end, 20))
graph.close()
vim.fn.delete(workspace, 'rf')
print('Installed Git branch tracking tests passed')
