-- Real Flash interaction checks. An optional argument selects a disposable checkout:
-- nvim --headless -u NONE -i NONE -l tests/search/flash_installed.lua [plugin-path]
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local plugin_path = arg[1] or vim.fn.stdpath('data') .. '/lazy/flash.nvim'
assert(vim.uv.fs_stat(plugin_path .. '/lua/flash/init.lua'), 'Flash.nvim is not installed')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'NONE', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = directory, XDG_CACHE_HOME = directory } })
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function wait_for(source, message)
  assert(vim.wait(2000, function() return evaluate(source) end, 10), message)
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
  vim.wait(30)
end
local function reset()
  evaluate([=[
    vim.cmd('enew!')
    vim.bo.filetype = 'lua'
    local lines = {}
    for index = 1, 100 do lines[index] = '-- filler ' .. index end
    lines[10] = '-- origin'
    lines[12] = '-- needle alpha'
    lines[15] = '-- needle beta'
    lines[80] = '-- needle distant'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    vim.cmd('normal! zt')
    vim.cmd('redraw')
    vim.g.flash_test_view = vim.fn.winsaveview()
    vim.g.flash_test_window = vim.api.nvim_get_current_win()
    vim.fn.setreg('/', 'previous-search')
  ]=])
end
local function target_label(row)
  return evaluate([=[
    local row = ...
    local state = require('flash.repeat')._states.jump
    for _, match in ipairs(state.results) do
      if match.pos[1] == row then return match.label end
    end
    error('Visible target has no label')
  ]=], { row })
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 30, { rgb = true })
  evaluate([=[
    local root, plugin = ...
    vim.opt.runtimepath:prepend(root)
    vim.opt.runtimepath:append(plugin)
    require('config.startup.options')
    require('config.syntax.highlights').setup()
    for _, spec in ipairs(dofile(root .. '/lua/plugins/coding.lua')) do
      if spec[1] == 'folke/flash.nvim' then
        require('flash').setup(spec.opts)
        for _, mapping in ipairs(spec.keys) do
          vim.keymap.set(mapping.mode, mapping[1], mapping[2], {
            silent = mapping.silent,
            desc = mapping.desc,
          })
        end
      end
    end
    require('config.startup.keybindings').setup()
    for _, mode in ipairs({ 'n', 'x', 'o' }) do
      for _, key in ipairs({ 's', 'S', 'r', 'R', 'f', 'F', 't', 'T', ';', ',', '/', '?' }) do
        assert(vim.tbl_isempty(vim.fn.maparg(key, mode, false, true)),
          'Plugin replaced an editing command: ' .. mode .. ' ' .. key)
      end
      for _, key in ipairs({ '<Space>s', '<Space>fn' }) do
        assert(vim.fn.maparg(key, mode, false, true).callback, 'Flash shortcut is missing')
      end
    end
  ]=], { vim.fn.getcwd(), plugin_path })
  reset()
  -- Another code window must not receive labels or change focus.
  evaluate([=[
    vim.cmd('vsplit')
    vim.api.nvim_set_current_win(vim.g.flash_test_window)
  ]=])
  input(' sneedle')
  wait_for([=[
    local state = require('flash.repeat')._states.jump
    return state and state.visible and #state.results == 2
  ]=], 'Flash did not label the two visible matches')
  evaluate([=[
    local state = require('flash.repeat')._states.jump
    assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.flash_test_view),
      'Standalone Flash moved the cursor or viewport while typing')
    for _, match in ipairs(state.results) do
      assert(match.win == vim.g.flash_test_window, 'Flash labelled another pane')
      assert(match.label and match.label:match('^[a-z]$'), 'Flash used an uppercase label')
      assert(match.pos[1] ~= 80, 'Flash labelled an off-screen match')
    end
  ]=])
  input(target_label(15))
  wait_for([=[return vim.api.nvim_win_get_cursor(0)[1] == 15]=], 'Label did not jump to the target')
  evaluate([=[
    assert(vim.fn.getreg('/') == 'previous-search', 'Standalone jump changed native search')
    local jumps = vim.fn.getjumplist()[1]
    assert(#jumps > 0 and jumps[#jumps].lnum == 10, 'Flash did not save the original jump position')
    vim.cmd('only')
  ]=])
  for _, cancel in ipairs({ '<Esc>', '<C-q>' }) do
    reset()
    input(' sneedle' .. cancel)
    wait_for([=[
      local state = require('flash.repeat')._states.jump
      return state and not state.visible
    ]=], 'Flash prompt did not cancel')
    evaluate([=[assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.flash_test_view),
      'Cancellation did not retain the original view')]=])
  end
  -- Native search stays unlabelled and reaches matches beyond the viewport.
  reset()
  input('/needle')
  wait_for([=[
    return vim.api.nvim_get_mode().mode == 'c' and vim.fn.getcmdline() == 'needle'
  ]=], 'Slash did not open native search')
  evaluate([=[assert(require('flash.plugins.search').state == nil, 'Flash took over native search')]=])
  input('<CR>')
  wait_for([=[return vim.api.nvim_win_get_cursor(0)[1] == 12]=], 'Native search acceptance changed')
  input('n')
  assert(evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=]) == 15, 'Native n repeat changed')
  input('N')
  assert(evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=]) == 12, 'Native N repeat changed')
  input('2n')
  assert(evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=]) == 80, 'Native search failed to reach an off-screen match')
  evaluate([=[vim.api.nvim_win_set_cursor(0, { 15, 0 })]=])
  input('?needle<CR>')
  assert(evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=]) == 12, 'Backward search changed')
  reset()
  input('/needle<Esc>')
  evaluate([=[assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.flash_test_view),
    'Native search cancellation lost the view')]=])
  -- Special buffers retain native search and receive no labels.
  reset()
  evaluate([=[vim.bo.buftype = 'nofile'; vim.bo.filetype = 'gitgraph']=])
  input('/needle')
  evaluate([=[
    local state = require('flash.plugins.search').state
    assert(state == nil, 'Flash labelled a panel search')
  ]=])
  input('<Esc>')
  -- Real operator-pending dispatch must execute a native edit at the chosen target.
  reset()
  input('d sneedle')
  input(target_label(12))
  wait_for([=[return vim.api.nvim_get_mode().mode == 'n']=], 'Flash delete motion did not finish')
  evaluate([=[
    assert(vim.api.nvim_buf_line_count(0) == 98, 'Flash delete motion selected the wrong range')
    assert(vim.api.nvim_buf_get_lines(0, 9, 10, false)[1] == 'needle alpha',
      'Flash delete motion did not end at the match: ' .. vim.api.nvim_buf_get_lines(0, 9, 10, false)[1])
  ]=])
  reset()
  input('d sneedle<C-q>')
  wait_for([=[return vim.api.nvim_get_mode().mode == 'n']=], 'Cancel left an operator pending')
  evaluate([=[assert(vim.api.nvim_buf_line_count(0) == 100,
    'Cancelling a Flash motion changed the buffer')]=])
  reset()
  input('v sneedle')
  input(target_label(15))
  wait_for([=[return not require('flash.repeat')._states.jump.visible]=],
    'Visual jump did not finish')
  evaluate([=[
    assert(vim.api.nvim_get_mode().mode == 'v' and vim.fn.getpos('v')[2] == 10
      and vim.api.nvim_win_get_cursor(0)[1] == 15, 'Visual jump lost its anchor or target')
  ]=])
  input('<Esc>')
  -- Syntax selection uses the actual installed Lua parser.
  reset()
  evaluate([=[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'local function sample()', '  return 42', 'end',
    })
    vim.api.nvim_win_set_cursor(0, { 2, 2 })
    vim.treesitter.get_parser(0, 'lua'):parse()
  ]=])
  input(' fn')
  wait_for([=[
    local state = require('flash.repeat')._states.treesitter
    return state and state.visible and #state.results > 0
  ]=], 'Syntax selection did not expose code regions')
  local syntax_label = evaluate([=[
    local state = require('flash.repeat')._states.treesitter
    for _, match in ipairs(state.results) do
      assert(match.label and match.label:match('^[a-z]$'), 'Syntax labels are not lowercase')
      if match.pos[1] == 1 and match.end_pos[1] == 3 then return match.label end
    end
    error('Function region is missing')
  ]=])
  input(syntax_label)
  wait_for([=[return vim.api.nvim_get_mode().mode == 'v']=], 'Syntax label did not select the region')
  evaluate([=[
    assert(vim.fn.getpos('v')[2] == 1 and vim.api.nvim_win_get_cursor(0)[1] == 3,
      'Syntax selection did not cover the function')
  ]=])
  input('<Esc>')
  evaluate([=[vim.api.nvim_win_set_cursor(0, { 2, 2 })]=])
  input('y fn')
  wait_for([=[
    local state = require('flash.repeat')._states.treesitter
    return state and state.visible and #state.results > 0
  ]=], 'Syntax yank did not expose code regions')
  input(syntax_label)
  wait_for([=[return vim.api.nvim_get_mode().mode == 'n']=], 'Syntax yank did not finish')
  evaluate([=[
    assert(vim.fn.getreg('"') == 'local function sample()\n  return 42\nend',
      'Syntax yank did not copy the complete function')
  ]=])
  evaluate([=[
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:match('Error') and not messages:match('E%d+:'), messages)
  ]=])
end
local ok, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(ok, failure)
print('Flash visible jumps, lowercase labels, native search, cancellation, motions, and syntax selection pass')
