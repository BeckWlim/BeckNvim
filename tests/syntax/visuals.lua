-- Focused tests for config.syntax.visuals.
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
  syntax_visuals.current_scope_color() == vim.api.nvim_get_hl(0, { name = 'CurrentCodeScope' }).bg,
  'current scope background does not follow the shared palette'
)

local diffview_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(diffview_buffer, 'diffview://scope-visual-test')
assert(
  not syntax_visuals.should_highlight_scope(diffview_buffer),
  'Diffview buffer retained the editor scope background'
)
local ordinary_buffer = vim.api.nvim_create_buf(false, true)
assert(
  syntax_visuals.should_highlight_scope(ordinary_buffer),
  'Ordinary editor buffer unexpectedly lost scope highlighting'
)
vim.api.nvim_buf_delete(diffview_buffer, { force = true })
vim.api.nvim_buf_delete(ordinary_buffer, { force = true })

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
  cursor_line_highlight.bg ~= normal_highlight.bg
    and cursor_line_highlight.bg ~= scope_highlight.bg,
  'cursor line does not use the stronger grey highlight'
)
assert(
  red_delimiter_highlight.fg ~= normal_highlight.fg,
  'red delimiter no longer uses the semantic-highlight-distinct palette'
)
assert(red_delimiter_highlight.bold == true, 'delimiter palette no longer preserves bold text')
assert(
  blue_delimiter_highlight.fg ~= red_delimiter_highlight.fg,
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
  type_location_highlight.fg == blue_delimiter_highlight.fg
    and type_location_highlight.underline == true,
  'type-information locations are not visually selectable'
)
assert(
  type_hint_highlight.fg ~= normal_highlight.fg and type_hint_highlight.italic == true,
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
  syntax_visuals.scope_is_highlightable(maximum_scope, 300),
  'scope highlight rejected its documented maximum size'
)
assert(
  not syntax_visuals.scope_is_highlightable(oversized_scope, 300),
  'oversized scope was not rejected before rendering'
)
local half_view_scope = { start_row = 3, start_column = 0, end_row = 12, end_column = 1 }
assert(syntax_visuals.scope_is_highlightable(half_view_scope, 20),
  'scope occupying exactly half the window was rejected')
assert(not syntax_visuals.scope_is_highlightable(half_view_scope, 19),
  'scope exceeding half the window retained its background')
assert(syntax_visuals.scope_is_highlightable(
  { start_row = 3, start_column = 0, end_row = 13, end_column = 0 }, 20),
  'exclusive range end incorrectly counted an additional line')
assert(not syntax_visuals.scope_is_highlightable(half_view_scope, 1),
  'tiny split retained an oversized scope background')
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

-- Cursor updates must not wait for parsing, and stale completions must not draw.
local original_get_parser = vim.treesitter.get_parser
local original_get_node = vim.treesitter.get_node
local original_window = vim.api.nvim_get_current_win()
local original_buffer = vim.api.nvim_get_current_buf()
local async_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(async_buffer)
vim.api.nvim_buf_set_lines(async_buffer, 0, -1, false, { 'one', 'two', 'three' })
local parse_callbacks = {}
local collected_trees = 0
local cursor_lookups = 0
vim.treesitter.get_parser = function(_, _, _)
  return {
    parse = function(_, _, callback)
      assert(type(callback) == 'function', 'Scope refresh forced a synchronous parse')
      parse_callbacks[#parse_callbacks + 1] = callback
      return {}
    end,
    for_each_tree = function(_, _) collected_trees = collected_trees + 1 end,
  }
end
vim.treesitter.get_node = function(options)
  cursor_lookups = cursor_lookups + 1
  return original_get_node(options)
end
syntax_visuals.setup_scopes()
assert(vim.wait(500, function() return #parse_callbacks == 1 end), 'Scope parse did not start')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = async_buffer })
assert(vim.api.nvim_win_get_cursor(0)[1] == 2 and cursor_lookups == 0,
  'Cursor movement requested syntax before the background parse finished')
vim.api.nvim_buf_set_lines(async_buffer, 0, 1, false, { 'changed' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = async_buffer })
parse_callbacks[1](nil)
vim.wait(20)
assert(collected_trees == 0, 'Stale parse completion collected outdated scope ranges')
assert(vim.wait(500, function() return #parse_callbacks == 2 end))
parse_callbacks[2](nil)
assert(vim.wait(500, function() return collected_trees == 1 end), 'Current parse was not applied')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = async_buffer })
assert(cursor_lookups > 0, 'Ready syntax did not provide cursor scope')
local large_lines = {}
for _ = 1, 5001 do large_lines[#large_lines + 1] = 'value' end
vim.api.nvim_buf_set_lines(async_buffer, 0, -1, false, large_lines)
assert(not rainbow_config.condition(async_buffer), 'Large buffers retained whole-file rainbow queries')
vim.api.nvim_exec_autocmds('TextChanged', { buffer = async_buffer })
vim.wait(120)
local lookups_before_large_move = cursor_lookups
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = async_buffer })
assert(#parse_callbacks == 2 and cursor_lookups == lookups_before_large_move,
  'Large-file scope fallback bypassed the parse budget')
vim.api.nvim_buf_set_lines(async_buffer, 0, -1, false, { 'small again' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = async_buffer })
assert(vim.wait(500, function() return #parse_callbacks == 3 end))
vim.api.nvim_buf_delete(async_buffer, { force = true })
parse_callbacks[3](nil)
vim.wait(20)
assert(collected_trees == 1, 'Deleted buffer accepted a pending parse')
vim.api.nvim_del_augroup_by_name('current_syntax_scope')
vim.api.nvim_set_current_win(original_window)
vim.api.nvim_set_current_buf(original_buffer)
vim.treesitter.get_parser = original_get_parser
vim.treesitter.get_node = original_get_node
