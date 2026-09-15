-- nvim --headless -u NONE -i NONE -l tests/search/telescope_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.fn.writefile({ 'local value = 1', 'print(value)' }, directory .. '/sample.lua')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = directory } })
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
local function open_picker()
  evaluate([[
    require('telescope.builtin').find_files({ cwd = ... })
    vim.g.pane_test_prompt = vim.api.nvim_get_current_buf()
  ]], { directory })
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt)
    local previewer = picker.previewer
    return previewer and previewer.state and previewer.state.bufnr
      and vim.api.nvim_buf_get_lines(previewer.state.bufnr, 0, 1, false)[1] == 'local value = 1'
  ]], 'Native file preview did not load')
  input('<Esc>')
end
local function focus_preview()
  input('<Tab>')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt)
    return vim.api.nvim_get_current_win() == picker.previewer.state.winid
  ]], 'Tab did not focus the native preview')
end
local function expect_closed()
  wait_for([[
    return vim.deep_equal(vim.api.nvim_list_wins(), vim.g.pane_test_windows)
      and vim.api.nvim_get_current_buf() == vim.g.pane_test_source
  ]], 'Ctrl-Q left orphaned panes or lost the source window')
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  evaluate([[vim.api.nvim__inspect_cell(1, 0, 0)]])
  evaluate([[
    require('telescope').setup({ defaults = { history = { path = ... } } })
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved source text' })
    vim.g.pane_test_source = vim.api.nvim_get_current_buf()
    vim.g.pane_test_windows = vim.api.nvim_list_wins()
    vim.g.pane_test_tick = vim.api.nvim_buf_get_changedtick(0)
  ]], { directory .. '/history' })
  -- Exercise the actual Space-fw key and native streamed finder, then change
  -- selection repeatedly: renderer writes must never raise W10/hit-enter.
  vim.fn.writefile({ 'local function sample_first() end', 'local function sample_second() end' },
    directory .. '/definitions.lua')
  evaluate([[vim.cmd.cd(...)]], { directory })
  input(' fw')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt']], 'Space-fw did not open definitions')
  evaluate([[vim.g.pane_test_prompt = vim.api.nvim_get_current_buf()]])
  input('sample')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt)
    return picker.manager and picker.manager:num_results() >= 2
      and require('telescope.actions.state').get_selected_entry() ~= nil
  ]], 'Workspace definition results did not stream')
  input('<Esc>')
  local selected_before = evaluate([[
    return require('telescope.actions.state').get_selected_entry().lnum
  ]])
  input('j')
  assert(evaluate([[return require('telescope.actions.state').get_selected_entry().lnum]])
    ~= selected_before, 'Result-list cursor did not advance')
  for _ = 1, 5 do input('kj') end
  evaluate([[
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:match('W10:') and not messages:match('E21:'), messages)
    assert(not vim.api.nvim_get_mode().blocking, 'Result movement entered a blocking prompt')
  ]])
  input('<C-q>')
  expect_closed()
  vim.fn.delete(directory .. '/definitions.lua')
  -- Switch every bundled theme with the real picker still open. Sample actual
  -- corner/margin cells, including inactive panes, rather than just group names.
  open_picker()
  for _, theme_name in ipairs({ 'monokai', 'vscode-dark', 'darcula-dark', 'tokyonight-night',
      'catppuccin-mocha', 'catppuccin-latte', 'gruvbox-dark', 'paper-light' }) do
    evaluate([[
      assert(require('config.ui.theme').select(...))
      vim.cmd('redraw!')
    ]], { theme_name })
    vim.wait(30)
    evaluate([[
      local background = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg
      local palette = require('config.ui.palette')
      local footer = vim.api.nvim_get_hl(0, { name = 'lualine_c_normal', link = false })
      local native_footer = vim.api.nvim_get_hl(0, { name = 'StatusLine', link = false })
      assert(footer.bg == native_footer.bg and footer.bg ~= background
          and palette.contrast(footer.bg, background) < 1.5
          and palette.contrast(footer.fg, footer.bg) >= 4.5,
        'Footer must share the native statusline palette with subtle background contrast')
      local picker = require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt)
      for _, pane in ipairs({ picker.layout.prompt, picker.layout.results, picker.layout.preview }) do
        local border = pane.border.winid
        local position = vim.api.nvim_win_get_position(border)
        local height = vim.api.nvim_win_get_height(border)
        local width = vim.api.nvim_win_get_width(border)
        for _, offset in ipairs({ { 0, 0 }, { 0, width - 1 },
            { height - 1, 0 }, { height - 1, width - 1 },
            { 1, 0 }, { height - 2, width - 1 }, { height - 1, math.floor(width / 2) } }) do
          local cell = vim.api.nvim__inspect_cell(1, position[1] + offset[1], position[2] + offset[2])
          assert((cell[2].background or background) == background,
            'Telescope corner has a contrasting backing rectangle')
          assert(cell[1] == ' ' or cell[1] == ''
              or (cell[2].foreground and require('config.ui.palette').contrast(cell[2].foreground, background) >= 3),
            'Telescope outline lacks contrast: ' .. tostring(vim.g.colors_name) .. ' ' .. vim.inspect(cell))
        end
        local content_position = vim.api.nvim_win_get_position(pane.winid)
        local cell = vim.api.nvim__inspect_cell(1,
          content_position[1] + vim.api.nvim_win_get_height(pane.winid) - 1,
          content_position[2] + vim.api.nvim_win_get_width(pane.winid) - 1)
        assert((cell[2].background or background) == background, 'Telescope empty margin has a different background')
      end
      local backdrop = vim.api.nvim__inspect_cell(1, 10, 119)
      assert((backdrop[2].background or background) == background, 'Inactive editor no longer matches the picker')
    ]])
  end
  input('<C-q>')
  expect_closed()
  -- :q cannot split the picker, and q/Escape do not dismiss it.
  for _, pane in ipairs({ 'prompt', 'results', 'preview' }) do
    open_picker()
    if pane == 'preview' then focus_preview()
    elseif pane == 'results' then
      evaluate([[
        local picker = require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt)
        vim.cmd(('noautocmd call nvim_set_current_win(%d)'):format(picker.results_win))
      ]])
    end
    evaluate([[
      local windows = vim.api.nvim_list_wins()
      local succeeded = pcall(vim.cmd, 'q')
      assert(not succeeded and vim.deep_equal(windows, vim.api.nvim_list_wins()), ':q closed part of the picker')
    ]])
    input('q<Esc>')
    assert(evaluate([[return vim.api.nvim_win_is_valid(require('telescope.actions.state').get_current_picker(vim.g.pane_test_prompt).prompt_win)]]))
    input('<C-q>')
    expect_closed()
  end
  -- Prompt input, Visual modes, operator pending, and command-line entry share one close action.
  for _, mode_keys in ipairs({ 'i', 'R', 'v', 'V', '<C-v>', 'gh', 'd', ':' }) do
    open_picker()
    if mode_keys == '<C-v>' then
      evaluate([[vim.cmd('normal! ' .. vim.keycode('<C-v>'))]])
    elseif mode_keys == 'gh' then
      evaluate([[vim.cmd('normal! gh')]])
    else input(mode_keys) end
    input('<C-q>')
    expect_closed()
  end
  open_picker()
  focus_preview()
  local preview_tick = evaluate([[return vim.api.nvim_buf_get_changedtick(0)]])
  for _, key in ipairs({ 'i', 'a', 'o', 'R' }) do
    input(key)
    assert(evaluate([[return vim.api.nvim_get_mode().mode]]) == 'n', 'Preview entered editing mode with ' .. key)
  end
  evaluate([[vim.cmd('startinsert')]])
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Preview accepted Insert mode through a command')
  assert(evaluate([[return vim.api.nvim_buf_get_changedtick(0)]]) == preview_tick, 'Preview text was edited')
  assert(evaluate([[return not vim.bo.modifiable and not vim.bo.readonly]]), 'Focused source preview is writable')
  input('<Tab>')
  wait_for([[return vim.api.nvim_get_current_buf() == vim.g.pane_test_prompt]], 'Tab lost the prompt')
  focus_preview()
  input('<C-q>')
  expect_closed()
  -- If a window is removed externally, native teardown must retire the other panes.
  open_picker()
  focus_preview()
  evaluate([[vim.api.nvim_win_close(0, true)]])
  expect_closed()
  -- A rejected :q must leave a lower file-tree layer intact.
  evaluate([[
    require('nvim-tree.api').tree.open()
    vim.g.pane_test_tree_windows = vim.api.nvim_list_wins()
  ]])
  open_picker()
  evaluate([[
    assert(not pcall(vim.cmd, 'q'))
    for _, window in ipairs(vim.g.pane_test_tree_windows) do
      assert(vim.api.nvim_win_is_valid(window), ':q dismissed the preserved file tree')
    end
  ]])
  input('<C-q>')
  evaluate([[require('nvim-tree.api').tree.close()]])
  expect_closed()
  evaluate([[
    assert(vim.api.nvim_buf_get_changedtick(vim.g.pane_test_source) == vim.g.pane_test_tick,
      'Picker changed the underlying source')
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed Telescope pane, mode, and read-only preview checks passed')
