-- Real completion and Telescope overrides for cursor shortcuts.
-- nvim --headless -u NONE -i NONE -l tests/startup/movement_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = directory } })
local function evaluate(source)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, {})
end
local function wait_for(source, message)
  assert(vim.wait(3000, function() return evaluate(source) end, 10), message)
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 30, { rgb = true })
  evaluate([[
    vim.cmd('enew!')
    local lines = {}
    for index = 1, 200 do lines[index] = 'line ' .. index end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 80, 0 })
    vim.cmd('normal! zz')
    vim.wo.scroll = 0
    vim.g.half_page_distance = vim.wo.scroll
  ]])
  input('<C-d>')
  wait_for([[return vim.api.nvim_win_get_cursor(0)[1] == 80 + vim.g.half_page_distance]],
    'Normal Ctrl-d did not move down half a page')
  input('<C-u>')
  wait_for([[return vim.api.nvim_win_get_cursor(0)[1] == 80]],
    'Normal Ctrl-u did not move up half a page')
  evaluate([[
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '  alpha tail' })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
  ]])
  input('i')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i']], 'Insert mode did not start')
  wait_for([[return require('lualine').get_config().sections.lualine_a ~= nil
    and vim.api.nvim_eval_statusline(vim.wo.statusline, {}).str:find('INSERT', 1, true) ~= nil]],
    'Statusline did not display Insert mode')
  evaluate([[
    vim.g.exit_insert_events = 0
    vim.api.nvim_create_autocmd('InsertLeave', {
      callback = function() vim.g.exit_insert_events = vim.g.exit_insert_events + 1 end,
    })
  ]])
  input('<C-c>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n' and vim.g.exit_insert_events == 1
    and vim.api.nvim_eval_statusline(vim.wo.statusline, {}).str:find('NORMAL', 1, true) ~= nil]],
    'Ctrl-c did not run InsertLeave and refresh the mode label')
  input('v<C-c>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Ctrl-c did not exit Visual mode')
  input('i')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i']], 'Insert mode did not restart')
  evaluate([[
    local cmp = require('cmp')
    cmp.register_source('movement_test', {
      complete = function(_, _, callback)
        callback({ items = { { label = 'alphabet' }, { label = 'alpine' } }, isIncomplete = false })
      end,
    })
    cmp.setup.buffer({ completion = { autocomplete = false }, sources = { { name = 'movement_test' } } })
  ]])
  for _, shortcut in ipairs({ '<C-a>', '<C-e>', '<C-h>', '<C-l>' }) do
    evaluate([[
      vim.api.nvim_win_set_cursor(0, { 1, 7 })
      require('cmp').complete()
    ]])
    wait_for([[return require('cmp').visible()]], 'Completion popup did not open')
    input(shortcut)
    local column = ({
      ['<C-a>'] = 0, ['<C-e>'] = 12,
      ['<C-h>'] = 6, ['<C-l>'] = 8,
    })[shortcut]
    wait_for(('return not require("cmp").visible() and vim.api.nvim_win_get_cursor(0)[2] == %d'):format(column),
      shortcut .. ' did not dismiss completion and move in one press')
    assert(evaluate([[return vim.api.nvim_get_current_line()]]) == '  alpha tail',
      'Completion movement changed buffer text')
  end
  evaluate([[
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    require('cmp').complete()
  ]])
  wait_for([[return require('cmp').visible()]], 'Completion popup did not open for navigation')
  evaluate([[
    require('cmp').select_next_item()
    require('cmp').select_next_item()
  ]])
  input('<C-p>')
  wait_for([[local entry = require('cmp').get_selected_entry()
    return require('cmp').visible() and entry and entry.completion_item.label == 'alphabet']],
    'Ctrl-p did not retain completion navigation')
  evaluate([[
    require('cmp').abort()
    vim.opt.clipboard = ''
  ]])
  input('<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Completion navigation did not end')
  evaluate([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '  alpha tail' })
    vim.fn.setreg('"', 'internal register must not be pasted', 'v')
    vim.g.clipboard = {
      name = 'movement-test-clipboard',
      copy = { ['+'] = function() end, ['*'] = function() end },
      paste = {
        ['+'] = function() return { { 'X', '  Y' }, 'v' } end,
        ['*'] = function() return { { 'primary selection must not be pasted' }, 'v' } end,
      },
      cache_enabled = 0,
    }
    vim.fn['provider#clipboard#Executable']()
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
  ]])
  input('i')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i']], 'Insert mode did not start for paste')
  input('<C-r><C-o>+')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i' and not require('cmp').visible()
    and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '  alphaX', '  Y tail' })]],
    'Native register paste did not preserve multiline text')
  input('<C-r><C-o>+')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i'
    and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '  alphaX', '  YX', '  Y tail' })]],
    'Repeated native register paste failed')
  input('<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Insert mode did not end')
  evaluate([[
    vim.g.command_paste_text = '中文 café'
    local clipboard_provider = vim.g.clipboard
    clipboard_provider.paste['+'] = function() return { { vim.g.command_paste_text }, 'v' } end
    vim.g.clipboard = clipboard_provider
    vim.fn['provider#clipboard#Executable']()
  ]])
  for _, prompt in ipairs({ '/', '?', ':' }) do
    input(prompt .. 'leftright<Left><Left><Left><Left><Left><C-r>+')
    wait_for([[return vim.api.nvim_get_mode().mode == 'c'
      and vim.fn.getcmdline() == 'left中文 caféright']],
      prompt .. ' native register paste did not insert the system clipboard at the cursor')
    input('<C-c>')
    wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Command line did not close')
  end
  evaluate([[vim.fn.histadd('search', 'stale search history')]])
  input('/<C-p>')
  wait_for([[return vim.fn.getcmdline() == 'stale search history']],
    'Command-line Ctrl-p did not retain native search history')
  input('<C-c>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Search history prompt did not close')
  evaluate([[vim.g.command_paste_text = 'A\nB' .. string.char(8) .. 'C']])
  input(':<C-r><C-r>+')
  wait_for([[return vim.api.nvim_get_mode().mode == 'c'
    and vim.fn.getcmdline() == vim.g.command_paste_text]],
    'Command-line paste executed a newline or interpreted a control character')
  input('<C-c>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Literal paste prompt did not close')
  evaluate([[
    require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('state') })
  ]])
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Telescope prompt did not open')
  input('alphaz<BS><C-a>X<C-e>Y')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker:_get_prompt() == 'XalphaY'
  ]], 'Telescope did not honor beginning/end movement')
  input('<C-h>Z<C-l>W')
  wait_for([[
    local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
    return picker:_get_prompt() == 'XalphaZYW'
  ]], 'Telescope Ctrl-h/l did not move through the query')
  input('<C-c>')
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'n']],
    'Telescope Ctrl-c did not leave Insert mode while preserving the picker')
  input('<C-q>')
  wait_for([[return vim.bo.filetype ~= 'TelescopePrompt']], 'Telescope did not close')
  input('<Esc>:let g:movement_probe = "mid<C-a><C-e>dle"<CR>')
  wait_for([[return vim.g.movement_probe == 'middle']], 'Command-line movement failed')
  evaluate([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first', 'second', 'third' })
    vim.api.nvim_win_set_cursor(0, { 2, 2 })
  ]])
  input('i<C-h><C-k>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i'
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 })]],
    'Insert Ctrl-h/k did not move left/up')
  input('<C-j><C-l>X')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i'
    and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'first', 'seXcond', 'third' })]],
    'Insert Ctrl-j/l inserted a newline or failed to move down/right')
end
local succeeded, failure = xpcall(check, debug.traceback)
pcall(vim.fn.jobstop, child)
vim.fn.delete(directory, 'rf')
assert(succeeded, failure)
print('Installed cursor movement checks passed')
