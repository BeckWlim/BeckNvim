-- Rendered files remain editor destinations even though their display is nofile.
local operations = require('config.navigation')
local renderer = require('render-markdown')
local original_tab = vim.api.nvim_get_current_tabpage()
local original_select = vim.ui.select
local original_confirm = vim.fn.confirm
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local markdown_path, target_path = root .. '/README.md', root .. '/target.txt'
vim.fn.writefile({ '# Rendered file', '', 'Replace this file in its existing pane.' }, markdown_path)
vim.fn.writefile({ 'replacement' }, target_path)
renderer.setup({ preview = { enabled = true } })
vim.cmd('tabnew')
local editor = vim.api.nvim_get_current_win()
local function open_preview()
  vim.api.nvim_set_current_win(editor)
  vim.api.nvim_cmd({ cmd = 'edit', args = { markdown_path } }, {})
  vim.bo.filetype = 'markdown'
  assert(vim.wait(1000, function() return vim.b.markdown_preview_source ~= nil end, 10),
    'Markdown fixture did not enter its rendered preview')
  return vim.api.nvim_get_current_buf(), vim.b.markdown_preview_source
end
local preview_buffer, source_buffer = open_preview()
vim.cmd('vnew')
local tree = vim.api.nvim_get_current_win()
local tree_buffer = vim.api.nvim_get_current_buf()
vim.bo[tree_buffer].buftype, vim.bo[tree_buffer].filetype = 'nofile', 'NvimTree'
local layout = vim.fn.winlayout()
operations.open(target_path, { keep_focus = true })
assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Tree selection split instead of replacing a rendered file')
assert(vim.api.nvim_get_current_win() == tree, 'Tree replacement lost tree focus')
assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == target_path,
  'Tree selection did not replace the rendered file in its existing pane')
assert(vim.api.nvim_buf_is_valid(source_buffer) and not vim.bo[source_buffer].buflisted
  and not vim.bo[source_buffer].modified and vim.api.nvim_buf_is_valid(preview_buffer),
  'Successful replacement lost the rendered jump destination or retained the listed Markdown source')

preview_buffer, source_buffer = open_preview()
vim.api.nvim_buf_set_lines(source_buffer, 2, 3, false, { 'unsaved source edit' })
vim.api.nvim_set_current_win(tree)
rawset(vim.ui, 'select', function() error('Rendered replacement opened a dirty-file decision flow') end)
local answer = 2
rawset(vim.fn, 'confirm', function() return answer end)
local rejected = operations.open(target_path, { keep_focus = true })
assert(rejected and rejected.cancelled and vim.api.nvim_win_get_buf(editor) == preview_buffer and vim.bo[source_buffer].modified,
  "Replacement failed to protect the rendered file's unwritten source")
assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Rejection changed the split layout')
answer = 1
operations.open(target_path, { keep_focus = true })
assert(vim.fn.readfile(markdown_path)[3] == 'unsaved source edit'
  and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == target_path,
  'Writing the Markdown source did not enable replacement')

preview_buffer, source_buffer = open_preview()
vim.api.nvim_set_current_win(tree)
operations.open(markdown_path, { keep_focus = true })
assert(vim.api.nvim_win_get_buf(editor) == preview_buffer and vim.deep_equal(vim.fn.winlayout(), layout),
  'Selecting the displayed Markdown file replaced its preview or split the pane')
vim.api.nvim_buf_set_lines(source_buffer, 2, 3, false, { 'newer source edit' })
answer = 2
assert(operations.open(target_path, { keep_focus = true }).cancelled
  and vim.api.nvim_win_get_buf(editor) == preview_buffer and vim.bo[source_buffer].modified,
  'Replacement covered newer unwritten source edits')
answer = 1
operations.open(target_path, { keep_focus = true })
assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == target_path
  and vim.fn.readfile(markdown_path)[3] == 'newer source edit', 'Written source did not replace successfully')

-- Editor-origin opens use the same file identity, without treating it as a panel.
preview_buffer, source_buffer = open_preview()
operations.open(target_path)
assert(vim.api.nvim_get_current_win() == editor and vim.api.nvim_buf_get_name(0) == target_path
    and vim.deep_equal(vim.fn.winlayout(), layout), 'Opening from a preview created another pane')

-- Only an explicit command adds a pane; it retains the original rendered file.
preview_buffer, source_buffer = open_preview()
vim.api.nvim_set_current_win(tree)
operations.open(target_path, { command = 'split', keep_focus = true })
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Explicit split did not add exactly one pane')
assert(vim.api.nvim_win_get_buf(editor) == preview_buffer and vim.api.nvim_buf_is_valid(source_buffer),
  'Explicit split replaced the existing rendered file')
assert(vim.api.nvim_get_current_win() == tree, 'Explicit tree split lost tree focus')

rawset(vim.ui, 'select', original_select)
rawset(vim.fn, 'confirm', original_confirm)
vim.cmd('tabclose!')
assert(vim.api.nvim_get_current_tabpage() == original_tab)
for _, buffer in ipairs({ tree_buffer, source_buffer, preview_buffer, vim.fn.bufnr(target_path) }) do
  if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
end
vim.fn.delete(root, 'rf')
print('Rendered file replacement and explicit split checks passed')
