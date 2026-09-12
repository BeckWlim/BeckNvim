-- Focused extmark rendering tests for config.syntax.markdown.
local markdown = require('config.syntax.markdown')
local table_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(table_buffer, 0, -1, false, {
  '',
  '| heading |',
  '|---|',
  '| first |',
  '| second |',
  '',
})

local function rendered_line(gutter, text)
  return {
    { gutter, 'LineNr' },
    { text, 'RenderMarkdownTableCell' },
  }
end

local table_groups = {
  { lines = { rendered_line('   ', 'table') } },
  {
    lines = {
      rendered_line(' 2 ', 'heading'),
      rendered_line('   ', 'continued heading'),
    },
    source_row = 1,
  },
  { lines = { rendered_line(' 3 ', 'rule') }, source_row = 2 },
  {
    lines = {
      rendered_line(' 4 ', 'first'),
      rendered_line('   ', 'continued first'),
    },
    source_row = 3,
  },
  { lines = { rendered_line('   ', 'spacing') } },
  { lines = { rendered_line(' 5 ', 'second') }, source_row = 4 },
  { lines = { rendered_line('   ', 'closing rule') } },
}
local staged_table_extmarks = {}
markdown.stage_table_rows(
  table_buffer,
  staged_table_extmarks,
  { start_row = 1 },
  table_groups
)

local overlay_rows = {}
local virtual_line_rows = {}
for _, staged_extmark in ipairs(staged_table_extmarks) do
  assert(
    staged_extmark.options.conceal_lines == nil,
    'Completed Markdown table concealed source rows into one unscrollable virtual block'
  )
  if staged_extmark.key:find(':overlay$') then
    overlay_rows[staged_extmark.row] = staged_extmark.options
  end
  if staged_extmark.options.virt_lines then
    virtual_line_rows[staged_extmark.row] = true
    for _, virtual_line in ipairs(staged_extmark.options.virt_lines) do
      local virtual_line_text = table.concat(vim.tbl_map(function(chunk)
        return chunk[1]
      end, virtual_line))
      assert(
        vim.trim(virtual_line_text) ~= '',
        'Markdown table reserved a whitespace-only preview row'
      )
    end
  end
end
assert(
  overlay_rows[1] and overlay_rows[2] and overlay_rows[3] and overlay_rows[4],
  'Completed Markdown table is not anchored to each corresponding source row'
)
for source_row, overlay in pairs(overlay_rows) do
  assert(
    overlay.virt_text_win_col == 0
      and overlay.conceal == nil
      and overlay.virt_text_pos == nil,
    ('Markdown table row %d is not a fixed preview over navigable source'):format(
      source_row + 1
    )
  )
end

local first_overlay_text = table.concat(vim.tbl_map(function(chunk)
  return chunk[1]
end, overlay_rows[3].virt_text))
local first_source_text = vim.api.nvim_buf_get_lines(table_buffer, 3, 4, false)[1]
assert(
  first_overlay_text:sub(1, #'first') == 'first'
    and vim.fn.strdisplaywidth(first_overlay_text)
      >= vim.fn.strdisplaywidth(first_source_text),
  'Markdown table preview does not cover the navigable raw source row'
)
assert(
  virtual_line_rows[1] and virtual_line_rows[3] and virtual_line_rows[4],
  'Markdown table continuation rows lost their distributed scroll anchors'
)

local rendered_first_row
for _, staged_extmark in ipairs(staged_table_extmarks) do
  if staged_extmark.row == 3 and staged_extmark.key:find(':lines$') then
    rendered_first_row = staged_extmark.options.virt_lines
    break
  end
end
local rendered_first_text = table.concat(vim.tbl_map(function(chunk)
  return chunk[1]
end, rendered_first_row[1]))
assert(
  rendered_first_text:find('continued first', 1, true),
  'Markdown table cursor row lost its rendered continuation'
)

vim.api.nvim_buf_delete(table_buffer, { force = true })
