local markdown_table = require('config.syntax.markdown.table')
local buffer = vim.api.nvim_create_buf(false, true)
local source_lines = {
  '| heading | description |', '|---|---|',
  '| `Enter` | alpha bravo charlie delta echo foxtrot golf hotel india juliet |',
}
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, source_lines)
local tree = assert(vim.treesitter.get_parser(buffer, 'markdown'):parse()[1])
local blocks = markdown_table.project({ buf = buffer, root = tree:root(), width = 27 })
assert(#blocks == 1 and blocks[1].start_row == 0 and blocks[1].end_row == 3, 'Table projection lost its source range')
local continuations = 0
local styled_code = false
local mapped_tail = false
for _, row in ipairs(blocks[1].rows) do
  local parts = {}
  for _, chunk in ipairs(row.chunks) do
    parts[#parts + 1] = chunk[1]
    styled_code = styled_code or chunk[2] == 'RenderMarkdownTableCode'
  end
  local text = table.concat(parts)
  assert(vim.trim(text) ~= '', 'Table projection reserved a blank source row')
  assert(vim.fn.strdisplaywidth(text) <= 27, 'Table cell layout exceeded its own width')
  if row.source_row == 2 and row.spans then continuations = continuations + 1 end
  for _, span in ipairs(row.spans or {}) do
    mapped_tail = mapped_tail or span.source_column > 40
  end
end
assert(continuations > 1 and styled_code and mapped_tail, 'Table lost wrapped cells, code styling, or source offsets')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), source_lines), 'Rendering changed table source')
local cache = {}
local cached_blocks = markdown_table.project({ buf = buffer, root = tree:root(), width = 27, cache = cache })
assert(markdown_table.project({ buf = buffer, root = tree:root(), width = 27, cache = cache }) == cached_blocks,
  'Unchanged tables are rebuilt when another feature completes')
local resized_blocks = markdown_table.project({ buf = buffer, root = tree:root(), width = 60, cache = cache })
assert(resized_blocks ~= cached_blocks, 'Table cache ignored the pane width')
vim.api.nvim_buf_set_lines(buffer, 2, 3, false, { '| changed | value |' })
local edited_tree = vim.treesitter.get_parser(buffer, 'markdown'):parse()[1]
assert(markdown_table.project({ buf = buffer, root = edited_tree:root(), width = 60, cache = cache }) ~= resized_blocks,
  'Table cache ignored source edits')
vim.api.nvim_buf_delete(buffer, { force = true })
