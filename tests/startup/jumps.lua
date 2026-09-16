-- Separate processes share ShaDa, but navigation starts with the current run.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local history_path = directory .. '/shared.shada'
local report_path = directory .. '/report.json'
local before_path = directory .. '/before.txt'
local after_path = directory .. '/after.txt'
local current_path = directory .. '/current.txt'
local destination_path = directory .. '/destination.txt'
for _, path in ipairs({ before_path, after_path, current_path, destination_path }) do
  vim.fn.writefile({ 'First line', 'Second line' }, path)
end

local function run_process(body, configured, startup_arguments)
  local init_path = directory .. '/init.lua'
  local init_lines = {
    ('vim.opt.runtimepath:prepend(%q)'):format(vim.fn.getcwd()),
    -- These disposable fixtures must be saved despite ShaDa's /tmp exclusion.
    [[vim.opt.shada = "!,'100,<50,s10,h"]],
    configured and [[require('config.startup.autocmds').setup()]] or '',
    [[vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()]],
    [[local passed, failure = xpcall(function()]],
    body,
    [[end, debug.traceback)]],
    [[if not passed then vim.api.nvim_err_writeln(failure); vim.cmd('cquit'); return end]],
    [[vim.cmd('qa!')]],
    [[end })]],
  }
  vim.fn.writefile(vim.split(table.concat(init_lines, '\n'), '\n', { plain = true }), init_path)
  local command = {
    vim.v.progpath, '--headless', '-n', '-u', init_path, '-i', history_path,
  }
  vim.list_extend(command, startup_arguments or {})
  local result = vim.system(command, { text = true }):wait(10000)
  assert(result.code == 0, result.stderr)
end

run_process(([[
  vim.api.nvim_cmd({ cmd = 'edit', args = { %q } }, {})
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  vim.cmd("normal! ma")
  vim.api.nvim_cmd({ cmd = 'edit', args = { %q } }, {})
  vim.fn.setreg('a', 'persistent register')
  vim.fn.histadd('search', 'persistent search')
]]):format(before_path, after_path), true)

-- Prove the shared file contains history that an unconfigured process imports.
run_process(([[
  local paths = {}
  for _, entry in ipairs(vim.fn.getjumplist()[1]) do
    paths[#paths + 1] = vim.api.nvim_buf_get_name(entry.bufnr)
  end
  vim.fn.writefile(paths, %q)
]]):format(report_path), false)
assert(vim.list_contains(vim.fn.readfile(report_path), before_path),
  'The cross-process fixture did not save and restore its jump history')

run_process(([[
  assert(#vim.fn.getjumplist()[1] == 0, 'Startup imported another process\'s jumps')
  assert(vim.list_contains(vim.v.oldfiles, %q), 'Startup discarded recent files')
  assert(vim.fn.getreg('a') == 'persistent register', 'Startup discarded saved registers')
  assert(vim.fn.histget('search', -1) == 'persistent search', 'Startup discarded search history')
  vim.api.nvim_cmd({ cmd = 'edit', args = { %q } }, {})
  assert(vim.fn.line("'a") == 2, 'Startup discarded saved file marks')
  -- Reset this deliberate old-file visit before testing new navigation.
  vim.cmd('clearjumps')
  vim.api.nvim_cmd({ cmd = 'edit', args = { %q } }, {})
  vim.cmd('clearjumps')
  local current = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  vim.api.nvim_cmd({ cmd = 'edit', args = { %q } }, {})
  local destination = vim.api.nvim_get_current_buf()
  vim.api.nvim_feedkeys(vim.keycode('<C-o>'), 'nxt', false)
  assert(vim.api.nvim_get_current_buf() == current
    and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 }), 'Current-run jump back failed')
  vim.api.nvim_feedkeys(vim.keycode('<C-i>'), 'nxt', false)
  assert(vim.api.nvim_get_current_buf() == destination, 'Current-run jump forward failed')
]]):format(before_path, before_path, current_path, destination_path), true)
run_process([[
  assert(#vim.api.nvim_list_wins() == 2, 'Startup split fixture did not open two windows')
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    assert(#vim.fn.getjumplist(window)[1] == 0, 'A startup split retained restored jumps')
  end
]], true, { '-o', current_path, destination_path })
vim.fn.delete(directory, 'rf')
