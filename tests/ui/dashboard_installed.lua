-- Start with an attached UI, exercising the real welcome/dashboard boundary.
-- nvim --headless -u NONE -i NONE -l tests/ui/dashboard_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local project = directory .. '/project'
local recent_file = project .. '/sample.txt'
vim.fn.mkdir(project .. '/.git', 'p')
vim.fn.writefile({ 'homepage selection' }, recent_file)
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' },
  { rpc = true, env = { XDG_STATE_HOME = directory } })
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  assert(vim.wait(5000, function()
    return evaluate([[
      return vim.bo.filetype == 'dashboard'
        and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false)):find('BECKNVIM', 1, true) ~= nil
    ]])
  end, 20), 'Startup did not display the project homepage')
  evaluate([[
    assert(vim.o.shortmess:find('I', 1, true), 'Built-in intro can flash before the project homepage')
    assert(not vim.api.nvim_get_mode().blocking, 'Dashboard startup opened a blocking prompt')
    assert(not vim.wo.number and not vim.wo.relativenumber, 'Startup dashboard retained an editor gutter')
  ]])
  evaluate([[
    local root, file = ...
    local dashboard = require('config.ui.dashboard')
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buffer)
    dashboard.attach(buffer, vim.api.nvim_get_current_win(),
      dashboard.collect({ file }, root), { root = root })
  ]], { project, recent_file })
  vim.rpcrequest(child, 'nvim_input', 'jo')
  assert(vim.wait(3000, function()
    return evaluate([[ return vim.api.nvim_buf_get_name(0) ]]) == recent_file
  end, 20), 'Homepage o did not open the selected recent file')
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed UI startup displays the project homepage with the built-in intro suppressed')
