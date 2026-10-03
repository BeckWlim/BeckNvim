-- Native :q/:wq must close one Lua pane, including two views of one buffer.
-- nvim --headless -u NONE -i NONE -l tests/ui/nested_close_installed.lua
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.git', 'p')
local lines = { 'local function fixture()' }
for index = 1, 100 do lines[#lines + 1] = ('  local value_%d = %d'):format(index, index) end
vim.list_extend(lines, { '  return value_100', 'end', 'return fixture' })
for _, name in ipairs({ 'left.lua', 'upper.lua', 'lower.lua' }) do
  vim.fn.writefile(lines, root .. '/' .. name)
end
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'init.lua', '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = root .. '/cache', XDG_STATE_HOME = root .. '/state' },
})
local function evaluate(source)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected blocking editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { root })
end
local function wait_for(source, message)
  assert(vim.wait(5000, function() return evaluate(source) end, 20), message)
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  wait_for([[return vim.bo.filetype == 'dashboard']], 'Startup dashboard did not open')
  for _, same_file in ipairs({ false, true }) do
    for _, command in ipairs({ 'q', 'wq' }) do
      for _, closing_pane in ipairs({ 'upper', 'lower' }) do
        evaluate([[
          vim.cmd('tabnew')
          vim.cmd.edit((...) .. '/left.lua')
          _G.left = vim.api.nvim_get_current_win()
          _G.left_buffer = vim.api.nvim_get_current_buf()
          vim.cmd('rightbelow vnew ' .. vim.fn.fnameescape((...) .. '/upper.lua'))
          _G.upper = vim.api.nvim_get_current_win()
          _G.upper_buffer = vim.api.nvim_get_current_buf()
          vim.api.nvim_win_set_cursor(0, { 95, 0 })
          vim.cmd('normal! zt')
        ]])
        vim.wait(100)
        evaluate(([[
          vim.cmd('rightbelow new ' .. vim.fn.fnameescape((...) .. '/%s'))
          _G.lower = vim.api.nvim_get_current_win()
          _G.lower_buffer = vim.api.nvim_get_current_buf()
          vim.api.nvim_win_set_cursor(0, { 95, 0 })
          vim.cmd('normal! zt')
          assert(vim.deep_equal(vim.fn.winlayout(), {
            'row', { { 'leaf', left }, { 'col', { { 'leaf', upper }, { 'leaf', lower } } } },
          }), 'Fixture did not create left file and stacked right files')
          _G.closing = %s
          _G.sibling = %s
          _G.sibling_buffer = vim.api.nvim_win_get_buf(sibling)
          vim.api.nvim_set_current_win(closing)
        ]]):format(same_file and 'upper.lua' or 'lower.lua', closing_pane,
          closing_pane == 'upper' and 'lower' or 'upper'))
        vim.wait(100)
        vim.rpcrequest(child, 'nvim_input', ':' .. command .. '<CR>')
        wait_for([[return not vim.api.nvim_win_is_valid(closing)]], 'Native quit did not close the focused pane')
        vim.wait(100)
        evaluate([[
          assert(vim.api.nvim_win_is_valid(left), 'Native quit also closed the left pane')
          assert(vim.api.nvim_win_is_valid(sibling), 'Native quit also closed the other right pane')
          assert(vim.api.nvim_win_get_buf(left) == left_buffer, 'Native quit replaced the left file')
          assert(vim.api.nvim_win_get_buf(sibling) == sibling_buffer, 'Native quit replaced the surviving right file')
          assert(vim.deep_equal(vim.fn.winlayout(), {
            'row', { { 'leaf', left }, { 'leaf', sibling } },
          }), 'Native quit changed more than the selected pane')
          vim.cmd('tabclose!')
        ]])
      end
    end
  end
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, 'rf')
assert(passed, failure)
print('Nested Lua panes: native :q/:wq preserve both siblings for different and shared buffers')
