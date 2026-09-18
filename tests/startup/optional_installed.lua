-- Installed-plugin smoke test; all writable editor data stays in a temporary directory.
-- nvim --headless -u NONE -i NONE -l tests/startup/optional_installed.lua
local directory = vim.fn.tempname()
local executable_directory = directory .. '/bin'
local data_directory = directory .. '/data/nvim'
vim.fn.mkdir(executable_directory, 'p')
vim.fn.mkdir(data_directory, 'p')
vim.fn.mkdir(directory .. '/project/.git', 'p')
assert(vim.uv.fs_symlink(vim.fn.stdpath('data') .. '/lazy', data_directory .. '/lazy'))
for _, command in ipairs({
  'sh', 'bash', 'git', 'rg', 'curl', 'cc', 'gcc', 'c++', 'g++', 'make', 'cmake',
  'ninja', 'tree-sitter', 'tar', 'gzip', 'unzip', 'env', 'nice', 'ionice', 'uname',
  'getconf', 'sed', 'cat',
}) do
  local path = vim.fn.exepath(command)
  if path ~= '' then assert(vim.uv.fs_symlink(path, executable_directory .. '/' .. command)) end
end
local bootstrap = directory .. '/init.lua'
vim.fn.writefile({
  'vim.g.optional_test_errors = {}',
  'local original_notify = vim.notify',
  'vim.notify = function(message, level, options)',
  '  if level == vim.log.levels.ERROR then',
  '    local errors = vim.g.optional_test_errors',
  '    table.insert(errors, tostring(message))',
  '    vim.g.optional_test_errors = errors',
  '  end',
  '  original_notify(message, level, options)',
  'end',
  -- This test validates startup and file editing, never downloads packages.
  "vim.opt.runtimepath:prepend(vim.fn.stdpath('data') .. '/lazy/mason.nvim')",
  "require('mason-registry').refresh = function(callback) callback(false, {}) end",
  'dofile(' .. string.format('%q', vim.fn.getcwd() .. '/init.lua') .. ')',
}, bootstrap)
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', bootstrap, '-i', 'NONE',
}, {
  rpc = true,
  env = {
    PATH = executable_directory,
    XDG_DATA_HOME = directory .. '/data',
    XDG_STATE_HOME = directory .. '/state',
    XDG_CACHE_HOME = directory .. '/cache',
  },
})
local function evaluate(source, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { ... })
end
local succeeded, failure = xpcall(function()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 30, { rgb = true })
  evaluate([[
    for _, command in ipairs({ 'uv', 'node', 'npm', 'python3', 'nvm', 'pyenv', 'termaid' }) do
      assert(vim.fn.executable(command) == 0, command .. ' leaked into the isolated PATH')
    end
    local options = require('mason-lspconfig.settings').current
    assert(vim.deep_equal(options.ensure_installed, {}))
    assert(not vim.lsp.is_enabled('bashls') and not vim.lsp.is_enabled('vimls'))
  ]])
  for _, file in ipairs({ 'sample.sh', 'sample.py', 'sample.lua', 'sample.vim' }) do
    local path = directory .. '/project/' .. file
    evaluate([[
      local path = ...
      vim.cmd.edit(vim.fn.fnameescape(path))
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'editable without optional runtimes' })
      vim.cmd.write()
      assert(vim.fn.readfile(path)[1] == 'editable without optional runtimes')
    ]], path)
  end
  evaluate([[
    require('lazy').load({ plugins = { 'render-markdown.nvim' } })
    -- Simulate a fresh machine with no built Termaid, even if the shared checkout has a .venv.
    require('render-markdown').setup({ preview = { mermaid = { command = '/nonexistent/becknvim-termaid' } } })
    assert(not require('render-markdown.preview.mermaid').find_executable())
    vim.cmd.edit(vim.fn.fnameescape(...))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# Optional tools', '', '```mermaid', 'graph LR', 'A --> B', '```', '', 'Plain text remains editable.',
    })
    vim.cmd.write()
    vim.bo.filetype = 'markdown'
  ]], directory .. '/project/sample.md')
  assert(vim.wait(5000, function()
    return evaluate([[return vim.b.markdown_preview_source ~= nil]])
  end, 50), 'Markdown did not enter preview without Termaid')
  evaluate([[
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(text:find('graph LR', 1, true) and text:find('A --> B', 1, true),
      'Missing Termaid hid the original Mermaid source')
    require('render-markdown').preview()
    assert(vim.bo.modifiable, 'Cannot return to editable Markdown source')
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'Saved after preview.' })
    vim.cmd.write()
    assert(#vim.g.optional_test_errors == 0, vim.inspect(vim.g.optional_test_errors))
  ]])
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Missing optional tools opened a blocking prompt')
end, debug.traceback)
pcall(vim.rpcnotify, child, 'nvim_command', 'qa!')
vim.fn.jobwait({ child }, 3000)
vim.fn.delete(directory, 'rf')
assert(succeeded, failure)
print('PASS: startup, file editing, and Markdown fallback without optional runtimes')
