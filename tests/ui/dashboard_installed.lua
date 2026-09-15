-- Start with an attached UI, exercising the real welcome/dashboard boundary.
-- nvim --headless -u NONE -i NONE -l tests/ui/dashboard_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' },
  { rpc = true, env = { XDG_STATE_HOME = directory } })
local function evaluate(source)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, {})
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
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed UI startup displays the project homepage with the built-in intro suppressed')
