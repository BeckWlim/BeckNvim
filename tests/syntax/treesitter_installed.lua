-- Native async highlighting on a large file must leave navigation available.
-- nvim --headless -u NONE -i NONE -l tests/syntax/treesitter_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local source_lines = {}
for index = 1, 20000 do
  source_lines[#source_lines + 1] = ('local function item_%d(value)'):format(index)
  source_lines[#source_lines + 1] = '  return { value, (value + 1) }'
  source_lines[#source_lines + 1] = 'end'
end
vim.fn.writefile(source_lines, directory .. '/large.lua')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = directory } })
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  evaluate([[
    vim.lsp.enable('lua_ls', false)
    vim.cmd.edit(vim.fn.fnameescape(...))
  ]], { directory .. '/large.lua' })
  for _ = 1, 5 do
    local previous_row = evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=])
    vim.rpcrequest(child, 'nvim_input', 'j')
    assert(vim.wait(1500, function()
      return evaluate([=[return vim.api.nvim_win_get_cursor(0)[1]]=]) > previous_row
    end, 10), 'Large-file cursor waited for syntax loading')
  end
  assert(vim.wait(5000, function()
    return evaluate([[
      local parser = vim.treesitter.get_parser(0)
      return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil
        and parser and next(parser:trees()) ~= nil
    ]])
  end, 10), 'Native large-file syntax highlighting never became ready')
  evaluate([[
    assert(not vim.api.nvim_get_mode().blocking, 'Syntax loading opened a blocking prompt')
    local rainbow = require('rainbow-delimiters.lib')
    assert(not rainbow.buffers[vim.api.nvim_get_current_buf()], 'Large file ran whole-tree rainbow queries')
    local namespace = vim.api.nvim_create_namespace('current_syntax_scope')
    assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 0)
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed 60,000-line syntax loading and cursor navigation checks passed')
