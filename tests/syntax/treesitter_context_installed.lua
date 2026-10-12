-- Pinned declarations survive native jumps back into retained, unlisted files.
-- nvim --headless -u NONE -i NONE -l tests/syntax/treesitter_context_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
local source_lines = { 'local function original_scope()' }
for index = 1, 100 do
  source_lines[#source_lines + 1] = ('  local value_%d = %d'):format(index, index)
end
vim.list_extend(source_lines, { '  return value_100', 'end' })
vim.fn.writefile(source_lines, directory .. '/source.lua')
vim.fn.writefile({ 'return {}' }, directory .. '/target.lua')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', 'NONE', '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = directory .. '/cache', XDG_STATE_HOME = directory .. '/state' },
})
local function evaluate(source)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected blocking editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { directory })
end
local function wait_for(source, message)
  assert(vim.wait(5000, function() return evaluate(source) end, 20), message)
end
local pinned_source = [[
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[window].treesitter_context then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)
      if vim.tbl_contains(lines, 'local function original_scope()') then return true end
    end
  end
  return false
]]
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  evaluate([[
    vim.opt.runtimepath:prepend(vim.fn.getcwd())
    vim.opt.runtimepath:prepend(vim.fn.stdpath('data') .. '/lazy/nvim-treesitter-context')
    vim.cmd('filetype on')
    vim.o.hidden = true
    require('config.startup.keybindings').setup()
    require('config.syntax.treesitter_context').setup()
    vim.cmd.edit(vim.fn.fnameescape((...) .. '/source.lua'))
    vim.cmd('clearjumps')
    vim.api.nvim_win_set_cursor(0, { 80, 2 })
    vim.cmd('normal! zz')
    _G.source_buffer = vim.api.nvim_get_current_buf()
  ]])
  wait_for(pinned_source, 'Initial declaration was not pinned')
  for _ = 1, 2 do
    evaluate([[
      require('config.navigation').open((...) .. '/target.lua', { push_cursor = true })
      assert(not vim.bo[source_buffer].buflisted, 'Replacement did not retire the source')
      assert(vim.api.nvim_buf_is_loaded(source_buffer), 'Replacement unloaded the source')
    ]])
    vim.rpcrequest(child, 'nvim_input', ' o')
    wait_for([[return vim.api.nvim_get_current_buf() == source_buffer
      and vim.api.nvim_win_get_cursor(0)[1] == 80]], 'Space-o did not restore the source cursor')
    wait_for(pinned_source, 'Space-o dismissed the pinned declaration in a retained buffer')
    vim.rpcrequest(child, 'nvim_input', ' p')
    wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.lua']],
      'Space-p did not restore the destination')
    vim.rpcrequest(child, 'nvim_input', ' o')
    wait_for(pinned_source, 'Repeated history navigation lost the pinned declaration')
  end
  evaluate([[
    require('treesitter-context').disable()
    require('config.navigation').forward()
    require('config.navigation').back()
    assert(not require('treesitter-context').enabled(), 'History reenabled disabled context')
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed pinned-context back/forward history checks passed')
