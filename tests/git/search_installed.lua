-- nvim --headless -u NONE -i NONE -l tests/git/search_installed.lua
local workspace = vim.fn.tempname()
local root = workspace .. '/repository'
vim.fn.mkdir(root, 'p')
local function git(...)
  local command = { 'git', '-C', root, '-c', 'commit.gpgsign=false',
    '-c', 'core.hooksPath=/dev/null' }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
git('init', '--initial-branch=main')
git('config', 'user.name', 'Search Test')
git('config', 'user.email', 'search@example.invalid')
vim.fn.writefile({ 'base' }, root .. '/file.txt')
git('add', '.')
git('commit', '-m', 'Base')
local base = git('rev-parse', 'HEAD')
vim.fn.writefile({ 'main' }, root .. '/file.txt')
git('commit', '-am', 'Main')
local main = git('rev-parse', 'HEAD')
git('switch', '-c', 'topic')
vim.fn.writefile({ 'topic' }, root .. '/file.txt')
git('commit', '-am', 'Topic')
local topic = git('rev-parse', 'HEAD')
git('switch', 'main')

local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = workspace, XDG_CACHE_HOME = workspace .. '/cache' } })
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function wait_for(source, message)
  if not vim.wait(5000, function() return evaluate(source) end, 10) then
    error(message .. '\n' .. evaluate([[return vim.api.nvim_exec2('messages', { output = true }).output]]))
  end
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
  vim.wait(30)
end
local function search(query)
  input(' de')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt']], 'Space-de did not open search')
  evaluate([[vim.g.git_search_prompt = vim.api.nvim_get_current_buf()]])
  if query then input(query) end
end
local function select_result(kind)
  evaluate([[
    local wanted = ...
    local picker = require('telescope.actions.state').get_current_picker(vim.g.git_search_prompt)
    local index = 0
    for entry in picker.manager:iter() do
      if entry.kind == wanted then
        picker:set_selection(index)
        require('telescope.actions').select_default(vim.g.git_search_prompt)
        return
      end
      index = index + 1
    end
    error('Missing result: ' .. wanted)
  ]], { kind })
