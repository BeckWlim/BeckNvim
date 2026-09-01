local M = {}

local scope_namespace = vim.api.nvim_create_namespace('current_syntax_scope')
local scope_ranges_by_buffer = {}
local pending_refreshes = {}
local max_scope_file_size_bytes = 1024 * 1024
local max_scope_line_count = 5000
M.maximum_highlighted_scope_lines = 120

local rainbow_highlight_groups = {
  'RainbowDelimiterBase',
  'RainbowDelimiterRed',
  'RainbowDelimiterYellow',
  'RainbowDelimiterBlue',
  'RainbowDelimiterOrange',
  'RainbowDelimiterGreen',
  'RainbowDelimiterViolet',
  'RainbowDelimiterCyan',
}

local current_scope_background = '#2B2C26'

function M.should_highlight_scope(buffer_number)
  return not vim.startswith(vim.api.nvim_buf_get_name(buffer_number), 'diffview://')
end

local global_wrapper_node_types = {
  chunk = true,
  document = true,
  module = true,
  program = true,
  source_file = true,
  table_constructor = true,
  translation_unit = true,
}

local cursor_scope_node_types = {
  block = true,
  case_clause = true,
  case_statement = true,
  class_declaration = true,
  class_definition = true,
  class_specifier = true,
  compound_statement = true,
  declaration_list = true,
  do_statement = true,
  else_clause = true,
  enum_specifier = true,
  field_declaration_list = true,
  for_range_loop = true,
  for_statement = true,
  function_declaration = true,
  function_definition = true,
  if_statement = true,
  lambda_expression = true,
  linkage_specification = true,
  match_statement = true,
  method_definition = true,
  namespace_definition = true,
  repeat_statement = true,
  struct_specifier = true,
  switch_statement = true,
  try_statement = true,
  while_statement = true,
  with_statement = true,
}

local function position_is_before_or_equal(left_row, left_column, right_row, right_column)
  return left_row < right_row or (left_row == right_row and left_column <= right_column)
end

local function range_contains_position(scope_range, cursor_row, cursor_column)
  local starts_before_cursor = position_is_before_or_equal(
    scope_range.start_row,
    scope_range.start_column,
    cursor_row,
    cursor_column
  )
  local cursor_is_before_end = cursor_row < scope_range.end_row
    or (cursor_row == scope_range.end_row and cursor_column < scope_range.end_column)
  return starts_before_cursor and cursor_is_before_end
end

local function range_contains_range(outer_range, inner_range)
  return position_is_before_or_equal(
    outer_range.start_row,
    outer_range.start_column,
    inner_range.start_row,
    inner_range.start_column
  ) and position_is_before_or_equal(
    inner_range.end_row,
    inner_range.end_column,
    outer_range.end_row,
    outer_range.end_column
  )
end

local function buffer_is_small_enough(buffer_number)
  if vim.api.nvim_buf_line_count(buffer_number) > max_scope_line_count then
    return false
  end

  local buffer_name = vim.api.nvim_buf_get_name(buffer_number)
  if buffer_name == '' then
    return true
  end

  local file_statistics = vim.uv.fs_stat(buffer_name)
  return not file_statistics or file_statistics.size <= max_scope_file_size_bytes
end

local function buffer_content_range(buffer_number)
  local buffer_lines = vim.api.nvim_buf_get_lines(buffer_number, 0, -1, false)
  local first_content_row
  local first_content_column
  local last_content_row
  local last_content_column

  for line_index, buffer_line in ipairs(buffer_lines) do
    local first_nonblank_byte = buffer_line:find('%S')
    if first_nonblank_byte then
      if not first_content_row then
        first_content_row = line_index - 1
        first_content_column = first_nonblank_byte - 1
      end
      last_content_row = line_index - 1
      last_content_column = #buffer_line
    end
  end

  if not first_content_row then
    return nil
  end
  return {
    start_row = first_content_row,
    start_column = first_content_column,
    end_row = last_content_row,
    end_column = last_content_column,
  }
end

