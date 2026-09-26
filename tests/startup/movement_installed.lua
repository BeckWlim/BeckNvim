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
        callback({ items = { { label = 'alphabet' } }, isIncomplete = false })
      end,
    })
    cmp.setup.buffer({ completion = { autocomplete = false }, sources = { { name = 'movement_test' } } })
  ]])
  for _, shortcut in ipairs({ '<C-a>', '<C-e>', '<C-Left>', '<C-Right>', '<C-h>', '<C-l>' }) do
    evaluate([[
      vim.api.nvim_win_set_cursor(0, { 1, 7 })
      require('cmp').complete()
    ]])
    wait_for([[return require('cmp').visible()]], 'Completion popup did not open')
    input(shortcut)
    local column = ({
      ['<C-a>'] = 0, ['<C-e>'] = 12, ['<C-Left>'] = 2, ['<C-Right>'] = 8,
      ['<C-h>'] = 6, ['<C-l>'] = 8,
    })[shortcut]
    wait_for(('return not require("cmp").visible() and vim.api.nvim_win_get_cursor(0)[2] == %d'):format(column),
      shortcut .. ' did not dismiss completion and move in one press')
    assert(evaluate([[return vim.api.nvim_get_current_line()]]) == '  alpha tail',
      'Completion movement changed buffer text')
  end
  evaluate([[
    vim.opt.clipboard = ''
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    require('cmp').complete()
  ]])
  wait_for([[return require('cmp').visible()]], 'Completion popup did not open for Backspace')
  input('<C-d>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i' and not require('cmp').visible()
    and vim.api.nvim_get_current_line() == '  alph tail']],
    'Ctrl-d did not delete the preceding character with completion open')
  input('a')
  wait_for([[return vim.api.nvim_get_current_line() == '  alpha tail']], 'Typing after Backspace failed')
  evaluate([[
    vim.fn.setreg('"', 'X\n  Y', 'v')
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    require('cmp').complete()
  ]])
  wait_for([[return require('cmp').visible()]], 'Completion popup did not open for paste')
  input('<C-p>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i' and not require('cmp').visible()
    and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '  alphaX', '  Y tail' })]],
    'Ctrl-p did not paste literal multiline text and dismiss completion')
  input('<C-p>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i'
    and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '  alphaX', '  YX', '  Y tail' })]],
    'Ctrl-p did not paste with completion closed')
  input('<Esc>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'n']], 'Insert mode did not end')
  evaluate([[
    require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('state') })
  ]])
  wait_for([[return vim.bo.filetype == 'TelescopePrompt' and vim.api.nvim_get_mode().mode == 'i']],
    'Telescope prompt did not open')
  input('alphaz<C-d><C-a>X<C-e>Y')
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
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local alpha = beta + gamma' })
    vim.bo.filetype = 'lua'
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
  ]])
  input('<C-Right>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'v' and vim.api.nvim_win_get_cursor(0)[2] == 10]],
    'Ctrl-Right did not select the current identifier')
  input('<C-Right>')
  wait_for([[return vim.fn.getpos('v')[3] == 15 and vim.api.nvim_win_get_cursor(0)[2] == 17]],
    'Ctrl-Right did not skip whitespace and punctuation to the next identifier')
  input('<C-Left>')
  wait_for([[return vim.fn.getpos('v')[3] == 7 and vim.api.nvim_win_get_cursor(0)[2] == 10]],
    'Ctrl-Left did not return to the previous identifier')
  input('<Esc>i<C-Left>')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i' and vim.api.nvim_win_get_cursor(0)[2] == 6]],
    'Insert Ctrl-Left did not return to the current word start')
  input('<C-Right>X')
  wait_for([[return vim.api.nvim_get_mode().mode == 'i'
    and vim.api.nvim_get_current_line() == 'local alpha = Xbeta + gamma']],
    'Insert Ctrl-Right did not skip punctuation or replaced selected text')
  evaluate([[
    vim.bo.filetype = ''
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'α_one,   β_two', '', '  final' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.fn.setreg('/', 'preserved_search')
  ]])
  input('<C-Left><C-Right>')
  wait_for([[return vim.api.nvim_win_get_cursor(0)[1] == 1 and vim.api.nvim_win_get_cursor(0)[2] == 10]],
    'Insert movement failed on Unicode words without a parser')
  input('<C-Right><C-Right>')
  wait_for([[return vim.api.nvim_win_get_cursor(0)[1] == 3 and vim.api.nvim_win_get_cursor(0)[2] == 2]],
    'Insert movement did not cross blank lines or stop at the buffer end')
  input('<C-Left>')
  wait_for([[return vim.api.nvim_win_get_cursor(0)[1] == 1 and vim.api.nvim_win_get_cursor(0)[2] == 10]],
    'Insert movement did not return across blank lines')
  assert(evaluate([[return vim.fn.getreg('/')]]) == 'preserved_search', 'Movement changed search history')
  evaluate([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first', 'second', 'third' })
    vim.api.nvim_win_set_cursor(0, { 2, 2 })
  ]])
  input('<C-h><C-k>')
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
