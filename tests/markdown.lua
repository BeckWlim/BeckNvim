local plugin_specs = dofile(vim.fn.getcwd() .. '/lua/plugins/extra.lua')
local markdown_spec
for _, plugin_spec in ipairs(plugin_specs) do
  if plugin_spec[1] == 'MeanderingProgrammer/render-markdown.nvim' then
    markdown_spec = plugin_spec
    break
  end
end

assert(markdown_spec, 'render-markdown plugin specification is missing')
local markdown = require('config.syntax.markdown')
local markdown_handler = markdown_spec.opts.custom_handlers.markdown
assert(
  markdown_handler == markdown.handler
    and markdown_handler.extends == true
    and markdown_handler.parse == markdown.parse,
  'Markdown table adapter does not use the renderer custom-handler lifecycle'
)
assert(
  markdown_spec.opts.on.attach == markdown.attach
    and markdown_spec.opts.on.clear == markdown.clear
    and markdown_spec.opts.on.render == markdown.render,
  'Markdown table adapter is outside the renderer callback lifecycle'
)
assert(
  markdown_spec.opts.pipe_table.enabled == false,
  'built-in pipe-table rendering conflicts with the equal-width adapter'
)
assert(
  markdown_spec.opts.debounce == 1,
  'Markdown table cursor-row focus retains a visible debounce interval'
)
assert(
  markdown.cell_margins.left == 1
    and markdown.cell_margins.right == 2
    and markdown.table_editing.wrap == false
    and markdown.table_layout.full_width_threshold == 80
    and markdown.table_layout.outer_right_ratio == 0.2,
  'Markdown table layout or stable editing policy changed unexpectedly'
)
assert(
  markdown.table_width_limit(27) == 27
    and markdown.table_width_limit(80) == 80
    and markdown.table_width_limit(100) == 80
    and markdown.table_width_limit(120) == 96,
  'Markdown table width cap is not responsive across narrow and wide views'
)
assert(
  markdown.uses_row_layout(1, 2, 9, 1)
    and markdown.uses_row_layout(2, 2, 9, 1)
    and markdown.uses_row_layout(3, 2, 9, 1)
    and not markdown.uses_row_layout(0, 2, 9, 1)
    and not markdown.uses_row_layout(9, 2, 9, 1),
  'Markdown table tag, header, and delimiter do not share one stable row layout'
)

local allocated_widths, gap_width = markdown.allocate_widths(80, 3)
assert(gap_width == 2, 'Markdown table columns lost their restrained whitespace gap')
assert(
  allocated_widths[1] == 26
    and allocated_widths[2] == 25
    and allocated_widths[3] == 25,
  'Markdown table did not distribute available width evenly from the first column'
)
assert(
  allocated_widths[1] - allocated_widths[3] <= 1,
  'Markdown table columns differ by more than one display cell'
)
local compact_widths, compact_gap = markdown.allocate_widths(80, 3, { 8, 12, 5 })
assert(
  compact_gap == 2 and vim.deep_equal(compact_widths, { 8, 12, 5 }),
  'Markdown table stretched columns beyond their maximum visible content'
)
local redistributed_widths = markdown.allocate_widths(40, 3, { 5, 50, 30 })
assert(
  vim.deep_equal(redistributed_widths, { 5, 16, 15 }),
  'Markdown table did not redistribute unused short-column capacity fairly'
)
local wrapped_cell = markdown.wrap_cell(
  '[visible label](https://example.com/a/long/hidden/destination) followed by text',
  16
)
assert(
  vim.deep_equal(wrapped_cell, { 'visible label', 'followed by text' }),
  'Markdown table wrapping measured a concealed link destination or crossed its column'
)
assert(
  vim.deep_equal(markdown.wrap_cell('abcdefgh', 3), { 'abc', 'def', 'gh' }),
  'Markdown table did not split an over-width word inside its allocated column'
)
local inline_code_chunks = markdown.wrap_cell_chunks(
  'press `Enter` now',
  20,
  'RenderMarkdownTableCell'
)
assert(
  vim.deep_equal(inline_code_chunks, {
    {
      { 'press ', 'RenderMarkdownTableCell' },
      { 'Enter', 'RenderMarkdownTableCode' },
      { ' now', 'RenderMarkdownTableCell' },
    },
  }),
  'Markdown table dropped the inline-code key mark'
)
assert(
  vim.deep_equal(markdown.wrap_cell_chunks('`abcdef`', 3, 'Cell'), {
    { { 'abc', 'RenderMarkdownTableCode' } },
    { { 'def', 'RenderMarkdownTableCode' } },
  }),
  'Markdown table lost inline-code styling across a wrapped key mark'
)
assert(
  vim.deep_equal(markdown.wrap_cell_chunks('`Enter key`', 20, 'Cell'), {
    { { 'Enter key', 'RenderMarkdownTableCode' } },
  }),
  'Markdown table split one spaced inline-code mark into separate badges'
)
local snapshot_key = '/oplog/<cluster>/snapshot/{maintenance,latest,fallback,compaction_floor}'
local snapshot_key_chunks = markdown.wrap_cell_chunks(
  '`' .. snapshot_key .. '`',
  24,
  'RenderMarkdownTableCell'
)
local snapshot_key_parts = {}
for _, wrapped_key_line in ipairs(snapshot_key_chunks) do
  for _, wrapped_key_chunk in ipairs(wrapped_key_line) do
    assert(
      wrapped_key_chunk[2] == 'RenderMarkdownTableCode',
      'wrapped snapshot key contains an unbadged fragment'
    )
    snapshot_key_parts[#snapshot_key_parts + 1] = wrapped_key_chunk[1]
  end
end
assert(
  table.concat(snapshot_key_parts) == snapshot_key,
  'wrapped snapshot key lost visible content'
)

local table_query_path = vim.fn.getcwd() .. '/after/queries/markdown/highlights.scm'
local table_query_text = table.concat(vim.fn.readfile(table_query_path), '\n')
assert(
  table_query_text:find('(pipe_table) @markup.table.markdown', 1, true),
  'Markdown table source lacks its block-background query'
)

local window_options = markdown_spec.opts.win_options
local expected_options = {
  breakindent = { default = false, rendered = true },
  breakindentopt = { default = '', rendered = 'shift:2,min:20' },
  linebreak = { default = false, rendered = true },
  showbreak = { default = '', rendered = '↳ ' },
  smoothscroll = { default = false, rendered = true },
  wrap = { default = false, rendered = true },
}
for option_name, expected_states in pairs(expected_options) do
  local option_states = window_options[option_name]
  assert(option_states, ('Markdown window option is missing: %s'):format(option_name))
  assert(
    option_states.default == expected_states.default
      and option_states.rendered == expected_states.rendered,
    ('Markdown %s does not preserve raw and rendered display states'):format(option_name)
  )
end
