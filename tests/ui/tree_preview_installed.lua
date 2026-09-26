-- Exercise the real Telescope preview in its normal event loop.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/alpha/deep', 'p')
vim.fn.mkdir(root .. '/beta/deep', 'p')
vim.fn.writefile({ 'a' }, root .. '/alpha/deep/needle.txt')
vim.fn.writefile({ 'b' }, root .. '/beta/deep/needle.txt')
local child = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n', '-u', 'NONE', '-i', 'NONE' }, { rpc = true })
local function evaluate(code, args)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, args or {})
end
local function wait_for(code, message)
  assert(vim.wait(3000, function() return evaluate(code) end, 10), message)
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
  vim.wait(150)
end
local function check()
  evaluate([[
    vim.opt.runtimepath:prepend(vim.fn.getcwd())
    for _, plugin in ipairs({ 'telescope.nvim', 'plenary.nvim', 'nvim-web-devicons' }) do
      vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
    end
    vim.o.columns, vim.o.lines = 140, 45
    require('telescope').setup({ defaults = {
      initial_mode = 'normal', layout_config = { preview_cutoff = 0 },
    } })
    _G.tree_picker = require('config.ui.folder_picker').open({ starting_directory = ..., search_root = ... })
  ]], { root })
  wait_for([[
    local state = tree_picker.previewer.state
    return state and state.bufnr and #vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false) >= 4
  ]], 'Project preview did not load')
  evaluate([[ require('config.search.telescope').focus_preview(tree_picker.prompt_bufnr) ]])
  input('/needle<CR>')
  wait_for([[ return vim.api.nvim_get_current_line():find('needle.txt', 1, true) ~= nil ]], 'Hidden preview file not found')
  input('n')
  wait_for([[
    local lines = vim.api.nvim_buf_get_lines(tree_picker.previewer.state.bufnr, 0, -1, false)
    return #lines == 6 and lines[3]:find('', 1, true) and lines[4]:find('', 1, true)
  ]], 'Preview search did not collapse alpha and expand beta')
  input('N')
  assert(evaluate([[ return vim.api.nvim_get_current_line():find('needle.txt', 1, true) ~= nil ]]))
  input('zM')
  assert(evaluate([[ return #vim.api.nvim_buf_get_lines(tree_picker.previewer.state.bufnr, 0, -1, false) == 4 ]]))
  evaluate([[ vim.api.nvim_win_set_cursor(0, { 3, 0 }) ]])
  input('zo')
  assert(evaluate([[ return #vim.api.nvim_buf_get_lines(tree_picker.previewer.state.bufnr, 0, -1, false) > 4 ]]))
  input('zc')
  assert(evaluate([[ return #vim.api.nvim_buf_get_lines(tree_picker.previewer.state.bufnr, 0, -1, false) == 4 ]]))
  input('/needle<CR>')
  wait_for([[ return vim.api.nvim_get_current_line():find('needle.txt', 1, true) ~= nil ]], 'File match disappeared')
  input('<CR>')
  wait_for([[ return vim.api.nvim_buf_get_name(0):match('/needle%.txt$') ~= nil ]], 'Enter did not open the matched file')
end
local ok, err = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, 'rf')
assert(ok, err)
print('Installed project tree tests passed')