local function collect_scope_ranges(buffer_number, parser)
  local scope_ranges = {}
  local seen_ranges = {}
  local content_range = buffer_content_range(buffer_number)
  if not content_range then
    return scope_ranges
  end

  parser:for_each_tree(function(syntax_tree, language_tree)
    local query_succeeded, context_query = pcall(
      vim.treesitter.query.get,
      language_tree:lang(),
      'context'
    )
    if not query_succeeded or not context_query then
      return
    end

    for capture_id, syntax_node in context_query:iter_captures(
      syntax_tree:root(),
      buffer_number,
      0,
      -1
    ) do
      if context_query.captures[capture_id] == 'context' then
        local start_row, start_column, end_row, end_column = syntax_node:range()
        if end_row > start_row then
          local scope_node_type = syntax_node:type()
          local scope_range = {
            start_row = start_row,
            start_column = start_column,
            end_row = end_row,
            end_column = end_column,
          }
          local range_key = table.concat({ start_row, start_column, end_row, end_column }, ':')
          if
            not seen_ranges[range_key]
            and not M.scope_is_global(scope_range, content_range, scope_node_type)
          then
            seen_ranges[range_key] = true
            scope_ranges[#scope_ranges + 1] = scope_range
          end
        end
      end
    end
  end)

  return scope_ranges
end

local function add_scope_highlight(buffer_number, start_row, start_column, end_row, end_column)
  vim.api.nvim_buf_set_extmark(buffer_number, scope_namespace, start_row, start_column, {
    end_row = end_row,
    end_col = end_column,
    hl_eol = true,
    hl_group = 'CurrentCodeScope',
    hl_mode = 'combine',
    priority = 140,
    strict = false,
  })
end

local function highlight_current_scope(buffer_number)
  if not vim.api.nvim_buf_is_valid(buffer_number) then
    return
  end

  if not M.should_highlight_scope(buffer_number) then
    vim.api.nvim_buf_clear_namespace(buffer_number, scope_namespace, 0, -1)
    return
  end

  if buffer_number ~= vim.api.nvim_get_current_buf() then
    vim.api.nvim_buf_clear_namespace(buffer_number, scope_namespace, 0, -1)
    return
  end

  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_position[1] - 1
  local current_scope = M.innermost_scope(
    scope_ranges_by_buffer[buffer_number] or {},
    cursor_row,
    cursor_position[2]
  )
  if not current_scope then
    current_scope = M.cursor_syntax_scope(
      buffer_number,
      cursor_row,
      cursor_position[2]
    )
  end
  if current_scope and not M.scope_is_highlightable(current_scope) then
    current_scope = nil
  end
  vim.api.nvim_buf_clear_namespace(buffer_number, scope_namespace, 0, -1)
  if not current_scope then
    return
  end

  for _, scope_segment in ipairs(M.scope_segments(current_scope, cursor_row)) do
    add_scope_highlight(
      buffer_number,
      scope_segment.start_row,
      scope_segment.start_column,
      scope_segment.end_row,
      scope_segment.end_column
    )
  end
end

local function refresh_scope_ranges(buffer_number)
  scope_ranges_by_buffer[buffer_number] = {}
  if not vim.api.nvim_buf_is_valid(buffer_number) then
    return
  end
  if vim.bo[buffer_number].buftype ~= '' or not buffer_is_small_enough(buffer_number) then
    highlight_current_scope(buffer_number)
    return
  end

  local parser_succeeded, parser = pcall(vim.treesitter.get_parser, buffer_number)
  if not parser_succeeded or not parser then
    highlight_current_scope(buffer_number)
    return
  end

  local parse_succeeded = pcall(function()
    parser:parse()
  end)
  if parse_succeeded then
    scope_ranges_by_buffer[buffer_number] = collect_scope_ranges(buffer_number, parser)
  end
  highlight_current_scope(buffer_number)
end

local function schedule_scope_refresh(buffer_number)
  if pending_refreshes[buffer_number] then
    return
  end

  pending_refreshes[buffer_number] = true
  vim.defer_fn(function()
    pending_refreshes[buffer_number] = nil
    refresh_scope_ranges(buffer_number)
  end, 80)
end

function M.rainbow_config()
  return {
    highlight = vim.deepcopy(rainbow_highlight_groups),
  }
end

function M.current_scope_color()
  return current_scope_background
end

function M.scope_is_highlightable(scope_range)
  local scope_line_count = scope_range.end_row - scope_range.start_row
  if scope_range.end_column > 0 then
    scope_line_count = scope_line_count + 1
  end
  return scope_line_count <= M.maximum_highlighted_scope_lines
end

function M.scope_segments(scope_range, cursor_row)
  local scope_segments = {}
  if scope_range.start_row < cursor_row then
    scope_segments[#scope_segments + 1] = {
      start_row = scope_range.start_row,
      start_column = scope_range.start_column,
      end_row = cursor_row,
      end_column = 0,
    }
  end
  local row_after_cursor = cursor_row + 1
  if row_after_cursor < scope_range.end_row
      or (row_after_cursor == scope_range.end_row and scope_range.end_column > 0) then
    scope_segments[#scope_segments + 1] = {
      start_row = row_after_cursor,
      start_column = 0,
      end_row = scope_range.end_row,
      end_column = scope_range.end_column,
    }
  end
  return scope_segments
end

function M.cursor_syntax_scope(buffer_number, cursor_row, cursor_column)
  local node_succeeded, cursor_node = pcall(vim.treesitter.get_node, {
    bufnr = buffer_number,
    pos = { cursor_row, cursor_column },
  })
  if not node_succeeded or not cursor_node then
    return nil
  end

  local scope_node = cursor_node
  while scope_node do
    if cursor_scope_node_types[scope_node:type()] then
      local start_row, start_column, end_row, end_column = scope_node:range()
      if end_row > start_row then
        return {
          start_row = start_row,
          start_column = start_column,
          end_row = end_row,
          end_column = end_column,
        }
      end
    end
    scope_node = scope_node:parent()
  end
  return nil
end

function M.scope_is_global(scope_range, content_range, scope_node_type)
  return global_wrapper_node_types[scope_node_type] == true
    and range_contains_range(scope_range, content_range)
end

function M.innermost_scope(scope_ranges, cursor_row, cursor_column)
  local selected_scope
  for _, scope_range in ipairs(scope_ranges) do
    if range_contains_position(scope_range, cursor_row, cursor_column) then
      if not selected_scope or range_contains_range(selected_scope, scope_range) then
        selected_scope = scope_range
      end
    end
  end
  return selected_scope
end

function M.setup_rainbow()
  require('rainbow-delimiters.setup').setup(M.rainbow_config())
end

function M.setup_scopes()
  local group = vim.api.nvim_create_augroup('current_syntax_scope', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'TextChanged', 'InsertLeave' }, {
    group = group,
    callback = function(event)
      schedule_scope_refresh(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    callback = function(event)
      highlight_current_scope(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    callback = function(event)
      scope_ranges_by_buffer[event.buf] = nil
      pending_refreshes[event.buf] = nil
    end,
  })
  schedule_scope_refresh(vim.api.nvim_get_current_buf())
end

return M
