-- Focused navigation and viewport tests for config.syntax.markdown.
local markdown = require('config.syntax.markdown')

local original = {
  buffer = vim.api.nvim_get_current_buf(),
  render_context = package.loaded['render-markdown.request.context'],
  render_state = package.loaded['render-markdown.state'],
  wrap = vim.wo.wrap,
}
local rendering_enabled = true
package.loaded['render-markdown.state'] = {
  get = function()
    return { enabled = rendering_enabled }
  end,
}
package.loaded['render-markdown.request.context'] = {
  get = function(buffer)
    return {
      view = {
        query = function(_, root, query, callback)
          for capture_id, node in query:iter_captures(root, buffer, 0, -1) do
            callback(capture_id, node)
          end
        end,
      },
    }
  end,
}

local function create_navigation_fixture()
  local lines = {}
  local function append(line)
    lines[#lines + 1] = line
    return #lines
  end
  for line_index = 1, 30 do
    append(('ordinary prose before table %d'):format(line_index))
  end
  local table_label_line = append('')
  append('| heading | evidence |')
  append('|---|---|')
  local long_source_row = '| first | ' .. string.rep('long content ', 30) .. '|'
  local table_data_line = append(long_source_row)
  append('')
  local following_prose_line = append('ordinary prose after table')
  for line_index = 1, 30 do
    append(('more ordinary prose %d'):format(line_index))
  end

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buffer)
  local parser = vim.treesitter.get_parser(buffer, 'markdown')
  local tree = assert(parser:parse()[1])
  markdown.parse({ buf = buffer, root = tree:root() })
  markdown.attach({ buf = buffer })
  return {
    buffer = buffer,
    following_prose_line = following_prose_line,
    last_line = #lines,
    long_source_row = long_source_row,
    table_data_line = table_data_line,
    table_label_line = table_label_line,
  }
end

local function render_at(fixture, row, place_at_top)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  if place_at_top then
    vim.cmd('normal! zt')
  end
  markdown.render({ buf = fixture.buffer, win = 0 })
end

local function includes_highlight(highlights, expected)
  if type(highlights) == 'string' then
    return highlights == expected
  end
  for _, highlight in ipairs(highlights or {}) do
    if highlight == expected then
      return true
    end
  end
  return false
end

local function highlighted_display_width(buffer, row, highlight)
  local namespace = vim.api.nvim_get_namespaces().markdown_tables
  local width = 0
  for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(
    buffer,
    namespace,
    { row, 0 },
    { row, -1 },
    { details = true }
  )) do
    for _, chunk in ipairs(extmark[4].virt_text or {}) do
      if includes_highlight(chunk[2], highlight) then
        width = width + vim.fn.strdisplaywidth(chunk[1])
      end
    end
  end
  return width
end

local fixture = create_navigation_fixture()

-- Soft wrapping follows table visibility, not the parser's off-screen lookahead
-- or the cursor's membership in the table.
vim.wo.wrap = false
render_at(fixture, 1, true)
assert(
  vim.wo.wrap,
  'An off-screen parsed table disabled soft wrapping for ordinary Markdown prose'
)
render_at(fixture, fixture.table_label_line, true)
assert(
  not vim.wo.wrap,
  'A visible table enabled raw source wrapping while the cursor was in prose'
)
render_at(fixture, fixture.table_data_line, false)
markdown.sync_cursor(fixture.buffer)
assert(
  not vim.wo.wrap,
  'Markdown table navigation did not suppress raw source wrapping'
)

-- The rendered cursor and Visual selection follow native movement through the
-- raw source without exposing or horizontally scrolling that source.
vim.api.nvim_feedkeys('2l', 'xt', false)
markdown.sync_cursor(fixture.buffer)
vim.api.nvim_feedkeys('v', 'xt', false)
markdown.sync_cursor(fixture.buffer)
local selected_display_width = highlighted_display_width(
  fixture.buffer,
  fixture.table_data_line - 1,
  'Visual'
)
assert(
  selected_display_width == 1,
  ('Entering Visual mode selected %d rendered cells instead of one character')
    :format(selected_display_width)
)
vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'xt', false)
markdown.sync_cursor(fixture.buffer)
vim.api.nvim_feedkeys('$', 'xt', false)
markdown.sync_cursor(fixture.buffer)
vim.cmd('redraw')
local parked_cursor = vim.api.nvim_win_get_cursor(0)
assert(
  parked_cursor[1] == fixture.table_data_line
    and parked_cursor[2] == 0
    and vim.fn.winsaveview().leftcol == 0,
  ('Markdown table raw cursor still shifted the resting viewport: %s leftcol=%d')
    :format(vim.inspect(parked_cursor), vim.fn.winsaveview().leftcol)
)

-- Native Visual-mode operations still use the complete source range.
vim.api.nvim_feedkeys('v', 'xt', false)
markdown.sync_cursor(fixture.buffer)
vim.api.nvim_feedkeys('0', 'xt', false)
markdown.sync_cursor(fixture.buffer)
vim.api.nvim_feedkeys('y', 'xt', false)
markdown.sync_cursor(fixture.buffer)
assert(
  vim.fn.getreg('"') == fixture.long_source_row,
  'Markdown table cursor parking changed the native Visual-mode yank range'
)

-- Moving into nearby prose keeps a visible table stable. Moving the table
-- fully out of the viewport restores prose wrapping immediately.
vim.api.nvim_feedkeys('2j', 'xt', false)
markdown.sync_cursor(fixture.buffer)
local prose_cursor = vim.api.nvim_win_get_cursor(0)
assert(
  prose_cursor[1] == fixture.following_prose_line and not vim.wo.wrap,
  ('Leaving a still-visible table changed its raw source wrapping: '
    .. 'cursor=%s wrap=%s mode=%s'):format(
      vim.inspect(prose_cursor),
      tostring(vim.wo.wrap),
      vim.api.nvim_get_mode().mode
    )
)
vim.api.nvim_win_set_cursor(0, { fixture.last_line, 0 })
vim.cmd('normal! zt')
markdown.sync_cursor(fixture.buffer)
assert(
  vim.wo.wrap,
  'Scrolling the table out of view did not restore prose soft wrapping'
)

rendering_enabled = false
markdown.clear({ buf = fixture.buffer, win = 0 })
vim.api.nvim_set_current_buf(original.buffer)
vim.api.nvim_buf_delete(fixture.buffer, { force = true })
vim.wo.wrap = original.wrap
package.loaded['render-markdown.state'] = original.render_state
package.loaded['render-markdown.request.context'] = original.render_context
