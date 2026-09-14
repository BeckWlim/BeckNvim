local specs = dofile(vim.fn.getcwd() .. '/lua/plugins/extra.lua')
local spec
for _, plugin in ipairs(specs) do
  if plugin[1] == 'MeanderingProgrammer/render-markdown.nvim' then spec = plugin; break end
end
assert(spec and not spec.opts.custom_handlers and not spec.opts.on, 'Source Markdown still uses inline feature overlays')
local buffer = vim.api.nvim_create_buf(true, false)
assert(spec.opts.ignore(buffer), 'Editable source still receives preview decorations')
vim.b[buffer].markdown_preview_source = 1
assert(not spec.opts.ignore(buffer), 'Ordinary Markdown was excluded from the rendered view')
assert(not spec.opts.anti_conceal.enabled and spec.opts.win_options.concealcursor.rendered == 'nvic',
  'Moving the cursor reveals raw Markdown inside the rendered view')
vim.b[buffer].markdown_preview_source = nil
vim.bo[buffer].buftype = 'nofile'
assert(not spec.opts.ignore(buffer), 'Read-only Markdown detail panels lost their prose renderer')
assert(spec.opts.win_options.wrap.rendered and spec.opts.win_options.linebreak.rendered,
  'Source Markdown lost native word wrapping')
local markdown_table = require('config.syntax.markdown.table')
assert(markdown_table.cell_margins.left == 1 and markdown_table.cell_margins.right == 2,
  'Table feature lost its cell margins')
assert(markdown_table.table_width_limit(27) == 27 and markdown_table.table_width_limit(120) == 96,
  'Table feature lost its independent responsive width policy')
assert(type(require('config.syntax.markdown').toggle) == 'function', 'Markdown has no shared preview entry point')
vim.api.nvim_buf_delete(buffer, { force = true })
