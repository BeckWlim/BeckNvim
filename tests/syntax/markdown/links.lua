local preview = require('render-markdown.preview')
local open_target = require('config.ui.open_target')
local original_buffer = vim.api.nvim_get_current_buf()
local original_confirm = vim.fn.confirm
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
vim.fn.mkdir(directory .. '/docs', 'p')
local source_path = directory .. '/docs/index.md'
local target_path = directory .. '/docs/replicas.md'
local lines = {
  '# Links', '', '[Replica support](replicas.md#L2)', '',
  '| Feature | Description |', '|---|---|',
  '| [Replica support](replicas.md#L2) | ' .. string.rep('wrapped content ', 30) .. '|', '',
  '[Replica support](../docs/replicas.md#L2)',
  '前 [部署指南](../../source/deployment/guide.md#descriptor-based-dfs-storage).',
  '[Only link](https://example.com/a/long/destination)',
  '`[literal](destination)`',
}
vim.fn.writefile(lines, source_path)
vim.fn.writefile({ '# Replicas', 'Replica details' }, target_path)
vim.api.nvim_cmd({ cmd = 'edit', args = { source_path } }, {})
local source = vim.api.nvim_get_current_buf()
vim.bo.filetype = 'markdown'
local window = vim.api.nvim_get_current_win()
local rendered = preview.open(source)
local source_tick = vim.api.nvim_buf_get_changedtick(source)
vim.treesitter.start(rendered)
vim.treesitter.get_parser(rendered):parse(true)
vim.wo.conceallevel = 3
vim.wo.concealcursor = 'nvic'
local function move(row, column, keys, expected_column)
  local position = assert(preview.display_position(window, { row, column }))
  vim.api.nvim_win_set_cursor(window, position)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(window), { position[1], expected_column }),
    keys .. ' stopped on concealed link text: ' .. vim.inspect(vim.api.nvim_win_get_cursor(window)))
end
local unicode_end = assert(lines[10]:find(']', 1, true)) - 1
move(10, #lines[10] - 1, 'h', unicode_end - 3)
move(10, #lines[10] - 1, '<Left>', unicode_end - 3)
move(10, #lines[10] - 1, '2h', unicode_end - 6)
move(10, unicode_end - 3, 'l', #lines[10] - 1)
move(10, unicode_end - 3, '<Right>', #lines[10] - 1)
move(10, unicode_end - 6, '2l', #lines[10] - 1)
move(10, #lines[10] - 1, 'vh', unicode_end - 3)
assert(vim.api.nvim_get_mode().mode == 'v', 'Horizontal preview motion ended Visual selection')
vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'xt', false)
move(11, #lines[11] - 1, 'h', 9)
move(11, 9, 'l', 9)
move(11, 1, 'h', 1)
move(12, 12, 'h', 11) -- Link-like text inside code remains ordinary text.
vim.wo.conceallevel = 0
move(10, #lines[10] - 1, 'h', #lines[10] - 2)
vim.wo.conceallevel = 3
vim.wo.concealcursor = ''
move(10, #lines[10] - 1, 'h', #lines[10] - 2)
vim.treesitter.stop(rendered)
vim.wo.concealcursor = 'nvic'
move(10, #lines[10] - 1, 'h', #lines[10] - 2)
local choice = 2
rawset(vim.fn, 'confirm', function() return choice end)

for _, row in ipairs({ 3, 7, 9 }) do
  local source_column = assert(lines[row]:find('Replica', 1, true)) - 1
  local position = preview.display_position(window, { row, source_column })
  vim.api.nvim_win_set_cursor(window, position)
  choice = 2
  open_target.open_at_cursor()
  assert(vim.api.nvim_get_current_buf() == rendered
    and vim.deep_equal(vim.api.nvim_win_get_cursor(window), position),
    'Cancelling a preview link changed the source or cursor')
  for _, selected_choice in ipairs({ 1, 3, 4 }) do
    choice = selected_choice
    open_target.open_at_cursor()
    assert(vim.api.nvim_buf_get_name(0) == target_path and vim.api.nvim_win_get_cursor(0)[1] == 2,
      'Preview link did not resolve its source-relative file and line anchor')
    assert(not vim.b.gx_lightweight_render, 'Preview source identity lost same-project detection')
    if selected_choice == 1 then
      vim.api.nvim_feedkeys(vim.keycode('<C-o>'), 'nxt', false)
    else
      vim.api.nvim_win_close(0, true)
    end
    assert(vim.api.nvim_get_current_win() == window and vim.api.nvim_get_current_buf() == rendered
      and vim.deep_equal(vim.api.nvim_win_get_cursor(window), position),
      'Returning from a preview link lost its rendered jump destination')
  end
end
assert(vim.api.nvim_buf_get_changedtick(source) == source_tick and not vim.bo[rendered].modifiable,
  'Following preview links changed the source or made the preview editable')
choice = 1
assert(open_target.open('#L3'), 'Preview fragment did not resolve to the original source file')
assert(vim.api.nvim_get_current_buf() == source and vim.api.nvim_win_get_cursor(0)[1] == 3,
  'Preview fragment used the synthetic buffer name')
vim.api.nvim_set_current_buf(rendered)
preview.toggle()
rawset(vim.fn, 'confirm', original_confirm)
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(source, { force = true })
local target_buffer = vim.fn.bufnr(target_path)
if target_buffer ~= -1 then vim.api.nvim_buf_delete(target_buffer, { force = true }) end
vim.fn.delete(directory, 'rf')
