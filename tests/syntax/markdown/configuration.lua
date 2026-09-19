local specs = dofile(vim.fn.getcwd() .. '/lua/plugins/extra.lua')
local spec
for _, plugin in ipairs(specs) do
  if plugin[1] == 'BeckWlim/render-markdown.nvim' then spec = plugin; break end
end
assert(spec and not spec.opts.custom_handlers and not spec.opts.on, 'Source Markdown still uses inline feature overlays')
assert(spec.dev == nil and spec.dir == nil, 'Markdown fork must leave development selection to personal settings')
assert(spec.opts.preview == nil and require('render-markdown').default.preview.enabled,
  'Markdown preview must come from the fork default')
assert(spec.dependencies[1][1] == 'BeckWlim/termaid' and spec.dependencies[1].optional,
  'Termaid must remain an optional renderer dependency')
assert(spec.opts.ignore == nil and spec.opts.pipe_table == nil,
  'BeckNvim still implements renderer feature policy')
assert(spec.opts.win_options.wrap.rendered and spec.opts.win_options.linebreak.rendered,
  'Source Markdown lost native word wrapping')
assert(type(require('render-markdown').preview) == 'function', 'Markdown has no upstream preview entry point')