end
local function expect_graph()
  evaluate([[
    assert(require('config.git.graph').is_current(), 'Search changed the graph layout')
    assert(not require('config.git.diffview').is_active(), 'Search mounted Diffview')
    assert(vim.api.nvim_get_current_tabpage() == vim.g.git_search_tab, 'Search replaced the graph tab')
    assert(vim.deep_equal(vim.api.nvim_tabpage_list_wins(0), vim.g.git_search_windows),
      'Search lost or replaced graph panes')
  ]])
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  evaluate([[
    local directory, history = ...
    vim.cmd.cd(directory)
    require('telescope').setup({ defaults = { history = { path = history } } })
    assert(require('config.git.graph').open(directory))
  ]], { root, workspace .. '/history' })
  wait_for([[return vim.api.nvim_get_current_line():find('Main', 1, true) ~= nil]], 'Graph did not load')
  evaluate([[
    vim.g.git_search_tab = vim.api.nvim_get_current_tabpage()
    vim.g.git_search_list = vim.api.nvim_get_current_win()
    assert(require('config.git.graph').toggle_branches())
  ]])
  wait_for([[return vim.bo.filetype == 'gitbranch' and vim.api.nvim_get_current_line() ~= 'Loading branches…']],
    'Branches did not load')
  evaluate([[vim.g.git_search_windows = vim.api.nvim_tabpage_list_wins(0)]])
  local windows = evaluate([[return vim.g.git_search_windows]])
  for _, window in ipairs(windows) do
    evaluate([[
      vim.api.nvim_set_current_win(...)
      vim.g.git_search_cursor = vim.api.nvim_win_get_cursor(0)
      vim.g.git_search_source_window = vim.api.nvim_get_current_win()
    ]], { window })
    search()
    evaluate([[
      assert(require('config.git.graph').is_active() and not require('config.git.diffview').is_active())
    ]])
    input('<C-q>')
    wait_for([[return vim.api.nvim_get_current_win() == vim.g.git_search_source_window]],
      'Search cancellation lost the source pane')
    expect_graph()
    evaluate([[assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), vim.g.git_search_cursor))]])
  end

  evaluate([[vim.api.nvim_set_current_win(vim.g.git_search_list)]])
  search(base:sub(1, 8))
  wait_for([[
    local entry = require('telescope.actions.state').get_selected_entry()
    return entry and entry.kind == 'commit_id'
  ]], 'Commit ID result did not appear')
  select_result('commit_id')
  wait_for(('return vim.api.nvim_get_current_line():find(%q, 1, true) ~= nil'):format(base:sub(1, 8)),
    'Commit search did not select the graph row')
  expect_graph()

  search(topic:sub(1, 8))
  wait_for([[local e = require('telescope.actions.state').get_selected_entry(); return e and e.kind == 'commit_id']],
    'Off-graph commit result did not appear')
  select_result('commit_id')
  wait_for([[return vim.bo.filetype == 'gitcommit' and vim.api.nvim_get_current_line() == 'Topic']],
    'Off-graph search did not use the graph preview')
  expect_graph()

  search('topic')
  wait_for([[local e = require('telescope.actions.state').get_selected_entry(); return e and e.kind == 'branch']],
    'Branch result did not appear')
  select_result('branch')
  wait_for(('return vim.bo.filetype == "gitgraph" and vim.api.nvim_get_current_line():find(%q, 1, true) ~= nil')
    :format(topic:sub(1, 8)), 'Branch search did not review the graph in place')
  expect_graph()
  assert(git('symbolic-ref', '--short', 'HEAD') == 'main' and git('rev-parse', 'HEAD') == main,
    'Search changed the checkout')

  evaluate([[
    require('config.git.github').fetch_issue = function(_, number, callback)
      vim.schedule(function()
        callback({ author = 'test', body = 'Issue fixture', comments = 0,
          created_at = '', updated_at = '', discussion = {}, discussion_complete = true,
          html_url = 'https://github.com/example/test/issues/' .. number,
          kind = 'Issue', labels = {}, number = tonumber(number), state = 'open', title = 'Fixture' }, nil)
      end)
      return function() end
    end
  ]])
  search('#23')
  wait_for([[
    local p = require('telescope.actions.state').get_current_picker(vim.g.git_search_prompt)
    if not p.manager then return false end
    for e in p.manager:iter() do if e.kind == 'issue' then return true end end
    return false
  ]], 'Issue result did not appear')
  select_result('issue')
  wait_for([[return vim.b.git_issue_number == '23']], 'Issue detail did not open')
  evaluate([[
    assert(require('config.git.graph').is_active())
    assert(not package.loaded['diffview.lib'] or not require('diffview.lib').get_current_view(),
      'Issue selection mounted native Diffview over the graph')
  ]])
  input(' de')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt']], 'Issue did not return to search')
  input('<C-q>')
  expect_graph()

  evaluate([[
    require('config.git').on('anchor_finished', function(event)
      vim.g.git_search_anchor_finished = event.succeeded
    end)
    vim.api.nvim_set_current_win(vim.g.git_search_list)
  ]])
  input(' dm')
  wait_for([[return vim.g.git_search_anchor_finished == true]], 'Graph list checkout did not finish')
  assert(git('rev-parse', 'HEAD') == topic, 'Graph list checkout chose a different commit')
  expect_graph()
  search(base:sub(1, 8))
  wait_for([[local e = require('telescope.actions.state').get_selected_entry(); return e and e.kind == 'commit_id']],
    'Checkout preview target did not appear')
  select_result('commit_id')
  wait_for(('return vim.api.nvim_get_current_line():find(%q, 1, true) ~= nil'):format(base:sub(1, 8)),
    'Checkout preview target was not selected')
  evaluate([[
    assert(require('config.git.graph').focus_preview())
    vim.g.git_search_anchor_finished = false
  ]])
  input(' dm')
  wait_for([[return vim.g.git_search_anchor_finished == true]], 'Graph preview checkout did not finish')
  assert(git('rev-parse', 'HEAD') == base, 'Graph preview checkout chose a different commit')
  expect_graph()

  evaluate([[
    vim.api.nvim_set_current_win(vim.g.git_search_list)
    assert(require('config.git.graph').open_detail(), vim.api.nvim_exec2('messages', { output = true }).output)
  ]])
  wait_for([[
    local v = require('diffview.lib').get_current_view()
    if not (v and v.git_detail_commit and v.cur_entry and v.cur_entry.opened and not v.update_needed) then
      return false
    end
    vim.g.git_search_detail_tab = v.tabpage
    vim.g.git_search_detail_file = v.cur_entry.path
    vim.g.git_search_detail_windows = vim.api.nvim_tabpage_list_wins(0)
    vim.g.git_search_detail_source = vim.api.nvim_get_current_win()
    return true
  ]], 'Detail did not render')
  search()
  input('<C-q>')
  wait_for([[return vim.api.nvim_get_current_win() == vim.g.git_search_detail_source]],
    'Detail search cancellation lost focus')
  evaluate([[
    local v = require('diffview.lib').get_current_view()
    assert(v.git_detail_commit and v.tabpage == vim.g.git_search_detail_tab
      and v.cur_entry.path == vim.g.git_search_detail_file
      and vim.deep_equal(vim.api.nvim_tabpage_list_wins(0), vim.g.git_search_detail_windows),
      'Search changed the detail selection or panes')
    vim.g.git_search_anchor_finished = false
  ]])
  input(' dm')
  wait_for([[return vim.g.git_search_anchor_finished == true]], 'Detail checkout did not finish')
  assert(git('rev-parse', 'HEAD') == base, 'Detail checkout changed the target unexpectedly')
  evaluate([[
    local v = require('diffview.lib').get_current_view()
    assert(v.git_detail_commit and v.tabpage == vim.g.git_search_detail_tab,
      'Detail checkout replaced the active layout')
    local repository = require('config.git.repository')
    local start = repository.start
    rawset(repository, 'start', function(command, directory, callback)
      if vim.tbl_contains(command, 'rev-parse') then
        _G.git_search_pending_resolution = callback
        return function() end
      end
      return start(command, directory, callback)
    end)
    vim.g.git_search_anchor_finished = true
    assert(require('config.git.diffview').checkout_selected_commit())
    rawset(repository, 'start', start)
    assert(require('config.git.diffview').toggle_history_layout())
  ]])
  wait_for([[return require('config.git.graph').is_current() and not require('config.git.diffview').is_active()]],
    'Pending detail checkout prevented returning to graph')
  evaluate([[
    local hash = ...
    _G.git_search_pending_resolution({ code = 0, stdout = hash .. '\n' })
    _G.git_search_pending_resolution = nil
  ]], { base })
  wait_for([[return vim.g.git_search_anchor_finished == false]], 'Retired detail checkout did not cancel')
  assert(git('rev-parse', 'HEAD') == base, 'Retired detail checkout changed HEAD')
  evaluate([[
    assert(require('config.git.graph').is_current() and not require('config.git.diffview').is_active(),
      'Delayed detail checkout replaced the returned graph')
    assert(require('config.git.graph').close())
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(workspace, 'rf')
assert(passed, failure)
print('Installed Git graph/detail search and return tests passed')
