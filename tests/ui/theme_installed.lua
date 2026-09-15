-- Real theme plugins, Telescope preview/rollback, and open editor surfaces.
-- nvim --headless -u NONE -i NONE -l tests/ui/theme_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local project = directory .. '/project'
vim.fn.mkdir(project, 'p')
local function git(arguments)
  local command = { 'git', '-C', project }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
end
git({ 'init', '-q' })
vim.fn.writefile({ 'local value = 1' }, project .. '/sample.lua')
git({ 'add', 'sample.lua' })
git({ '-c', 'user.name=Theme Test', '-c', 'user.email=theme@example.invalid',
  '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture' })
vim.fn.writefile({ 'local value = 2' }, project .. '/sample.lua')
local child_errors = {}
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, {
  rpc = true,
  env = { XDG_STATE_HOME = directory },
  on_stderr = function(_, lines) vim.list_extend(child_errors, lines) end,
})
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function wait_for(source, message)
  assert(vim.wait(5000, function() return evaluate(source) end, 20), message)
end
local function open_picker(target)
  evaluate([[
    require('config.ui.theme').pick()
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    picker:set_prompt(...)
  ]], { target })
  wait_for([[
    local entry = require('telescope.actions.state').get_selected_entry()
    return entry and entry.value == vim.g.theme_test_target and require('config.ui.theme').current().name == entry.value
  ]], 'Picker did not preview the requested theme')
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 36, { rgb = true })
  evaluate([[
    require('telescope').setup({ defaults = {
      history = { path = vim.fn.stdpath('state') .. '/telescope_history' },
    } })
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local number = 42', 'print(number)' })
    vim.bo.filetype = 'lua'
    vim.g.theme_test_buffer = vim.api.nvim_get_current_buf()
    vim.g.theme_test_tick = vim.api.nvim_buf_get_changedtick(0)
    vim.g.theme_test_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
  ]])
  local variants = { 'monokai', 'vscode-dark', 'darcula-dark',
      'tokyonight-night', 'catppuccin-mocha', 'catppuccin-latte',
      'gruvbox-dark', 'paper-light' }
  for _, name in ipairs(variants) do
    evaluate([[
      local name = ...
      assert(require('config.ui.theme').select(name), name .. ': selection failed')
      local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
      local contrast = require('config.ui.palette').contrast
      if name == 'paper-light' then
        assert(vim.o.background == 'light' and normal.bg == 0xE6E3DB,
          'Paper Light did not load its softer light background')
        for _, group in ipairs({ 'String', 'Function', 'Type', 'Statement', 'Number', 'Special' }) do
          assert(contrast(vim.api.nvim_get_hl(0, { name = group, link = false }).fg, normal.bg) >= 4.5,
            'Paper Light syntax is unreadable: ' .. group)
        end
      end
      if name == 'catppuccin-latte'
          or name == 'paper-light' then
        assert(vim.o.background == 'light', name .. ': light variant was not selected')
        for _, group in ipairs({ 'Normal', 'CursorLine', 'CurrentCodeScope', 'TreesitterContext',
          'lualine_a_normal', 'lualine_c_normal' }) do
          local background = vim.api.nvim_get_hl(0, { name = group }).bg
          assert(background and contrast(background, 0) > contrast(background, 0xFFFFFF),
            name .. ': retained a dark background in ' .. group)
        end
      end
      for _, group in ipairs({ 'NormalFloat', 'TelescopeSelection', 'PmenuSel',
        'TreesitterContext', 'RenderMarkdownMermaidEdgeLabel', 'TranslationNotification' }) do
        local role = vim.api.nvim_get_hl(0, { name = group, link = false })
        assert(contrast(role.fg, role.bg or normal.bg) >= 4.5, name .. ': unreadable ' .. group)
      end
      assert(vim.api.nvim_get_current_buf() == vim.g.theme_test_buffer, 'Theme replaced the current buffer')
      assert(vim.api.nvim_buf_get_changedtick(0) == vim.g.theme_test_tick, 'Theme changed buffer content')
      assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 }), 'Theme moved the cursor')
      local footer = vim.api.nvim_get_hl(0, { name = 'lualine_c_normal', link = false })
      local native_footer = vim.api.nvim_get_hl(0, { name = 'StatusLine', link = false })
      assert(footer.bg == native_footer.bg and footer.bg ~= normal.bg
          and contrast(footer.bg, normal.bg) < 1.5 and contrast(footer.fg, footer.bg) >= 4.5,
        name .. ': statusline lost its subtle shared contrast')
    ]], { name })
    vim.wait(30)
  end
  evaluate([[
    local names = require('config.ui.theme').names()
    for _, name in ipairs({ 'vscode-light', 'gruvbox-light', 'tokyonight-day', 'morning' }) do
      assert(not vim.tbl_contains(names, name), 'Uncurated native variant entered the picker: ' .. name)
    end
  ]])
  evaluate([[require('config.ui.theme').select('catppuccin-latte')]])
  wait_for([[
    local path = require('config.ui.theme').state_path()
    return vim.fn.filereadable(path) == 1
      and vim.json.decode(table.concat(vim.fn.readfile(path))).name == 'catppuccin-latte'
  ]], 'Final theme selection did not finish saving')
  evaluate([[
    vim.g.colors_name = nil
    vim.o.background = 'dark'
    vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'monokai' } }, {})
    vim.fn.delete(require('config.ui.theme').state_path())
  ]])
  -- Live preview is transient; normal-mode Ctrl-q restores name, variant, and position.
  evaluate([[vim.g.theme_test_target = 'paper-light']])
  open_picker('paper-light')
  evaluate([[
    vim.cmd('stopinsert')
    vim.api.nvim_feedkeys(vim.keycode('<C-q>'), 'xt', false)
  ]])
  wait_for([[return vim.g.colors_name == 'monokai' and vim.api.nvim_get_current_buf() == vim.g.theme_test_buffer]],
    'Cancel did not restore the previous theme and buffer')
  assert(evaluate([[return vim.fn.filereadable(require('config.ui.theme').state_path())]]) == 0,
    'Preview or cancellation saved a selection')
  -- Confirm through the actual Enter mapping, then restore in another setup.
  evaluate([[vim.g.theme_test_target = 'paper-light']])
  open_picker('paper-light')
  evaluate([[vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'xt', false)]])
  wait_for([[
    local path = require('config.ui.theme').state_path()
    return vim.fn.filereadable(path) == 1
      and vim.json.decode(table.concat(vim.fn.readfile(path))).name == 'paper-light'
  ]], 'Picker confirmation was not persisted')
  evaluate([[require('config.ui.theme').setup()]])
  wait_for([[return require('config.ui.theme').current().name == 'paper-light']], 'Saved choice was not restored')
  -- A plugin loaded after the switch inherits the same palette.
  evaluate([[require('nvim-tree.api').tree.open()]])
  wait_for([[
    return vim.api.nvim_get_hl(0, { name = 'NvimTreeNormal' }).bg
      == vim.api.nvim_get_hl(0, { name = 'Normal' }).bg
  ]], 'File tree loaded with a stale background')
  evaluate([[
    local windows = vim.api.nvim_list_wins()
    vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'monokai' } }, {})
    assert(vim.deep_equal(windows, vim.api.nvim_list_wins()), 'Theme switch rebuilt the open tree')
    require('nvim-tree.api').tree.close()
  ]])
  -- Recolor a live native Diffview without changing its selected file or pane state.
  evaluate([[
    vim.api.nvim_set_current_dir(...)
    vim.api.nvim_cmd({ cmd = 'DiffviewOpen' }, {})
  ]], { project })
  wait_for([[
    local view = require('diffview.lib').get_current_view()
    return view ~= nil and view.cur_entry ~= nil and view.panel.cur_file ~= nil
  ]], 'Diffview did not open the disposable repository')
  evaluate([[
    local view = require('diffview.lib').get_current_view()
    local entry = view.cur_entry
    local selected_file = view.panel.cur_file
    local windows = vim.api.nvim_tabpage_list_wins(0)
    for _, name in ipairs({ 'morning', 'monokai' }) do
      vim.api.nvim_cmd({ cmd = 'colorscheme', args = { name } }, {})
      vim.wait(30)
      assert(require('diffview.lib').get_current_view() == view and view.cur_entry == entry
        and view.panel.cur_file == selected_file, 'Theme switch changed Diffview selection')
      assert(vim.deep_equal(windows, vim.api.nvim_tabpage_list_wins(0)), 'Theme switch rebuilt Diffview panes')
      assert(vim.api.nvim_get_hl(0, { name = 'DiffviewNormal' }).bg
        == vim.api.nvim_get_hl(0, { name = 'Normal' }).bg, 'Diffview retained the previous theme background')
    end
    vim.api.nvim_cmd({ cmd = 'DiffviewClose' }, {})
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:find('stack traceback', 1, true) and not messages:find('Failed to run', 1, true), messages)
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, tostring(failure) .. '\n' .. table.concat(child_errors, '\n'))
print('Installed themes, live preview, cancellation, persistence, file tree, and Diffview passed')
