-- Exercise real resize events and nvim-tree file opens in an attached UI.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.fn.writefile({ 'first' }, directory .. '/first.txt')
vim.fn.writefile({ 'second' }, directory .. '/second.txt')
local function git(arguments)
  local command = { 'git', '-C', directory }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
end
git({ 'init', '-q' })
git({ 'add', '.' })
local commit_options = { '-c', 'user.name=Window Test', '-c', 'user.email=window@example.invalid',
  '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qam' }
git(vim.list_extend(vim.deepcopy(commit_options), { 'initial' }))
vim.fn.writefile({ 'first changed' }, directory .. '/first.txt')
vim.fn.writefile({ 'second changed' }, directory .. '/second.txt')
git(vim.list_extend(vim.deepcopy(commit_options), { 'changed' }))
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' },
  { rpc = true, env = {
    XDG_STATE_HOME = directory .. '/.git/state', XDG_CACHE_HOME = directory .. '/.git/cache',
  } })
local function evaluate(source)
  local result = vim.rpcrequest(child, 'nvim_exec_lua', source, { directory })
  return result
end
local function settle()
  vim.wait(150, function() return false end, 10)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Editor opened a blocking prompt')
  evaluate('return true')
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  settle()
  evaluate([[
    local directory = ...
    vim.cmd.edit(directory .. '/first.txt')
    vim.cmd.vsplit(directory .. '/second.txt')
    _G.editor_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(editor_window, 45)
    require('nvim-tree.api').tree.open({ path = directory })
    _G.tree_window = require('nvim-tree.api').tree.winid()
    vim.api.nvim_win_set_width(tree_window, 16)
  ]])
  settle()
  evaluate([[
    _G.saved_widths = {}
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      saved_widths[winid] = vim.api.nvim_win_get_width(winid)
    end
    local api = require('nvim-tree.api')
    api.tree.find_file({ buf = (...) .. '/second.txt', open = true, focus = true })
    api.node.open.no_window_picker()
    assert(vim.api.nvim_buf_get_name(0):match('/second.txt$'), 'Tree did not open selected file')
    for winid, width in pairs(saved_widths) do
      assert(vim.api.nvim_win_get_width(winid) == width, 'File open reset a split width')
    end
    vim.api.nvim_set_current_win(editor_window)
    vim.cmd.split()
    _G.bottom_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(bottom_window, 12)
  ]])
  settle()
  local original = evaluate([[
    return { tree = vim.api.nvim_win_get_width(tree_window),
      editor = vim.api.nvim_win_get_width(editor_window),
      height = vim.api.nvim_win_get_height(bottom_window) }
  ]])
  vim.rpcrequest(child, 'nvim_ui_try_resize', 240, 70)
  settle()
  local resized = evaluate([[
    return { tree = vim.api.nvim_win_get_width(tree_window),
      editor = vim.api.nvim_win_get_width(editor_window),
      height = vim.api.nvim_win_get_height(bottom_window) }
  ]])
  assert(math.abs(resized.tree - original.tree * 1.5) <= 1, vim.inspect({ original, resized }))
  assert(math.abs(resized.editor - original.editor * 1.5) <= 2, 'Nested editor width lost its ratio')
  assert(math.abs(resized.height - original.height * 1.4) <= 2, 'Nested split height lost its ratio')
  evaluate([[
    vim.api.nvim_win_set_width(tree_window, 36)
    vim.cmd('tabnew')
    vim.cmd.vsplit()
    _G.other_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(other_window, 80)
  ]])
  settle()
  vim.rpcrequest(child, 'nvim_ui_try_resize', 160, 50)
  settle()
  evaluate([[
    assert(math.abs(vim.api.nvim_win_get_width(other_window) - 53) <= 2,
      'Second tab lost its independent proportion')
    vim.cmd.tabprevious()
  ]])
  settle()
  evaluate([[
    assert(math.abs(vim.api.nvim_win_get_width(tree_window) - 24) <= 1,
      'Inactive tab lost its latest manual proportion')
    local width = vim.api.nvim_win_get_width(tree_window)
    local buffer = vim.api.nvim_create_buf(false, true)
    local float = vim.api.nvim_open_win(buffer, true, {
      relative = 'editor', row = 2, col = 2, width = 30, height = 8, style = 'minimal',
    })
    vim.api.nvim_win_close(float, true)
    assert(vim.api.nvim_win_get_width(tree_window) == width, 'Float changed tiled proportions')
    vim.api.nvim_set_current_win(bottom_window)
    vim.cmd('wincmd =')
  ]])
  settle()
  evaluate([[
    _G.equalized_width = vim.api.nvim_win_get_width(editor_window)
    vim.cmd.edit((...) .. '/first.txt')
    assert(vim.api.nvim_win_get_width(editor_window) == equalized_width,
      'Explicit equalization was undone by a file open')
    vim.api.nvim_win_close(bottom_window, true)
  ]])
  settle()
  vim.rpcrequest(child, 'nvim_ui_try_resize', 200, 60)
  settle()
  evaluate([[
    assert(not vim.api.nvim_win_is_valid(bottom_window), 'Closed pane was restored')
    assert(not vim.api.nvim_get_mode().blocking, 'Window lifecycle raised a blocking error')
    assert(vim.fn.maparg('<Tab>', 'n') ~= '', 'Startup lost window navigation')
  ]])
  evaluate([[
    require('nvim-tree.api').tree.close()
    require('nvim-tree.api').tree.open()
    _G.tree_window = require('nvim-tree.api').tree.winid()
    vim.api.nvim_win_set_width(tree_window, 20)
    require('nvim-tree.api').tree.close()
  ]])
  settle()
  vim.rpcrequest(child, 'nvim_ui_try_resize', 240, 60)
  settle()
  evaluate([[
    local expected_width = require('config.ui.window_state').panel_size('NvimTree', 'width', 30)
    require('nvim-tree.api').tree.open()
    _G.tree_window = require('nvim-tree.api').tree.winid()
    assert(math.abs(vim.api.nvim_win_get_width(tree_window) - 24) <= 1,
      'File tree did not remember its proportion across close, resize, and reopen: '
        .. vim.inspect({ expected_width, vim.api.nvim_win_get_width(tree_window) }))
    require('nvim-tree.api').tree.close()
  ]])
  vim.rpcrequest(child, 'nvim_ui_try_resize', 200, 60)
  settle()
  evaluate([[
    vim.cmd.tabonly()
    vim.cmd.only()
    vim.api.nvim_set_current_dir(...)
    vim.cmd.edit((...) .. '/first.txt')
    require('config.git').history_repository()
  ]])
  assert(vim.wait(5000, function()
    return evaluate([[
      local view = require('diffview.lib').get_current_view()
      return view and require('config.git.lifecycle').is_ready(view)
    ]])
  end, 20), 'Repository history did not become ready')
  evaluate([[
    _G.history = require('diffview.lib').get_current_view()
    _G.entry = history.panel.entries[1]
    _G.details_loaded = false
    require('config.git.footer_loader').ensure_entry(history, entry, function(loaded)
      details_loaded = loaded
    end)
  ]])
  assert(vim.wait(5000, function() return evaluate('return details_loaded') end, 20),
    'History file details did not load')
  evaluate([[
    assert(#entry.files == 2, 'Fixture should contain two changed files')
    vim.api.nvim_set_current_win(history.panel.winid)
    history.panel:highlight_item(entry.files[1])
    vim.api.nvim_input('<CR>')
  ]])
  assert(vim.wait(5000, function()
    return evaluate("return require('config.git.lifecycle').render_is_ready(history)")
  end, 20), 'First history file did not render')
  settle()
  evaluate([[
    vim.api.nvim_win_set_width(history.cur_layout.a.id, 60)
    vim.api.nvim_win_set_height(history.panel.winid, 8)
  ]])
  settle()
  evaluate([[
    _G.history_width = vim.api.nvim_win_get_width(history.cur_layout.a.id)
    _G.history_height = vim.api.nvim_win_get_height(history.panel.winid)
    vim.api.nvim_set_current_win(history.panel.winid)
    history.panel:highlight_item(entry.files[2])
    vim.api.nvim_input('<CR>')
  ]])
  assert(vim.wait(5000, function()
    return evaluate([[
      return history.cur_entry == entry.files[2]
        and require('config.git.lifecycle').render_is_ready(history)
    ]])
  end, 20), 'Second history file did not render')
  settle()
  evaluate([[
    assert(vim.api.nvim_win_get_width(history.cur_layout.a.id) == history_width,
      'Selecting another history file reset the code split')
    assert(vim.api.nvim_win_get_height(history.panel.winid) == history_height,
      'Selecting another history file reset the footer')
  ]])
  vim.rpcrequest(child, 'nvim_ui_try_resize', 240, 75)
  settle()
  evaluate([[
    assert(math.abs(vim.api.nvim_win_get_width(history.cur_layout.a.id) - history_width * 1.2) <= 2,
      'Diffview code split did not use shared proportions')
    assert(math.abs(vim.api.nvim_win_get_height(history.panel.winid) - history_height * 1.25) <= 2,
      'Diffview history footer did not use shared proportions')
  ]])
  evaluate([[
    local preference = require('config.ui.window_state').prepare_panel('NvimTree', 'width')
    preference.store:when_idle(function(saved, failure)
      assert(saved, failure)
      vim.g.window_preference_saved = true
    end)
  ]])
  assert(vim.wait(2000, function() return evaluate([[return vim.g.window_preference_saved]]) end),
    'Window preference did not finish saving')
  local persisted_ratio = evaluate([[
    local preference = require('config.ui.window_state').prepare_panel('NvimTree', 'width')
    return assert(preference.store:read_sync()).ratio
  ]])
  local restarted = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' },
    { rpc = true, env = {
      XDG_STATE_HOME = directory .. '/.git/state', XDG_CACHE_HOME = directory .. '/.git/cache',
    } })
  local function restart_check()
    vim.rpcrequest(restarted, 'nvim_ui_attach', 320, 70, { rgb = true })
    vim.rpcrequest(restarted, 'nvim_exec_lua', [[
      local root = ...
      vim.cmd.edit(root .. '/first.txt')
      require('nvim-tree.api').tree.open({ path = root })
    ]], { directory })
    assert(vim.wait(3000, function()
      return vim.rpcrequest(restarted, 'nvim_exec_lua', [[
        local ratio = ...
        local winid = require('nvim-tree.api').tree.winid()
        return math.abs(vim.api.nvim_win_get_width(winid) - math.floor(ratio * vim.o.columns + 0.5)) <= 1
      ]], { persisted_ratio })
    end, 20), 'A new Neovim process did not restore the saved file-tree proportion')
  end
  local restart_passed, restart_failure = xpcall(restart_check, debug.traceback)
  vim.fn.jobstop(restarted)
  assert(restart_passed, restart_failure)
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed split proportions, file-tree persistence, and Diffview history passed')
