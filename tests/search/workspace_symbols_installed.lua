-- Real first-use definition selection and native back/forward navigation.
-- nvim --headless -u NONE -i NONE -l tests/search/workspace_symbols_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/project/.git', 'p')
local project = directory .. '/project'
vim.fn.writefile({ 'source first', 'source second', 'source third' }, project .. '/source.txt')
vim.fn.writefile({ 'unrelated pane' }, project .. '/other.txt')
vim.fn.writefile({ '-- first', '', 'vim.g.loaded_render_markdown = true', '', 'local next_symbol = 1' },
  project .. '/target.lua')
vim.fn.writefile({ '', 'local fresh_definition = 1' }, project .. '/fresh.lua')
local child = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' }, {
  rpc = true, env = { XDG_STATE_HOME = directory .. '/state', XDG_CACHE_HOME = directory .. '/cache',
    NVIM_LOG_FILE = directory .. '/nvim.log' },
})
local function evaluate(source)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected blocking editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { project })
end
local function wait_for(source, message)
  local passed = vim.wait(5000, function()
    if vim.rpcrequest(child, 'nvim_get_mode').blocking then return false end
    return evaluate(source)
  end, 20)
  if not passed and not vim.rpcrequest(child, 'nvim_get_mode').blocking then
    print(vim.inspect(evaluate([[return { file = vim.api.nvim_buf_get_name(0), cursor = vim.api.nvim_win_get_cursor(0),
      messages = vim.api.nvim_exec2('messages', { output = true }).output, jumps = vim.fn.getjumplist() }]])))
  end
  assert(passed, message .. ' ' .. vim.inspect(vim.rpcrequest(child, 'nvim_get_mode')))
end
local function assert_panes()
  evaluate([[
    assert(vim.api.nvim_get_current_win() == source_window, 'Selection did not replace the focused editor')
    assert(vim.deep_equal(vim.fn.winlayout(), saved_layout), 'Selection changed split structure')
    for window, saved in pairs(saved_panes) do
      assert(vim.api.nvim_win_get_width(window) == saved.width
        and vim.api.nvim_win_get_height(window) == saved.height,
        'Selection resized a pane: ' .. vim.inspect({ window = window, saved = saved,
          width = vim.api.nvim_win_get_width(window), height = vim.api.nvim_win_get_height(window) }))
      if window ~= source_window then
        assert(vim.api.nvim_win_get_buf(window) == saved.buffer, 'Selection replaced an unrelated pane')
        assert(vim.deep_equal(vim.api.nvim_win_get_cursor(window), saved.cursor),
          'Selection moved an unrelated pane cursor')
      end
    end
  ]])
