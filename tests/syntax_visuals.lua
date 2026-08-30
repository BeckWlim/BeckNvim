local syntax_visuals = require('config.syntax.visuals')

local rainbow_config = syntax_visuals.rainbow_config()
assert(#rainbow_config.highlight == 8, 'rainbow delimiters did not configure the base and nested colors')
assert(
  rainbow_config.highlight[1] == 'RainbowDelimiterBase',
  'first-level delimiters no longer start with the neutral base color'
)
assert(
  rainbow_config.highlight[2] == 'RainbowDelimiterRed'
    and rainbow_config.highlight[8] == 'RainbowDelimiterCyan',
  'nested delimiter colors no longer follow the configured palette'
)

assert(
  syntax_visuals.current_scope_color() == '#2B2C26',
  'current scope background is not the subtle Monokai variant'
)

require('config.syntax.highlights').setup()
local red_delimiter_highlight = vim.api.nvim_get_hl(0, {
  name = 'RainbowDelimiterRed',
  link = false,
})
local blue_delimiter_highlight = vim.api.nvim_get_hl(0, {
  name = 'RainbowDelimiterBlue',
  link = false,
})
local normal_highlight = vim.api.nvim_get_hl(0, {
  name = 'Normal',
  link = false,
})
local scope_highlight = vim.api.nvim_get_hl(0, {
  name = 'CurrentCodeScope',
  link = false,
})
local cursor_line_highlight = vim.api.nvim_get_hl(0, {
  name = 'CursorLine',
  link = false,
})
assert(scope_highlight.bg ~= normal_highlight.bg, 'current scope no longer uses a grey background')
assert(
  cursor_line_highlight.bg == tonumber('3A3D3F', 16)
    and cursor_line_highlight.bg ~= scope_highlight.bg,
  'cursor line does not use the stronger grey highlight'
)
assert(
  red_delimiter_highlight.fg == tonumber('D23A78', 16),
  'red delimiter no longer uses the semantic-highlight-distinct palette'
)
assert(red_delimiter_highlight.bold == true, 'delimiter palette no longer preserves bold text')
assert(
  blue_delimiter_highlight.fg == tonumber('62B4CA', 16),
  'blue delimiter no longer uses the semantic-highlight-distinct palette'
)
local type_location_highlight = vim.api.nvim_get_hl(0, {
  name = 'TypeInformationLocation',
  link = false,
})
local type_hint_highlight = vim.api.nvim_get_hl(0, {
  name = 'TypeInformationHint',
  link = false,
})
assert(
  type_location_highlight.fg == tonumber('66D9EF', 16)
    and type_location_highlight.underline == true,
  'type-information locations are not visually selectable'
)
assert(
  type_hint_highlight.fg == tonumber('75715E', 16) and type_hint_highlight.italic == true,
  'type-information hints do not use the muted detail style'
)
local outer_scope = { start_row = 0, start_column = 0, end_row = 10, end_column = 1 }
local inner_scope = { start_row = 2, start_column = 2, end_row = 8, end_column = 3 }
local sibling_scope = { start_row = 12, start_column = 0, end_row = 14, end_column = 1 }
local scope_ranges = { inner_scope, sibling_scope, outer_scope }
local buffer_content = { start_row = 0, start_column = 0, end_row = 10, end_column = 1 }
assert(
  syntax_visuals.scope_is_global(outer_scope, buffer_content, 'table_constructor'),
  'full-buffer syntax wrapper was not recognized as global'
)
assert(
  not syntax_visuals.scope_is_global(outer_scope, buffer_content, 'function_definition'),
  'full-buffer function was incorrectly recognized as global'
)
assert(
  not syntax_visuals.scope_is_global(inner_scope, buffer_content, 'table_constructor'),
  'nested syntax scope was incorrectly recognized as global'
)
assert(
  syntax_visuals.innermost_scope(scope_ranges, 4, 4) == inner_scope,
  'cursor did not select the innermost syntax scope'
)
assert(
  syntax_visuals.innermost_scope(scope_ranges, 1, 0) == outer_scope,
  'cursor did not select the enclosing syntax scope'
)
assert(
  syntax_visuals.innermost_scope(scope_ranges, 11, 0) == nil,
  'cursor outside every syntax scope retained a background'
)
local maximum_scope = {
  start_row = 0,
  start_column = 0,
  end_row = syntax_visuals.maximum_highlighted_scope_lines - 1,
  end_column = 1,
}
local oversized_scope = {
  start_row = 0,
  start_column = 0,
  end_row = syntax_visuals.maximum_highlighted_scope_lines,
  end_column = 1,
}
assert(
  syntax_visuals.scope_is_highlightable(maximum_scope),
  'scope highlight rejected its documented maximum size'
)
assert(
  not syntax_visuals.scope_is_highlightable(oversized_scope),
  'oversized scope was not rejected before rendering'
)
local split_scope_segments = syntax_visuals.scope_segments(outer_scope, 4)
assert(#split_scope_segments == 2, 'scope background was not split around the cursor row')
assert(
  split_scope_segments[1].end_row == 4 and split_scope_segments[2].start_row == 5,
  'scope background still includes the cursor row'
)

rainbow_config.highlight[1] = 'ChangedByTest'
assert(
  syntax_visuals.rainbow_config().highlight[1] == 'RainbowDelimiterBase',
  'rainbow configuration leaked mutable state'
)
