-- Focused configuration and lifecycle tests for config.syntax.markdown.
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
local markdown_features = require('config.syntax.markdown_features')
local markdown_handler = markdown_spec.opts.custom_handlers.markdown
assert(
  markdown_handler == markdown.handler
    and markdown_handler.extends == true
    and markdown_handler.parse == markdown.parse,
  'Markdown features do not use the renderer custom-handler lifecycle'
)
assert(
  markdown_spec.opts.on.attach == markdown.attach
    and markdown_spec.opts.on.clear == markdown.clear
    and markdown_spec.opts.on.render == markdown.render,
  'Markdown features are outside the renderer callback lifecycle'
)
assert(
  type(markdown.sync_cursor) == 'function',
  'Markdown table cursor updates are not available to the attach lifecycle'
)
assert(
  type(markdown_features.request_render) == 'function',
  'Markdown features do not share a re-render request pipeline'
)
assert(
  type(markdown_features.apply) == 'function'
    and type(markdown_features.update) == 'function'
    and type(markdown_features.clear) == 'function'
    and type(markdown_features.park_cursor) == 'function'
    and type(markdown_features.dispatch) == 'function',
  'Markdown features do not share persistent extmark operations'
)

local original_render_markdown = package.loaded['render-markdown']
local requested_renders = {}
package.loaded['render-markdown'] = {
  render = function(context)
    requested_renders[#requested_renders + 1] = context
  end,
}
local request_buffer = vim.api.nvim_create_buf(false, true)
markdown_features.request_render(request_buffer, 'TableRender')
markdown_features.request_render(request_buffer, 'MermaidRender')
assert(vim.wait(100, function()
  return #requested_renders == 1
end, 1), 'Markdown feature re-render requests were not scheduled')
assert(
  requested_renders[1].buf == request_buffer
    and requested_renders[1].event == 'MermaidRender',
  'Markdown feature re-render requests were not coalesced with the latest reason'
)
vim.api.nvim_buf_delete(request_buffer, { force = true })
package.loaded['render-markdown'] = original_render_markdown

local cursor_event_buffer = vim.api.nvim_create_buf(false, true)
markdown.attach({ buf = cursor_event_buffer })
local cursor_events = {}
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ buffer = cursor_event_buffer })) do
  cursor_events[autocmd.event] = cursor_events[autocmd.event] or autocmd.callback ~= nil
end
assert(
  cursor_events.CursorMoved
    and cursor_events.ModeChanged
    and cursor_events.BufLeave
    and cursor_events.WinLeave,
  'Markdown table cursor rendering or transition cleanup is not synchronized'
)
vim.api.nvim_buf_delete(cursor_event_buffer, { force = true })

assert(
  markdown_spec.opts.pipe_table.enabled == false,
  'built-in pipe-table rendering conflicts with the equal-width adapter'
)
assert(
  vim.deep_equal(markdown_spec.opts.code.disable, { 'mermaid' }),
  'built-in Mermaid code rendering conflicts with the custom feature adapter'
)
assert(
  markdown_spec.opts.debounce == 1,
  'Markdown table cursor-row focus retains a visible debounce interval'
)
assert(
  vim.deep_equal(
    markdown_spec.opts.render_modes,
    { 'n', 'c', 't', 'v', 'V', '\22' }
  ),
  'Markdown rendering is not retained across Normal and Visual modes'
)
assert(
  markdown.cell_margins.left == 1
    and markdown.cell_margins.right == 2
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