end
local function assert_editor_layout()
  evaluate([[
    local picker = require('telescope.actions.state').get_current_picker(symbol_prompt)
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

local function select_symbol(query, line, preview, filename)
  vim.rpcrequest(child, 'nvim_input', ' fw')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'First Space-fw invocation did not open the picker')
  evaluate([[_G.symbol_prompt = vim.api.nvim_get_current_buf()]])
  assert_editor_layout()
  vim.rpcrequest(child, 'nvim_input', query)
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(symbol_prompt)
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], 'Definition result did not arrive')
  if preview then
    vim.rpcrequest(child, 'nvim_input', '<Tab>')
    wait_for([[
      local picker = require('telescope.actions.state').get_current_picker(symbol_prompt)
      return vim.api.nvim_get_current_win() == picker.previewer.state.winid and vim.api.nvim_get_mode().mode == 'n'
    ]], 'Definition preview did not focus')
    assert_editor_layout()
  end
  vim.rpcrequest(child, 'nvim_input', '<CR>')
  wait_for(('return vim.api.nvim_buf_get_name(0) == (...) .. %q and vim.fn.line(".") == %d')
    :format('/' .. (filename or 'target.lua'), line),
    'First selection did not jump to the definition')
  assert_panes()
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  wait_for([[return vim.bo.filetype == 'dashboard']], 'Startup dashboard did not open')
  evaluate([[
    vim.cmd.edit((...) .. '/source.txt')
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    _G.source_window = vim.api.nvim_get_current_win()
    _G.source_buffer = vim.api.nvim_get_current_buf()
    vim.cmd.vsplit((...) .. '/target.lua')
    _G.other_window = vim.api.nvim_get_current_win()
    vim.cmd.split((...) .. '/other.txt')
    _G.bottom_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(other_window, 47)
    vim.api.nvim_win_set_height(bottom_window, 11)
    vim.api.nvim_set_current_win(source_window)
    vim.cmd('clearjumps')
  ]])
  vim.wait(100)
  evaluate([[
    _G.saved_layout = vim.fn.winlayout()
    _G.saved_panes = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      saved_panes[window] = { buffer = vim.api.nvim_win_get_buf(window), cursor = vim.api.nvim_win_get_cursor(window),
        width = vim.api.nvim_win_get_width(window), height = vim.api.nvim_win_get_height(window) }
    end
    -- Exercise both launch-time and buffer-entry callbacks changing geometry.
    vim.api.nvim_create_autocmd('User', { pattern = 'TelescopeFindPre', once = true, callback = function()
      vim.api.nvim_win_set_width(source_window, 65)
      vim.api.nvim_win_set_height(bottom_window, 7)
    end })
    vim.api.nvim_create_autocmd('BufEnter', { pattern = (...) .. '/target.lua', once = true, callback = function()
      vim.api.nvim_win_set_width(source_window, 58)
      vim.api.nvim_win_set_height(bottom_window, 8)
    end })
  ]])
  select_symbol('loaded_render_markdown', 3)
  evaluate([[assert(vim.api.nvim_get_current_win() == source_window, 'Selection changed the editor pane')]])
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/source.txt'
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 })]], 'Space-o lost the original file or position')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.lua' and vim.fn.line('.') == 3]],
    'Space-p lost the selected definition')
  select_symbol('next_symbol', 5, true)
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.fn.line('.') == 3]], 'Same-file definition selection did not record the origin')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.fn.line('.') == 5]], 'Same-file definition selection did not preserve forward navigation')
  evaluate([[
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd('clearjumps')
  ]])
  vim.rpcrequest(child, 'nvim_input', '/next_symbol<CR>')
  wait_for([[return vim.fn.line('.') == 5]], 'Native slash search did not reach the symbol')
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.fn.line('.') == 1]], 'Space-o lost slash-search history')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.fn.line('.') == 5]], 'Space-p lost slash-search history')
  evaluate([[vim.cmd.cd(...)]])
  vim.rpcrequest(child, 'nvim_input', ' ff')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Space-ff did not open')
  vim.rpcrequest(child, 'nvim_input', 'source.txt')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], 'File-search result did not arrive')
  vim.rpcrequest(child, 'nvim_input', '<CR>')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/source.txt']], 'First file selection did not open')
  assert_panes()
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.lua' and vim.fn.line('.') == 5]],
    'Space-o lost file-picker history')
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.fn.line('.') == 1]], 'File replacement erased older slash-search history')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.fn.line('.') == 5]], 'Forward navigation lost the search destination')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/source.txt']], 'Space-p lost file-picker history')
  select_symbol('fresh_definition', 2, true, 'fresh.lua')
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/source.txt']], 'Fresh-file definition lost jump history')
  assert_panes()
  evaluate([[
    vim.api.nvim_create_autocmd('User', { pattern = 'TelescopeFindPre', once = true, callback = function()
      vim.api.nvim_win_set_width(source_window, 65)
      vim.api.nvim_win_set_height(bottom_window, 7)
    end })
  ]])
  vim.rpcrequest(child, 'nvim_input', ' fw')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Definition cancellation fixture did not open')
  vim.rpcrequest(child, 'nvim_input', '<C-q>')
  wait_for([[return vim.api.nvim_get_current_win() == source_window]], 'Definition cancellation lost the launch pane')
  assert_panes()
  evaluate([[vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'unsaved layout fixture' })]])
  vim.rpcrequest(child, 'nvim_input', ' fw')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Unwritten definition fixture did not open')
  evaluate([[_G.symbol_prompt = vim.api.nvim_get_current_buf()]])
  vim.rpcrequest(child, 'nvim_input', 'fresh_definition')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(symbol_prompt)
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], 'Unwritten definition result did not arrive')
  vim.rpcrequest(child, 'nvim_input', '<CR>')
  assert(vim.wait(5000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'r?' end, 20),
    'Definition search did not ask whether to write the destination')
  vim.rpcrequest(child, 'nvim_input', 'n')
  wait_for([[return vim.api.nvim_get_current_win() == source_window and vim.bo.modified]],
    'No did not reject the unwritten definition destination')
  assert_panes()
  evaluate([[vim.cmd('write')]])
  select_symbol('fresh_definition', 2, false, 'fresh.lua')
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed definitions use whole-editor proportions and preserve launch-pane targeting and native history')
