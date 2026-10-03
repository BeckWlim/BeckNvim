-- Real <Space>ff routing from the tree, including the startup dashboard.
-- nvim --headless -u NONE -i NONE -l tests/search/file_selection_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/project/.git', 'p')
local project = directory .. '/project'
vim.fn.writefile({ 'target fixture' }, project .. '/target.txt')
vim.fn.writefile({ 'other fixture' }, project .. '/other.txt')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' },
  { rpc = true, env = {
    XDG_STATE_HOME = directory .. '/state', XDG_CACHE_HOME = directory .. '/cache',
    NVIM_LOG_FILE = directory .. '/nvim.log',
  } })
local function evaluate(source, ...)
  local mode = vim.rpcrequest(child, 'nvim_get_mode')
  assert(not mode.blocking, 'Editor opened a blocking prompt: ' .. vim.inspect(mode))
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { project, ... })
end
local function wait_for(source, message)
  assert(vim.wait(5000, function() return evaluate(source) end, 20), message)
end
local function assert_editor_layout()
  evaluate([[
    local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
    local expected = require('telescope.pickers.layout_strategies').flex(picker, vim.o.columns, vim.o.lines - vim.o.cmdheight - (vim.o.laststatus == 0 and 0 or 1))
    for _, name in ipairs({ 'prompt', 'results', 'preview' }) do
      local pane = picker.layout[name]
      if pane then
        assert(vim.api.nvim_win_get_width(pane.winid) == expected[name].width
          and vim.api.nvim_win_get_height(pane.winid) == expected[name].height,
          'Search lost the native whole-editor proportions: ' .. name .. vim.inspect({ actual = { vim.api.nvim_win_get_width(pane.winid), vim.api.nvim_win_get_height(pane.winid) }, expected = expected[name], columns = vim.o.columns, lines = vim.o.lines, cmdheight = vim.o.cmdheight }))
      end
    end
  ]])
end

