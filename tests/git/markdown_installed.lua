-- Run with installed Diffview, the renderer fork, and Marksman:
-- nvim --headless -u init.lua -i NONE -l tests/git/markdown_installed.lua
local directory = vim.fn.tempname()
local original_directory = vim.fn.getcwd()
vim.fn.mkdir(directory, 'p')
local function git(arguments)
  local command = { 'git', '-C', directory }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
end
local function check()
  git({ 'init', '-q' })
  local lines = { '# Markdown diff', '' }
  for index = 1, 120 do
    lines[#lines + 1] = ('Line %d **bold** [link](other.md)'):format(index)
  end
  vim.fn.writefile(lines, directory .. '/sample.md')
  git({ 'add', 'sample.md' })
  git({ '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture' })
  lines[15] = 'Changed line'
  vim.fn.writefile(lines, directory .. '/sample.md')
  vim.api.nvim_set_current_dir(directory)
  require('lazy').load({ plugins = { 'render-markdown.nvim', 'diffview.nvim', 'mason-lspconfig.nvim' } })
  vim.lsp.enable('marksman')
  vim.cmd('DiffviewOpen')
  assert(vim.wait(5000, function()
    local view = require('diffview.lib').get_current_view()
    return view and view.cur_layout and view.cur_layout.b.file
      and view.cur_layout.b.file.bufnr and view.cur_layout.b.id
      and vim.api.nvim_win_get_buf(view.cur_layout.b.id) == view.cur_layout.b.file.bufnr
      and vim.api.nvim_buf_get_name(view.cur_layout.b.file.bufnr) == directory .. '/sample.md'
  end, 10), 'Markdown diff did not load')
  local view = require('diffview.lib').get_current_view()
  local left, right = view.cur_layout.a, view.cur_layout.b
  local source = right.file.bufnr
  assert(vim.wait(5000, function()
    local clients = vim.lsp.get_clients({ bufnr = source, name = 'marksman' })
    return clients[1] and clients[1].initialized
  end, 10), 'Marksman did not attach to real Markdown')
  local client = vim.lsp.get_clients({ bufnr = source, name = 'marksman' })[1]
  assert(client.root_dir == directory, 'Virtual-buffer guard changed native root detection')
  for _, pane in ipairs({ left, right }) do
    vim.api.nvim_set_current_win(pane.id)
    vim.wait(100)
    require('render-markdown').preview()
    vim.wait(50)
    assert(vim.api.nvim_win_get_buf(pane.id) == pane.file.bufnr,
      'Markdown projection replaced a Diffview source')
    assert(vim.wo[pane.id].diff and vim.wo[pane.id].scrollbind and vim.wo[pane.id].cursorbind,
      'Markdown preview disabled native diff synchronization')
  end
  assert(#vim.lsp.get_clients({ bufnr = left.file.bufnr, name = 'marksman' }) == 0,
    'Marksman attached to an editable Git index URI')
  vim.cmd('normal! 50G')
  vim.wait(50)
  assert(vim.api.nvim_win_get_cursor(left.id)[1] == 50
    and vim.api.nvim_win_get_cursor(right.id)[1] == 50, 'Diff cursors did not synchronize')
  local index_buffer = left.file.bufnr
  vim.cmd('DiffviewClose')
  if vim.api.nvim_buf_is_valid(index_buffer) then
    vim.api.nvim_buf_delete(index_buffer, { force = true })
  end
  vim.wait(100)
  assert(not client:is_stopped(), 'Closing the virtual index killed Marksman')
  vim.api.nvim_cmd({ cmd = 'edit', args = { directory .. '/sample.md' } }, {})
  assert(vim.wait(1000, function()
    return vim.b.markdown_preview_source == source
  end, 10), 'Ordinary Markdown preview did not resume after Diffview')
end
local passed, failure = xpcall(check, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients({ name = 'marksman' })) do client:stop(true) end
vim.api.nvim_set_current_dir(original_directory)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Markdown diff source identity, cursor synchronization, and Marksman isolation passed')
