-- Exercise actual tree mappings, Telescope actions and shared letter selection.
-- nvim --headless -u NONE -i NONE -l tests/ui/file_operations_installed.lua
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/project/.git', 'p')
local project = root .. '/project'
for _, name in ipairs({ 'one.txt', 'two.txt', 'target.txt' }) do
  vim.fn.writefile({ name, 'location target' }, project .. '/' .. name)
end
local init_path = root .. '/init.lua'
vim.fn.writefile({
  ('vim.opt.runtimepath:prepend(%q)'):format(vim.fn.getcwd()),
  [[local lazy = vim.fn.stdpath('data') .. '/lazy/']],
  [[for _, plugin in ipairs({ 'nvim-tree.lua', 'nvim-web-devicons', 'telescope.nvim', 'plenary.nvim', 'telescope-ui-select.nvim', 'toggleterm.nvim' }) do vim.opt.runtimepath:append(lazy .. plugin) end]],
  [[require('config.startup.options')]],
  [[require('config.ui.window_state').setup()]],
  [[require('config.ui.float').setup()]],
  [[require('config.navigation.write_guard').setup()]],
  [[require('config.startup.autocmds').setup()]],
  [[require('config.startup.keybindings').setup()]],
  [[require('config.syntax.highlights').setup()]],
  [[require('config.search.telescope').setup()]],
  [[require('telescope').setup({ defaults = { history = { path = vim.fn.stdpath('state') .. '/history' } } })]],
  [[local opts = require('plugins.extra')[2].opts]],
  [[opts.git = { enable = false }; opts.filesystem_watchers = { enable = false }]],
  [[require('nvim-tree').setup(opts)]],
  [[require('config.ui.filetree').setup()]],
  [[require('toggleterm').setup(require('plugins.extra')[3].opts)]],
}, init_path)
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', init_path, '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = root .. '/cache', XDG_STATE_HOME = root .. '/state' },
})
local function evaluate(source)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected blocking editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { project })
end
local function wait_for(source, message)
  assert(vim.wait(5000, function() return evaluate(source) end, 20), message)
end
local function destination()
  wait_for([[return vim.bo.filetype == 'FilePanePicker']], 'Letter pane selector did not open')
  evaluate([[
    local palette = require('config.ui.palette')
    local label = vim.api.nvim_get_hl(0, { name = 'FilePaneLabel', link = false })
    assert(label.bold and palette.contrast(label.fg, label.bg) >= 7, 'Pane label lost its contrast')
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'FilePanePicker' then
        assert(vim.wo[window].winhighlight:find('NormalFloat:FilePaneLabel', 1, true)
          and vim.wo[window].winhighlight:find('FloatBorder:FilePaneBorder', 1, true)
          and vim.wo[window].winblend == 0, 'A pane badge did not apply its palette')
      end
    end
  ]])