local function open_picker(key, source_window, query)
  evaluate([[
    local _, source = ...
    if source then vim.api.nvim_set_current_win(source)
    else require('nvim-tree.api').tree.focus() end
    _G.saved_layout = vim.fn.winlayout()
    _G.saved_sizes = {}
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      saved_sizes[winid] = {
        width = vim.api.nvim_win_get_width(winid), height = vim.api.nvim_win_get_height(winid),
      }
    end
  ]], source_window)
  vim.rpcrequest(child, 'nvim_input', key or ' ff')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Find files did not open in Insert mode')
  evaluate([[_G.selection_prompt = vim.api.nvim_get_current_buf()]])
  assert_editor_layout()
  local prompt = query or 'target'
  vim.rpcrequest(child, 'nvim_input', prompt)
  local selected = vim.wait(5000, function() return evaluate([[
    local _, prompt = ...
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker.manager and picker:_get_prompt() == prompt
      and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], prompt) end, 20)
  if not selected then
    print(vim.inspect(evaluate([[
      local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
      return { prompt = picker:_get_prompt(), results = picker.manager and picker.manager:num_results(),
        selection = picker:get_selection(), max_results = picker.max_results, messages = vim.api.nvim_exec2('messages', { output = true }).output }
    ]])))
  end
  assert(selected, 'File picker did not select the fixture')
end
local function select_file(destination, from_preview)
  if from_preview then
    evaluate([[_G.selection_prompt = vim.api.nvim_get_current_buf()]])
    vim.rpcrequest(child, 'nvim_input', '<Tab>')
    wait_for([[
      local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
      return vim.api.nvim_get_current_win() == picker.previewer.state.winid
        and vim.api.nvim_get_mode().mode == 'n'
    ]], 'Recent files did not focus the preview')
    assert_editor_layout()
  end
  vim.rpcrequest(child, 'nvim_input', '<CR>')
  if destination then
    wait_for([[return vim.bo.filetype == 'FilePanePicker']], 'Find files did not ask for an editor pane')
    local letter = evaluate(([[
      local index = 0
      for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buffer = vim.api.nvim_win_get_buf(window)
        if vim.api.nvim_win_get_config(window).relative == ''
            and (vim.bo[buffer].buftype == '' or vim.bo[buffer].filetype == 'dashboard')
            and not vim.wo[window].winfixbuf then
          index = index + 1
          if window == %s then return string.char(96 + index) end
        end
      end
      error('Requested destination was not offered')
    ]]):format(destination))
    vim.rpcrequest(child, 'nvim_input', letter)
  end
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Find files did not open the selected file')
end
local function assert_layout()
  evaluate([[
    assert(vim.deep_equal(vim.fn.winlayout(), saved_layout),
      'Find files changed split structure: ' .. vim.inspect({ before = saved_layout, after = vim.fn.winlayout() }))
    for winid, size in pairs(saved_sizes) do
      assert(vim.api.nvim_win_get_width(winid) == size.width
        and vim.api.nvim_win_get_height(winid) == size.height, 'Find files resized an existing pane')
    end
    assert(vim.bo[vim.api.nvim_win_get_buf(tree_window)].filetype == 'NvimTree',
      'Find files replaced the tree')
  ]])
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  wait_for([[return vim.bo.filetype == 'dashboard']], 'Startup dashboard did not open')
  evaluate([[
    require('telescope').setup({ defaults = { history = { path = vim.fn.stdpath('state') .. '/telescope_history' } } })
    _G.editor_window = vim.api.nvim_get_current_win()
    _G.editor_numbers = require('config.ui.window_state').resolve(editor_window, { 'number', 'relativenumber' })
    vim.cmd.cd(...)
    require('config.project').activate(...)
    require('nvim-tree.api').tree.open({ path = ... })
    _G.tree_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(tree_window, 24)
  ]])
  open_picker()
  select_file()
  assert_layout()
  evaluate([[
    assert(vim.api.nvim_get_current_win() == editor_window, 'Find files did not reuse the dashboard pane')
    assert(vim.wo.number == editor_numbers.number and vim.wo.relativenumber == editor_numbers.relativenumber,
      'Dashboard selection lost editor line-number settings')
    vim.cmd.vsplit((...) .. '/other.txt')
    _G.other_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(other_window, 45)
    vim.cmd.split()
    _G.target_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(target_window, 12)
  ]])
  open_picker()
  select_file('target_window')
  assert_layout()
  evaluate([[
    assert(vim.api.nvim_get_current_win() == target_window, 'Find files lost the chosen editor target')
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(other_window)) == (...) .. '/other.txt',
      'Find files replaced an unrelated editor buffer')
  ]])
  evaluate([[vim.v.oldfiles = { (...) .. '/target.txt' }]])
  open_picker(' fr')
  select_file('other_window', true)
  assert_layout()
  evaluate([[
    assert(vim.api.nvim_get_current_win() == other_window,
      'Recent files preview ignored the panel-origin destination choice')
  ]])
  open_picker()
  vim.rpcrequest(child, 'nvim_input', '<C-q>')
  wait_for([[return vim.api.nvim_get_current_win() == tree_window]], 'Cancellation did not restore tree focus')
  assert_layout()
  local focused_window = evaluate([[return target_window]])
  for _, case in ipairs({ { ' ff', 'target', false }, { ' fr', 'target', true },
    { ' fg', 'target fixture', false }, { ' fb', 'target', true } }) do
    evaluate([[
      vim.api.nvim_set_current_win(target_window)
      vim.cmd.edit((...) .. '/other.txt')
    ]])
    open_picker(case[1], focused_window, case[2])
    select_file(nil, case[3])
    assert_layout()
    evaluate([[
      assert(vim.api.nvim_get_current_win() == target_window, 'File picker did not replace the focused pane')
      assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(other_window)) == (...) .. '/target.txt',
        'File picker changed an unrelated pane')
    ]])
  end
  -- Short or narrow launch panes must not shrink the whole-editor search.
  evaluate([[
    vim.o.showtabline = 2
    vim.api.nvim_win_set_height(target_window, 5)
  ]])
  open_picker(' ff', focused_window)
  assert_editor_layout()
  select_file()
  assert_layout()
  evaluate([[
    vim.api.nvim_win_set_height(target_window, 12)
    vim.cmd.edit((...) .. '/other.txt')
  ]])
  open_picker(' fr', focused_window)
  vim.rpcrequest(child, 'nvim_input', '<Tab>')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
    return vim.api.nvim_get_current_win() == picker.previewer.state.winid
      and vim.api.nvim_get_mode().mode == 'n'
  ]], 'Resize fixture did not focus the preview')
  evaluate([[
    vim.api.nvim_win_set_height(target_window, 9)
    require('telescope.actions.state').get_current_picker(selection_prompt):full_layout_update()
  ]])
  assert_editor_layout()
  evaluate([[
    vim.api.nvim_win_set_width(target_window, 24)
    require('telescope.actions.state').get_current_picker(selection_prompt):full_layout_update()
  ]])
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
    return vim.api.nvim_buf_is_valid(selection_prompt) and picker.layout.preview ~= nil
  ]], 'A narrow launch pane unexpectedly hid the full-editor preview')
  assert_editor_layout()
  vim.rpcrequest(child, 'nvim_input', '<C-q>')
  wait_for([[return vim.api.nvim_get_current_win() == target_window]], 'Resized picker lost launch focus')
  assert_layout()
  evaluate([[
    vim.api.nvim_set_current_win(target_window)
    vim.cmd.edit((...) .. '/other.txt')
    vim.api.nvim_create_autocmd('User', { pattern = 'TelescopeFindPre', once = true, callback = function()
      vim.api.nvim_win_set_width(other_window, 62)
      vim.api.nvim_win_set_height(target_window, 8)
    end })
    local configuration = require('telescope.config').values
    local session = require('config.search.query_picker').open({
      title = 'LSP location fixture', entry_maker = function(entry) return entry end,
      sorter = configuration.generic_sorter({}), previewer = configuration.qflist_previewer({}),
    })
    session:finish({ { filename = (...) .. '/target.txt', lnum = 1, col = 3,
      display = 'target location', ordinal = 'target location' } })
  ]])
  wait_for([[
    if vim.bo.filetype ~= 'TelescopePrompt' or vim.api.nvim_get_mode().mode ~= 'i' then return false end
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], 'Shared location picker did not finish')
  evaluate([[_G.selection_prompt = vim.api.nvim_get_current_buf()]])
  assert_editor_layout()
  select_file()
  assert_layout()
  evaluate([[
    assert(vim.api.nvim_get_current_win() == target_window, 'Location picker did not replace the focused pane')
    vim.cmd.edit((...) .. '/other.txt')
    vim.api.nvim_create_autocmd('BufEnter', { pattern = (...) .. '/target.txt', once = true, callback = function()
      vim.api.nvim_win_set_width(other_window, 62)
      vim.api.nvim_win_set_height(target_window, 8)
    end })
  ]])
  vim.rpcrequest(child, 'nvim_input', ':e target.txt<CR>')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']], 'Typed edit did not replace the pane')
  assert_layout()
  evaluate([[
    vim.api.nvim_win_close(target_window, true)
    vim.api.nvim_win_close(other_window, true)
    vim.api.nvim_win_close(editor_window, true)
  ]])
  open_picker()
  select_file()
  evaluate([[
    assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'Tree-only selection did not create exactly one editor')
    assert(vim.api.nvim_get_current_win() ~= tree_window, 'Tree-only selection replaced the tree')
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed searches retain whole-editor proportions and replace only their launch pane')
