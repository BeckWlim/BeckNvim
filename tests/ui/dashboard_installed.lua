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
  for _, command in ipairs({ 'split', 'vsplit', 'new', 'vnew', 'tab split' }) do
    evaluate([[
      local command, file = ...
      local source_window = vim.api.nvim_get_current_win()
      local expected = require('config.ui.window_state').resolve(source_window)
      vim.cmd(command)
      local opened_window = vim.api.nvim_get_current_win()
      vim.cmd.edit(vim.fn.fnameescape(file))
      for name, value in pairs(expected) do
        assert(vim.wo[opened_window][name] == value, command .. ' leaked dashboard ' .. name)
      end
      assert(not vim.wo[source_window].number and vim.wo[source_window].signcolumn == 'no',
        command .. ' changed the preserved homepage')
      vim.api.nvim_win_close(opened_window, true)
      vim.api.nvim_set_current_win(source_window)
    ]], { command, recent_file })
    vim.wait(30)
  end
  evaluate([[
    local root, file = ...
    local dashboard = require('config.ui.dashboard')
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buffer)
    dashboard.attach(buffer, vim.api.nvim_get_current_win(),
      dashboard.collect({ file }, root), { root = root })
  ]], { project, recent_file })
  assert(vim.wait(3000, function()
    return evaluate([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      :find('sample.txt', 1, true) ~= nil]])
  end, 10), 'Fixture homepage did not display recent files')
  vim.rpcrequest(child, 'nvim_input', 'j')
  assert(vim.wait(3000, function()
    return evaluate([[return vim.api.nvim_get_current_line():find('sample.txt', 1, true) ~= nil]])
  end, 10), 'Homepage did not select its recent file')
  for _, height in ipairs({ 14, 8 }) do
    vim.rpcrequest(child, 'nvim_ui_try_resize', 120, height)
    assert(vim.wait(3000, function()
      return evaluate([[
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local text = table.concat(lines, '\n')
        return vim.bo.filetype == 'dashboard'
          and not text:find('███╗   ██╗', 1, true)
          and text:find('Recent projects', 1, true)
          and text:find('Recent files', 1, true)
          and vim.api.nvim_get_current_line():find('sample.txt', 1, true)
          and #lines <= vim.api.nvim_win_get_height(0)
      ]])
    end, 10), 'UI resize did not prioritize project and file navigation')
  end
  vim.rpcrequest(child, 'nvim_ui_try_resize', 120, 40)
  assert(vim.wait(3000, function()
    return evaluate([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      :find('███╗   ██╗', 1, true) ~= nil]])
  end, 10), 'UI growth did not restore the homepage icon')
  local other_window = evaluate([[
    return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
      { split = 'below', win = 0, height = 26 })
  ]])
  assert(vim.wait(3000, function()
    return evaluate([[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      return not table.concat(lines, '\n'):find('███╗   ██╗', 1, true)
        and vim.api.nvim_get_current_line():find('sample.txt', 1, true)
        and #lines <= vim.api.nvim_win_get_height(0)
    ]])
  end, 10), 'Split resize did not adapt the homepage pane')
  evaluate([[vim.api.nvim_win_close(..., true)]], { other_window })
  assert(vim.wait(3000, function()
    return evaluate([[return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      :find('███╗   ██╗', 1, true) ~= nil]])
  end, 10), 'Closing the other pane did not restore the homepage icon')
  vim.rpcrequest(child, 'nvim_input', 'o')
  assert(vim.wait(3000, function()
    return evaluate([[ return vim.api.nvim_buf_get_name(0) ]]) == recent_file
  end, 20), 'Homepage o did not open the selected recent file')
  evaluate([[assert(vim.wo.number, 'Homepage file selection lost editor line numbers')]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed homepage startup, native split context, adaptive height, and file selection checks passed')
