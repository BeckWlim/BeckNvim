-- Real parser and editor events: scope visibility follows active window height.
-- nvim --headless -u NONE -i NONE -l tests/syntax/visuals_installed.lua
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true })
local function evaluate(source)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, {})
end
local function expect_background(expected, message)
  assert(vim.wait(1000, function()
    return evaluate([[
      local namespace = vim.api.nvim_create_namespace('current_syntax_scope')
      return #vim.api.nvim_buf_get_extmarks(vim.g.scope_test_buffer, namespace, 0, -1, {}) > 0
    ]]) == expected
  end, 10), message)
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 60, { rgb = true })
  evaluate([[vim.lsp.enable('lua_ls', false)]])
  evaluate([[
    vim.cmd('enew!')
    vim.g.scope_test_buffer = vim.api.nvim_get_current_buf()
    local source = { 'local function sample()' }
    for index = 1, 8 do source[#source + 1] = '  print(' .. index .. ')' end
    source[#source + 1] = 'end'
    for _ = 1, 50 do source[#source + 1] = '' end
    vim.api.nvim_buf_set_lines(vim.g.scope_test_buffer, 0, -1, false, source)
    vim.bo[vim.g.scope_test_buffer].filetype = 'lua'
    vim.wo.foldenable = false
    vim.wo.wrap = false
    require('config.syntax.visuals').setup_scopes()
    vim.cmd('botright new')
    vim.g.scope_test_other_window = vim.api.nvim_get_current_win()
    vim.cmd('wincmd p')
    vim.g.scope_test_window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(vim.g.scope_test_window, 24)
    vim.api.nvim_win_set_cursor(vim.g.scope_test_window, { 5, 2 })
    vim.cmd('redraw')
  ]])
  expect_background(true, 'Small scope did not render in the taller split')
  evaluate([[
    vim.g.scope_test_cursor = vim.api.nvim_win_get_cursor(vim.g.scope_test_window)
    vim.g.scope_test_changedtick = vim.api.nvim_buf_get_changedtick(vim.g.scope_test_buffer)
    vim.api.nvim_win_set_height(vim.g.scope_test_window, 12)
    vim.cmd('redraw')
  ]])
  expect_background(false, 'Resizing without moving the cursor retained the oversized background')
  evaluate([[
    vim.api.nvim_win_set_height(vim.g.scope_test_window, 24)
    vim.cmd('redraw')
  ]])
  expect_background(true, 'Enlarging the window did not restore the background')
  evaluate([[
    -- The same buffer in a smaller active split must obey that split's limit.
    vim.api.nvim_win_set_buf(vim.g.scope_test_other_window, vim.g.scope_test_buffer)
    vim.api.nvim_win_set_height(vim.g.scope_test_other_window, 12)
    vim.api.nvim_win_set_cursor(vim.g.scope_test_other_window, { 5, 2 })
    vim.api.nvim_set_current_win(vim.g.scope_test_other_window)
  ]])
  expect_background(false, 'Focusing the smaller split retained the larger split limit')
  evaluate([[
    vim.api.nvim_set_current_win(vim.g.scope_test_window)
  ]])
  expect_background(true, 'Returning to the larger split did not restore highlighting')
  evaluate([[
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(vim.g.scope_test_window), vim.g.scope_test_cursor), 'Visibility refresh moved the cursor')
    assert(vim.api.nvim_buf_get_changedtick(vim.g.scope_test_buffer) == vim.g.scope_test_changedtick, 'Visibility refresh edited the buffer')
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
assert(passed, failure)
print('Installed scope resize, focus, and navigation checks passed')
