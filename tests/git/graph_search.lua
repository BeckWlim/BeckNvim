local graph = require('config.git.graph')
local original_diffview = package.loaded['config.git.diffview']
local original_search = package.loaded['config.git.search']
local search_call
---@type { succeeded: boolean, detail: string }?
local checkout_finished
package.loaded['config.git.diffview'] = {
  install_quit_command = function() end,
  log_anchor = function() end,
  finish_anchor_operation = function(_, succeeded, detail)
    checkout_finished = { succeeded = succeeded, detail = detail }
  end,
}
package.loaded['config.git.search'] = {
  open = function(root, options, parent, actions)
    search_call = { root = root, options = options, parent = parent, actions = actions }
    return true
  end,
}
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local command = { 'git', '-C', root, '-c', 'commit.gpgsign=false',
    '-c', 'core.hooksPath=/dev/null' }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function wait_for(check, message)
  assert(vim.wait(3000, check, 10), message)
end
local function check()
  git('init', '--initial-branch=main')
  git('config', 'user.name', 'Graph Search Test')
  git('config', 'user.email', 'graph-search@example.invalid')
  vim.fn.writefile({ 'base' }, root .. '/file.txt')
  git('add', '.')
  git('commit', '-m', 'Base')
  local base = git('rev-parse', 'HEAD')
  git('switch', '-c', 'topic')
  vim.fn.writefile({ 'topic' }, root .. '/file.txt')
  git('commit', '-am', 'Topic')
  local topic = git('rev-parse', 'HEAD')
  git('switch', 'main')
  local editor_tab = vim.api.nvim_get_current_tabpage()
  assert(graph.open(root))
  local graph_tab = vim.api.nvim_get_current_tabpage()
  local list = vim.api.nvim_get_current_win()
  assert(graph.search(), 'Graph search requires loaded commit details')
  assert(graph.is_active() and graph_tab == vim.api.nvim_get_current_tabpage()
    and search_call.parent == nil and search_call.options.location.root == root,
    'Opening graph search replaced the graph')
  wait_for(function() return vim.api.nvim_get_current_line():find(base:sub(1, 8), 1, true) end,
    'Graph fixture did not load')
  assert(graph.toggle_branches())
  local branches = vim.api.nvim_get_current_win()
  wait_for(function() return vim.api.nvim_get_current_line():find('main', 1, true) end,
    'Branches did not load')
  vim.api.nvim_win_set_width(list, 31)
  vim.api.nvim_win_set_height(branches, 4)
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(graph_tab)) do
    vim.api.nvim_set_current_win(window)
    local mapping = vim.fn.maparg('<Space>de', 'n', false, true)
    assert(mapping.buffer == 1, 'A graph pane lacks its local search action')
    mapping.callback()
    assert(graph.is_active() and vim.api.nvim_get_current_win() == window,
      'Search changed graph pane focus or layout')
  end
  assert(search_call.actions.commit({ hash = base, history_ref = 'refs/heads/topic' }))
  assert(vim.api.nvim_get_current_win() == list
    and vim.api.nvim_get_current_line():find(base:sub(1, 8), 1, true),
    'Existing commit was not selected in the preserved graph')
  assert(search_call.actions.commit({ hash = topic, history_ref = 'refs/heads/topic' }))
  local preview = vim.api.nvim_get_current_win()
  assert(preview ~= list and preview ~= branches and vim.bo.filetype == 'gitcommit',
    'Off-graph commit did not use the graph preview')
  wait_for(function() return vim.api.nvim_get_current_line() == 'Topic' end,
    'Off-graph preview did not load')
  assert(vim.api.nvim_win_get_buf(list)
    and vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(list)) == 1,
    'Off-graph commit replaced the retained branch history')

  local preview_checkout = vim.fn.maparg('<Space>dm', 'n', false, true)
  assert(preview_checkout.buffer == 1, 'Graph preview lacks guarded checkout')
  vim.fn.writefile({ 'dirty' }, root .. '/untracked.txt')
  preview_checkout.callback()
  wait_for(function() return checkout_finished ~= nil end, 'Dirty checkout did not finish')
  assert(checkout_finished and not checkout_finished.succeeded and git('rev-parse', 'HEAD') == base,
    'Graph checkout ignored the dirty worktree guard')
  vim.fn.delete(root .. '/untracked.txt')

  checkout_finished = nil
  local modified_buffer = vim.fn.bufadd(root .. '/file.txt')
  vim.fn.bufload(modified_buffer)
  vim.api.nvim_buf_set_lines(modified_buffer, 0, -1, false, { 'unsaved edit' })
  preview_checkout.callback()
  wait_for(function() return checkout_finished ~= nil end, 'Modified-buffer checkout did not finish')
  assert(checkout_finished and not checkout_finished.succeeded and git('rev-parse', 'HEAD') == base,
    'Graph checkout ignored modified editor buffers')
  vim.api.nvim_buf_delete(modified_buffer, { force = true })

  checkout_finished = nil
  preview_checkout.callback()
  wait_for(function() return checkout_finished ~= nil end, 'Preview checkout did not finish')
  assert(checkout_finished and checkout_finished.succeeded and git('rev-parse', 'HEAD') == topic
    and graph.is_active() and vim.api.nvim_get_current_win() == preview
    and vim.api.nvim_get_current_tabpage() == graph_tab
    and vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(list)) == 1,
    'Preview checkout lost the graph, reviewed branch, or selected target')

  vim.api.nvim_set_current_win(list)
  checkout_finished = nil
  local list_checkout = vim.fn.maparg('<Space>dm', 'n', false, true)
  assert(list_checkout.buffer == 1, 'Graph commit list lacks guarded checkout')
  list_checkout.callback()
  wait_for(function() return checkout_finished ~= nil end, 'List checkout did not finish')
  assert(checkout_finished and checkout_finished.succeeded and git('rev-parse', 'HEAD') == base
    and vim.api.nvim_get_current_win() == list,
    'List checkout used the preview commit or changed graph focus')

  assert(search_call.actions.branch({ refname = 'refs/heads/topic', tip_commit = topic }))
  wait_for(function() return vim.api.nvim_get_current_line():find(topic:sub(1, 8), 1, true) end,
    'Search branch selection did not review its graph')
  assert(graph_tab == vim.api.nvim_get_current_tabpage()
    and #vim.api.nvim_tabpage_list_wins(graph_tab) == 3
    and vim.api.nvim_win_get_width(list) == 31
    and vim.api.nvim_win_get_height(branches) == 4,
    'Search review lost the graph tab, branch pane, or dimensions')
  assert(git('rev-parse', 'HEAD') == base, 'Search changed checkout')
  -- Closing the owner while validation is pending must prevent the mutation.
  local repository = require('config.git.repository')
  local original_start = repository.start
  local pending_resolution
  rawset(repository, 'start', function(command, directory, callback)
    if vim.tbl_contains(command, 'rev-parse') then
      pending_resolution = callback
      return function() end
    end
    return original_start(command, directory, callback)
  end)
  assert(graph.checkout_selected_commit() and pending_resolution)
  local actions = search_call.actions
  assert(graph.close() and vim.api.nvim_get_current_tabpage() == editor_tab)
  rawset(repository, 'start', original_start)
  checkout_finished = nil
  pending_resolution({ code = 0, stdout = topic .. '\n' })
  assert(checkout_finished and not checkout_finished.succeeded
    and git('rev-parse', 'HEAD') == base, 'Retired graph checkout changed HEAD')
  assert(not actions.is_current() and not actions.commit({ hash = base })
    and not actions.branch({ refname = 'main' }), 'Search dispatched into a retired graph')
end
local succeeded, failure = xpcall(check, debug.traceback)
if graph.is_active() then graph.close() end
package.loaded['config.git.diffview'] = original_diffview
package.loaded['config.git.search'] = original_search
vim.fn.delete(root, 'rf')
assert(succeeded, failure)
print('Git graph search tests passed')