end
local function choose(window_name, focus_only)
  destination()
  local letter = evaluate(([[
    local windows = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buffer = vim.api.nvim_win_get_buf(window)
      if vim.api.nvim_win_get_config(window).relative == '' and (%s or (vim.bo[buffer].buftype == ''
          and not vim.wo[window].winfixbuf)) then windows[#windows + 1] = window end
    end
    for index, window in ipairs(windows) do
      if window == %s then return string.char(96 + index) end
    end
    error('Requested pane was not offered')
  ]]):format(tostring(focus_only == true), window_name))
  vim.rpcrequest(child, 'nvim_input', letter)
end
local function answer_write(answer)
  local asking = vim.wait(5000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'r?' end, 20)
  assert(asking, 'Modified destination did not ask whether to write it')
  vim.rpcrequest(child, 'nvim_input', answer)
  assert(vim.wait(5000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode ~= 'r?' end, 20),
    'Write question did not finish')
end
local function find_file(key, from_preview, return_window)
  vim.rpcrequest(child, 'nvim_input', key or ' ff')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']], 'Find files did not open')
  vim.rpcrequest(child, 'nvim_input', 'target')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
      and picker:_get_prompt() == 'target'
  ]], 'File search did not find the target')
  if return_window then
    -- A plugin's return focus must not reclassify a panel-origin open as an
    -- editor-origin open. Pinning the launch context must survive that handoff.
    evaluate(('require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf()).original_win_id = %s')
      :format(return_window))
  end
  if from_preview then
    evaluate([[_G.selection_prompt = vim.api.nvim_get_current_buf()]])
    vim.rpcrequest(child, 'nvim_input', '<Tab>')
    wait_for([[
      local picker = require('telescope.actions.state').get_current_picker(selection_prompt)
      return vim.api.nvim_get_current_win() == picker.previewer.state.winid
        and vim.api.nvim_get_mode().mode == 'n'
    ]], 'File picker did not focus its preview')
  end
  vim.rpcrequest(child, 'nvim_input', '<CR>')
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  for _, close_tree in ipairs({ false, true }) do
    evaluate([[
      _G.preserved_tab = vim.api.nvim_get_current_tabpage()
      _G.preserved_window = vim.api.nvim_get_current_win()
      _G.preserved_buffer = vim.api.nvim_get_current_buf()
      vim.cmd.tabnew((...) .. '/one.txt')
      _G.closing_tab = vim.api.nvim_get_current_tabpage()
      _G.closing_editor = vim.api.nvim_get_current_win()
      require('nvim-tree.api').tree.open({ path = ... })
      _G.closing_tree = require('nvim-tree.api').tree.winid()
    ]])
    evaluate(('vim.api.nvim_set_current_win(%s)'):format(close_tree and 'closing_tree' or 'closing_editor'))
    vim.rpcrequest(child, 'nvim_input', ':q<CR>')
    wait_for(('return not vim.api.nvim_win_is_valid(%s)'):format(close_tree and 'closing_tree' or 'closing_editor'),
      'Native :q did not close the focused pane')
    evaluate(([[
      local remaining = %s
      assert(vim.api.nvim_win_is_valid(remaining), 'Native :q also closed the other pane')
      assert(vim.api.nvim_get_current_tabpage() == closing_tab, 'Native :q closed the split tab')
      assert(vim.deep_equal(vim.fn.winlayout(), { 'leaf', remaining }), 'Native :q left an unexpected layout')
      assert(vim.api.nvim_tabpage_is_valid(preserved_tab)
        and vim.api.nvim_win_is_valid(preserved_window)
        and vim.api.nvim_win_get_buf(preserved_window) == preserved_buffer,
        'Native :q changed another tab')
      vim.cmd.tabclose()
    ]]):format(close_tree and 'closing_editor' or 'closing_tree'))
  end
  evaluate([[
    vim.cmd.cd(...)
    vim.cmd.edit((...) .. '/one.txt')
    _G.first = vim.api.nvim_get_current_win()
    vim.cmd.vsplit((...) .. '/two.txt')
    _G.second = vim.api.nvim_get_current_win()
    vim.cmd.edit((...) .. '/one.txt')
    assert(vim.api.nvim_get_current_win() == second)
    assert(vim.api.nvim_win_get_buf(first) == vim.api.nvim_win_get_buf(second))
    vim.cmd.edit((...) .. '/two.txt')
    local api = require('nvim-tree.api')
    api.tree.open({ path = ... })
    _G.tree = api.tree.winid()
    _G.layout = vim.fn.winlayout()
    vim.v.oldfiles = { (...) .. '/target.txt' }
    vim.api.nvim_set_current_win(first)
  ]])
  vim.rpcrequest(child, 'nvim_input', ' ww')
  choose('tree', true)
  wait_for([[return vim.api.nvim_get_current_win() == tree]], 'Window picker excluded the tree pane')
  vim.rpcrequest(child, 'nvim_input', ' ww')
  destination()
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_current_win() == tree]], 'Window picker cancellation changed focus')
  vim.rpcrequest(child, 'nvim_input', ' ww')
  choose('first', true)
  wait_for([[return vim.api.nvim_get_current_win() == first]], 'Window picker did not focus the selected editor')
  evaluate([[
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Focus picker changed the layout')
    _G.gx_sizes = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      gx_sizes[window] = { vim.api.nvim_win_get_width(window), vim.api.nvim_win_get_height(window) }
    end
    _G.gx_source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(gx_source, 0, -1, false, { '[target](target.txt#L2)', 'source remains here' })
    vim.api.nvim_win_set_cursor(first, { 1, 2 })
  ]])
  vim.rpcrequest(child, 'nvim_input', 'gx')
  choose('second')
  wait_for([[return vim.api.nvim_get_current_win() == second
    and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt' and vim.fn.line('.') == 2]],
    'gx did not replace the chosen existing pane at the link anchor')
  evaluate([[
    assert(vim.api.nvim_win_get_buf(first) == gx_source and vim.bo[gx_source].modified,
      'gx changed or discarded the source pane')
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'gx added a split')
    for window, size in pairs(gx_sizes) do
      assert(vim.api.nvim_win_get_width(window) == size[1] and vim.api.nvim_win_get_height(window) == size[2],
        'gx changed split proportions')
    end
  ]])
  vim.rpcrequest(child, 'nvim_input', ' o')
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_buf_get_name(0) == (...) .. '/two.txt']],
    'gx history did not return to the chosen pane origin')
  vim.rpcrequest(child, 'nvim_input', ' p')
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt'
    and vim.fn.line('.') == 2]], 'gx forward history lost its anchor')
  evaluate([[vim.api.nvim_set_current_win(first)]])
  vim.rpcrequest(child, 'nvim_input', 'gx')
  destination()
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_current_win() == first]], 'gx cancellation lost source focus')
  evaluate([[
    assert(vim.api.nvim_win_get_buf(first) == gx_source and vim.bo[gx_source].modified
      and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(second)) == (...) .. '/target.txt'
      and vim.deep_equal(vim.fn.winlayout(), layout), 'Cancelling gx changed files or layout')
    local project_path = ...
    vim.api.nvim_win_call(second, function()
      vim.cmd.edit(project_path .. '/two.txt')
      vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'unsaved destination' })
    end)
  ]])
  vim.rpcrequest(child, 'nvim_input', 'gx')
  choose('second')
  answer_write('n')
  wait_for([[return vim.api.nvim_get_current_win() == first]], 'Dirty gx cancellation lost source focus')
  evaluate([[
    assert(vim.bo[vim.api.nvim_win_get_buf(second)].modified
      and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(second)) == (...) .. '/two.txt',
      'gx discarded an unsaved destination')
    vim.api.nvim_win_call(second, function() vim.cmd('edit!') end)
    vim.api.nvim_buf_set_lines(gx_source, 0, -1, false, { 'one.txt', 'location target' })
    vim.bo[gx_source].modified = false
  ]])
  find_file(' fr', true)
  wait_for([[return vim.api.nvim_get_current_win() == first and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Recent files did not use the focused editor')
  evaluate([[
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Recent files created an unexpected editor split')
    vim.cmd.edit((...) .. '/one.txt')
    require('nvim-tree.api').tree.focus()
  ]])
  find_file(' fr', true, 'first')
  choose('second')
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Recent files from the tree bypassed shared pane choice')
  evaluate([[
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Tree-origin recent files created an unexpected editor split')
    vim.cmd.edit((...) .. '/two.txt')
    vim.api.nvim_set_current_win(first)
  ]])
  find_file(' fv', true)
  wait_for([[return vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Explicit split selection from preview did not open the file')
  evaluate([[
    assert(vim.api.nvim_get_current_win() ~= first and #vim.api.nvim_tabpage_list_wins(0) == 4,
      'Explicit split picker preview did not match prompt Enter')
    require('config.navigation').close()
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Closing the explicit split changed unrelated panes')
    local api = require('nvim-tree.api')
    api.tree.find_file({ buf = (...) .. '/one.txt', focus = true })
    vim.fn.maparg('<CR>', 'n', false, true).callback()
  ]])
  choose('second')
  wait_for([[return vim.api.nvim_get_current_win() == tree]], 'Tree open lost focus')
  evaluate([[
    assert(vim.api.nvim_win_get_buf(first) == vim.api.nvim_win_get_buf(second), 'Tree reused another pane instead of the chosen one')
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Tree open changed the split layout')
    require('nvim-tree.api').tree.find_file({ buf = (...) .. '/target.txt', focus = true })
    vim.fn.maparg('o', 'n', false, true).callback()
  ]])
  destination()
  vim.rpcrequest(child, 'nvim_input', '<C-q>')
  wait_for([[return vim.api.nvim_get_current_win() == tree]], 'Destination cancellation lost tree focus')
  evaluate([[
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(second)) == (...) .. '/one.txt', 'Cancelled tree choice opened a file')
    -- Loading Git's command dispatcher must retain ordinary tree :e routing.
    require('config.git.diffview').install_quit_command()
  ]])
  vim.rpcrequest(child, 'nvim_input', ':e target.txt<CR>')
  choose('second')
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Panel :e did not use shared letter selection')
  evaluate([[vim.cmd.edit((...) .. '/one.txt'); require('nvim-tree.api').tree.focus()]])
  vim.rpcrequest(child, 'nvim_input', ' ff')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.b.telescope_quit_guard == true]],
    'File picker did not bind its close adapter')
  evaluate([[vim.fn.maparg('<Space>wq', 'n', false, true).callback()]])
  wait_for([[return vim.api.nvim_get_current_win() == tree and #vim.api.nvim_tabpage_list_wins(0) == 3]],
    'Shared close left picker panes or closed the preserved tree')
  find_file()
  choose('second')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt' and vim.api.nvim_get_current_win() == second]],
    'Telescope open did not use the chosen pane')
  evaluate([[
    assert(vim.deep_equal(vim.fn.winlayout(), layout), 'File search changed split layout')
    require('nvim-tree.api').tree.focus()
    local configuration = require('telescope.config').values
    local session = require('config.search.query_picker').open({
      title = 'Location fixture', entry_maker = function(entry) return entry end,
      sorter = configuration.generic_sorter({}), previewer = false,
    })
    session:finish({ { filename = (...) .. '/target.txt', lnum = 2, col = 3,
      display = 'location target', ordinal = 'location target' } })
  ]])
  wait_for([[
    if vim.bo.filetype ~= 'TelescopePrompt' then return false end
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker.manager and picker.manager:num_results() == 1 and picker:get_selection() ~= nil
  ]], 'Location picker did not finish')
  evaluate([[require('telescope.actions').select_default(vim.api.nvim_get_current_buf())]])
  choose('second')
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_win_get_cursor(0)[1] == 2]],
    'Location selection lost its destination or line')
  evaluate([[
    assert(vim.api.nvim_win_get_cursor(0)[2] == 2, 'Location selection lost its byte column: '
      .. vim.inspect({ cursor = vim.api.nvim_win_get_cursor(0), mode = vim.api.nvim_get_mode() }))
    assert(#vim.fn.gettagstack(second).items > 0, 'Location selection lost tag history')
    vim.cmd.edit((...) .. '/two.txt')
    require('nvim-tree.api').tree.focus()
  ]])
  find_file(' fr', true)
  destination()
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_current_win() == tree]], 'Find-files destination cancellation lost source focus')
  evaluate([[
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(second)) == (...) .. '/two.txt', 'Cancelled file choice opened a file')
    vim.api.nvim_set_current_win(second)
  ]])
  find_file()
  wait_for([[return vim.api.nvim_get_current_win() == second and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Editor-origin find-files unnecessarily asked for a pane')
  evaluate([[
    vim.cmd.split()
    local extra_window = vim.api.nvim_get_current_win()
    vim.cmd('quit')
    assert(not vim.api.nvim_win_is_valid(extra_window)
      and require('nvim-tree.api').tree.winid() == tree, 'Native pane quit closed a separate tree')
    _G.file_buffer = vim.api.nvim_get_current_buf()
    vim.fn.maparg('<Space>wq', 'n', false, true).callback()
    assert(not vim.api.nvim_win_is_valid(second), 'Close did not remove the pane')
    assert(vim.api.nvim_buf_is_valid(file_buffer), 'Close deleted the file buffer')
    assert(require('nvim-tree.api').tree.winid() == tree, 'Closing editor pane closed the tree')
    vim.api.nvim_set_current_win(first)
    vim.api.nvim_win_set_width(first, 60)
    local tree_width = vim.api.nvim_win_get_width(tree)
    require('config.navigation').open((...) .. '/target.txt', { command = 'vsplit' })
    local reopened = vim.api.nvim_get_current_win()
    assert(math.abs(vim.api.nvim_win_get_width(first) - vim.api.nvim_win_get_width(reopened)) <= 1,
      'Reopened split reused old proportions instead of equal weights')
    assert(vim.api.nvim_win_get_width(tree) == tree_width, 'Equal-size editor split resized the fixed-width tree')
    vim.fn.maparg('<Space>wq', 'n', false, true).callback()
    require('nvim-tree.api').tree.focus()
    vim.fn.maparg('<Space>wq', 'n', false, true).callback()
    assert(require('nvim-tree.api').tree.winid() == nil, 'Close did not delegate tree disposal')
    assert(vim.api.nvim_win_is_valid(first), 'Tree close removed the editor pane')
  ]])
  evaluate([[
    vim.cmd('rightbelow vsplit ' .. vim.fn.fnameescape((...) .. '/two.txt'))
    _G.upper = vim.api.nvim_get_current_win()
    vim.cmd('rightbelow split ' .. vim.fn.fnameescape((...) .. '/one.txt'))
    _G.lower = vim.api.nvim_get_current_win()
  ]])
  vim.rpcrequest(child, 'nvim_input', '<C-t>')
  wait_for([[return vim.bo.buftype == 'terminal' and vim.api.nvim_get_mode().mode == 't']],
    'Ctrl-T did not open the real ToggleTerm terminal')
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n']], 'Terminal escape did not leave input mode')
  evaluate([[
    _G.terminal_window = vim.api.nvim_get_current_win()
    _G.terminal_buffer = vim.api.nvim_get_current_buf()
    _G.terminal_job = vim.bo.channel
    _G.terminal_layout = vim.fn.winlayout()
    _G.terminal_sizes = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      terminal_sizes[window] = { vim.api.nvim_win_get_width(window), vim.api.nvim_win_get_height(window) }
    end
  ]])
  vim.rpcrequest(child, 'nvim_input', ':e target.txt<CR>')
  choose('lower')
  wait_for([[return vim.api.nvim_get_current_win() == lower and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Terminal :e did not open in the chosen editor pane')
  evaluate([[
    assert(vim.api.nvim_win_get_buf(terminal_window) == terminal_buffer and vim.bo[terminal_buffer].buftype == 'terminal',
      'Terminal :e replaced the shell buffer')
    assert(vim.fn.jobwait({ terminal_job }, 0)[1] == -1, 'Terminal :e stopped the shell job')
    assert(vim.deep_equal(vim.fn.winlayout(), terminal_layout), 'Terminal :e changed the nested layout')
    for window, size in pairs(terminal_sizes) do
      assert(vim.api.nvim_win_get_width(window) == size[1] and vim.api.nvim_win_get_height(window) == size[2],
        'Terminal :e resized an existing pane')
    end
    vim.api.nvim_set_current_win(terminal_window)
  ]])
  find_file()
  destination()
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_current_win() == terminal_window
    and vim.api.nvim_get_mode().mode:sub(1, 1) == 'n']],
    'Cancelling terminal find-files did not restore terminal focus')
  find_file(' fr', true)
  choose('upper')
  wait_for([[return vim.api.nvim_get_current_win() == upper and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Terminal find-files did not share pane selection')
  evaluate([[
    vim.api.nvim_win_close(upper, true)
    vim.api.nvim_win_close(lower, true)
    vim.api.nvim_set_current_win(terminal_window)
  ]])
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n']], 'Terminal did not accept editor commands')
  vim.rpcrequest(child, 'nvim_input', ':e two.txt<CR>')
  wait_for([[return vim.api.nvim_get_current_win() == first and vim.api.nvim_buf_get_name(0) == (...) .. '/two.txt']],
    'Terminal :e did not automatically select the sole editor')
  evaluate([[vim.api.nvim_set_current_win(terminal_window)]])
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n']], 'Terminal did not leave input mode before search')
  find_file()
  wait_for([[return vim.api.nvim_get_current_win() == first and vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']],
    'Terminal find-files did not automatically select the sole editor')
  evaluate([[
    require('nvim-tree.api').tree.open({ path = ... })
    _G.tree = require('nvim-tree.api').tree.winid()
    vim.api.nvim_win_close(first, true)
    vim.api.nvim_set_current_win(terminal_window)
  ]])
  vim.rpcrequest(child, 'nvim_input', '<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode:sub(1, 1) == 'n']], 'Terminal-only layout did not leave input mode')
  vim.rpcrequest(child, 'nvim_input', ':e one.txt<CR>')
  wait_for([[return vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) == (...) .. '/one.txt']],
    'Terminal :e did not create an editor when only panels remained')
  evaluate([[
    assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Terminal-only open created unexpected panes')
    assert(vim.wo.number == vim.go.number and vim.wo.relativenumber == vim.go.relativenumber,
      'Editor created from terminal inherited hidden line numbers')
    assert(vim.api.nvim_win_get_buf(terminal_window) == terminal_buffer
      and vim.fn.jobwait({ terminal_job }, 0)[1] == -1, 'File opening damaged the terminal session')
    _G.covered = vim.api.nvim_get_current_buf()
    _G.editor = vim.api.nvim_get_current_win()
    _G.cover_layout = vim.fn.winlayout()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'saved from dialog' })
    vim.o.hidden = false
  ]])
  vim.rpcrequest(child, 'nvim_input', ':e two.txt<CR>')
  answer_write('n')
  wait_for([[return vim.api.nvim_get_current_win() == editor and vim.api.nvim_get_current_buf() == covered]],
    'Cancel replaced the current file')
  evaluate([[assert(vim.bo.modified and vim.deep_equal(vim.fn.winlayout(), cover_layout), 'Cancel lost edits or changed the layout')]])
  vim.rpcrequest(child, 'nvim_input', ':e two.txt<CR>')
  answer_write('y')
  wait_for([[return vim.api.nvim_get_current_win() == editor and vim.api.nvim_buf_get_name(0) == (...) .. '/two.txt']],
    'Save did not complete the replacement')
  evaluate([[
    assert((vim.api.nvim_buf_is_valid(covered) and not vim.bo[covered].buflisted and not vim.bo[covered].modified) and vim.fn.readfile((...) .. '/one.txt')[1] == 'saved from dialog',
      'Save retained the covered buffer or failed to write its edits')
    _G.covered = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'discarded from dialog' })
  ]])
  vim.rpcrequest(child, 'nvim_input', ':e one.txt<CR>')
  answer_write('n')
  wait_for([[return vim.api.nvim_get_current_buf() == covered and vim.bo.modified]],
    'No did not keep unwritten content')
  vim.rpcrequest(child, 'nvim_input', ':e one.txt<CR>')
  answer_write('y')
  wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/one.txt']], 'Write-then-open did not open the new file')
  evaluate([[
    assert((vim.api.nvim_buf_is_valid(covered) and not vim.bo[covered].buflisted and not vim.bo[covered].modified) and vim.fn.readfile((...) .. '/two.txt')[1] == 'discarded from dialog',
      'Yes did not write before replacing the covered buffer')
    assert(vim.deep_equal(vim.fn.winlayout(), cover_layout), 'Replacing files changed the layout')
    _G.visible = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'remain visible in the original pane' })
    require('config.navigation').open((...) .. '/two.txt', { command = 'vsplit' })
    assert(vim.api.nvim_buf_get_name(0) == (...) .. '/two.txt' and vim.api.nvim_buf_is_valid(visible)
      and vim.bo[visible].modified, 'Explicit split prompted for or discarded the still-visible file')
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, 'rf')
assert(passed, failure)
print('Installed navigation: gx replacement/history/dirty cancellation, window focus badges, and file routing pass')
