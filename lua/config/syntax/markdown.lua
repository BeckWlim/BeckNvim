local M = {}

M.cell_margins = { left = 1, right = 2 }
M.table_layout = {
  full_width_threshold = 80,
  outer_right_ratio = 0.2,
}

local table_namespace = vim.api.nvim_create_namespace('markdown_tables')
local table_query_cache
local table_query_resolved = false
local extmark_ids_by_buffer = {}
local extmark_specs_by_buffer = {}
local tables_by_buffer = {}
local render_states_by_window = {}
local cursor_states_by_window = {}
local cursor_key_listener_installed = false
local cursor_key_namespace = vim.api.nvim_create_namespace('markdown_table_cursor_keys')
local hidden_cursor

local table_highlights = {
  cell = 'RenderMarkdownTableCell',
  code = 'RenderMarkdownTableCode',
  header = 'RenderMarkdownTableHeader',
  icon = 'RenderMarkdownTableIcon',
  label = 'RenderMarkdownTableLabel',
  row_rule = 'RenderMarkdownTableRowRule',
  rule = 'RenderMarkdownTableRule',
}

local function table_query()
  if table_query_resolved then
    return table_query_cache
  end
  table_query_resolved = true
  pcall(function()
    table_query_cache = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
  end)
  return table_query_cache
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function cell_display_text(raw_text)
  local normalized_text = raw_text:gsub('\r', '')
  local image_labels_removed = normalized_text:gsub('!%[([^%]]-)%]%([^%)]-%)', '%1')
  local link_destinations_removed = image_labels_removed:gsub('%[([^%]]-)%]%([^%)]-%)', '%1')
  local code_ticks_removed = link_destinations_removed:gsub('`([^`]-)`', '%1')
  local unescaped_pipes = code_ticks_removed:gsub('\\|', '|')
  return vim.trim(unescaped_pipes)
end

local function append_display_characters(target, text, is_code, source_start)
  local next_byte = 1
  while next_byte <= #text do
    local escaped_pipe = text:sub(next_byte, next_byte + 1) == '\\|'
    local character_text = escaped_pipe and '|'
      or vim.fn.strcharpart(text:sub(next_byte), 0, 1)
    local source_width = escaped_pipe and 2 or #character_text
    target[#target + 1] = {
      is_code = is_code,
      source_end = source_start + next_byte - 1 + source_width,
      source_start = source_start + next_byte - 1,
      text = character_text,
    }
    next_byte = next_byte + source_width
  end
end

local function display_markup(raw_text, next_byte)
  local prefix = raw_text:sub(next_byte, next_byte)
  local pattern
  local is_code = false
  if prefix == '!' and raw_text:sub(next_byte + 1, next_byte + 1) == '[' then
    pattern = '!%[()([^%]]-)%]%([^%)]-%)'
  elseif prefix == '[' then
    pattern = '%[()([^%]]-)%]%([^%)]-%)'
  elseif prefix == '`' then
    pattern = '`()([^`]*)`'
    is_code = true
  else
    return nil
  end
  local markup_start, markup_end, content_start, content = raw_text:find(
    pattern,
    next_byte
  )
  if markup_start ~= next_byte then
    return nil
  end
  return markup_end, content_start - 1, content, is_code
end

local function cell_display_characters(raw_text)
  local source_characters = {}
  local next_byte = 1
  while next_byte <= #raw_text do
    local markup_end, content_start, content, is_code = display_markup(
      raw_text,
      next_byte
    )
    if markup_end then
      append_display_characters(source_characters, content, is_code, content_start)
      next_byte = markup_end + 1
    elseif raw_text:sub(next_byte, next_byte + 1) == '\\|' then
      source_characters[#source_characters + 1] = {
        is_code = false,
        source_end = next_byte + 1,
        source_start = next_byte - 1,
        text = '|',
      }
      next_byte = next_byte + 2
    else
      local character_text = vim.fn.strcharpart(raw_text:sub(next_byte), 0, 1)
      if character_text ~= '\r' then
        append_display_characters(
          source_characters,
          character_text,
          false,
          next_byte - 1
        )
      end
      next_byte = next_byte + #character_text
    end
  end

  local display_characters = {}
  local pending_space
  for _, source_character in ipairs(source_characters) do
    if source_character.text:match('%s') then
      if pending_space then
        pending_space.source_end = source_character.source_end
      else
        pending_space = vim.tbl_extend('force', {}, source_character, { text = ' ' })
      end
    else
      if pending_space and #display_characters > 0 then
        display_characters[#display_characters + 1] = pending_space
      end
      display_characters[#display_characters + 1] = source_character
      pending_space = nil
    end
  end
  return display_characters
end

local function characters_width(characters)
  local width = 0
  for _, character in ipairs(characters) do
    width = width + display_width(character.text)
  end
  return width
end

local function character_words(characters)
  local words = {}
  local current_word = {}
  for _, character in ipairs(characters) do
    if character.text == ' ' then
      if #current_word > 0 then
        words[#words + 1] = current_word
        current_word = {}
      end
    else
      current_word[#current_word + 1] = character
    end
  end
  if #current_word > 0 then
    words[#words + 1] = current_word
  end
  return words
end

local function split_character_prefix(characters, maximum_width)
  local prefix = {}
  local suffix = {}
  local prefix_width = 0
  for character_index, character in ipairs(characters) do
    local character_width = display_width(character.text)
    if prefix_width + character_width <= maximum_width or #prefix == 0 then
      prefix[#prefix + 1] = character
      prefix_width = prefix_width + character_width
    else
      for suffix_index = character_index, #characters do
        suffix[#suffix + 1] = characters[suffix_index]
      end
      break
    end
  end
  return prefix, suffix
end

local function wrap_cell_characters(text, width)
  local cell_width = math.max(width, 1)
  local display_characters = cell_display_characters(text)
  if #display_characters == 0 then
    return { {} }
  end

  local wrapped_lines = {}
  local current_line = {}
  for _, source_word in ipairs(character_words(display_characters)) do
    local remaining_word = source_word
    local separator_width = #current_line > 0 and 1 or 0
    local candidate_width = characters_width(current_line)
      + separator_width
      + characters_width(remaining_word)
    if candidate_width <= cell_width then
      if separator_width > 0 then
        local preceding_character = current_line[#current_line]
        local following_character = remaining_word[1]
        current_line[#current_line + 1] = {
          is_code = preceding_character.is_code and following_character.is_code,
          source_end = following_character.source_start,
          source_start = preceding_character.source_end,
          text = ' ',
        }
      end
      vim.list_extend(current_line, remaining_word)
    else
      if #current_line > 0 then
        wrapped_lines[#wrapped_lines + 1] = current_line
        current_line = {}
      end
      while characters_width(remaining_word) > cell_width do
        local word_prefix, word_suffix = split_character_prefix(
          remaining_word,
          cell_width
        )
        wrapped_lines[#wrapped_lines + 1] = word_prefix
        remaining_word = word_suffix
      end
      current_line = remaining_word
    end
  end
  if #current_line > 0 then
    wrapped_lines[#wrapped_lines + 1] = current_line
  end
  return wrapped_lines
end

local function characters_text(characters)
  local text_parts = {}
  for _, character in ipairs(characters) do
    text_parts[#text_parts + 1] = character.text
  end
  return table.concat(text_parts)
end

local function characters_chunks(characters, base_highlight)
  local chunks = {}
  for _, character in ipairs(characters) do
    local character_highlight = character.is_code and table_highlights.code
      or base_highlight
    local previous_chunk = chunks[#chunks]
    if previous_chunk and previous_chunk[2] == character_highlight then
      previous_chunk[1] = previous_chunk[1] .. character.text
    else
      chunks[#chunks + 1] = { character.text, character_highlight }
    end
  end
  return chunks
end

---@param text string
---@param width integer
---@return string[]
function M.wrap_cell(text, width)
  return vim.tbl_map(characters_text, wrap_cell_characters(text, width))
end

---@param text string
---@param width integer
---@param base_highlight string
---@return [string, string][][]
function M.wrap_cell_chunks(text, width, base_highlight)
  return vim.tbl_map(function(characters)
    return characters_chunks(characters, base_highlight)
  end, wrap_cell_characters(text, width))
end

local function cursor_location(wrapped_lines, source_offset)
  local fragment = 1
  local character_index = 1
  for line_index, characters in ipairs(wrapped_lines) do
    for index, character in ipairs(characters) do
      if character.source_start and source_offset >= character.source_start then
        fragment = line_index
        character_index = index
      end
    end
  end
  return fragment, character_index
end

local function cursor_fragment(wrapped_lines, source_offset)
  local fragment = cursor_location(wrapped_lines, source_offset)
  return fragment
end

---@param text string
---@param source_offset integer
---@param width integer
---@return integer
function M.cell_fragment(text, source_offset, width)
  return cursor_fragment(
    wrap_cell_characters(text, width),
    math.max(math.min(source_offset, #text), 0)
  )
end

---@param available_width integer
---@param column_count integer
---@param preferred_widths? integer[]
---@return integer[], integer
function M.allocate_widths(available_width, column_count, preferred_widths)
  if column_count <= 0 then
    return {}, 0
  end
  local preferred_gap_width = 2
  local minimum_cell_width = 1
  local preferred_minimum = column_count * minimum_cell_width
    + (column_count - 1) * preferred_gap_width
  local gap_width = available_width >= preferred_minimum and preferred_gap_width or 1
  local content_width = math.max(
    available_width - (column_count - 1) * gap_width,
    column_count
  )
  local requested_widths = {}
  local requested_total = 0
  for column_index = 1, column_count do
    local preferred_width = preferred_widths and preferred_widths[column_index]
      or content_width
    local requested_width = math.max(preferred_width, minimum_cell_width)
    requested_widths[column_index] = requested_width
    requested_total = requested_total + requested_width
  end
  if requested_total <= content_width then
    return requested_widths, gap_width
  end

  local column_widths = {}
  local pending_columns = {}
  for column_index = 1, column_count do
    pending_columns[#pending_columns + 1] = column_index
  end
  local remaining_width = content_width
  while #pending_columns > 0 do
    local fair_width = math.floor(remaining_width / #pending_columns)
    local oversized_columns = {}
    for _, column_index in ipairs(pending_columns) do
      if requested_widths[column_index] <= fair_width then
        column_widths[column_index] = requested_widths[column_index]
        remaining_width = remaining_width - requested_widths[column_index]
      else
        oversized_columns[#oversized_columns + 1] = column_index
      end
    end
    if #oversized_columns == #pending_columns then
      local base_width = math.floor(remaining_width / #oversized_columns)
      local extra_columns = remaining_width % #oversized_columns
      for pending_index, column_index in ipairs(oversized_columns) do
        column_widths[column_index] = base_width
          + (pending_index <= extra_columns and 1 or 0)
      end
      break
    end
    pending_columns = oversized_columns
  end
  return column_widths, gap_width
end

---@param available_width integer
---@return integer
function M.table_width_limit(available_width)
  local usable_ratio = 1 - M.table_layout.outer_right_ratio
  local proportional_width = math.floor(available_width * usable_ratio)
  local responsive_width = math.max(
    proportional_width,
    M.table_layout.full_width_threshold
  )
  return math.max(math.min(available_width, responsive_width), 1)
end

local function node_children(node, child_type)
  local matching_children = {}
  for child in node:iter_children() do
    if child:type() == child_type then
      matching_children[#matching_children + 1] = child
    end
  end
  return matching_children
end

local function row_cells(buffer, row_node)
  local cell_nodes = node_children(row_node, 'pipe_table_cell')
  local cell_texts = {}
  local cell_ranges = {}
  for _, cell_node in ipairs(cell_nodes) do
    cell_texts[#cell_texts + 1] = vim.treesitter.get_node_text(cell_node, buffer)
    local _, start_column, _, end_column = cell_node:range()
    cell_ranges[#cell_ranges + 1] = {
      end_column = end_column,
      start_column = start_column,
    }
  end
  return cell_texts, cell_ranges
end

local function delimiter_alignment(buffer, delimiter_node)
  local delimiter_cells = node_children(delimiter_node, 'pipe_table_delimiter_cell')
  local alignments = {}
  for _, cell_node in ipairs(delimiter_cells) do
    local delimiter_text = vim.trim(vim.treesitter.get_node_text(cell_node, buffer))
    local has_left_marker = delimiter_text:sub(1, 1) == ':'
    local has_right_marker = delimiter_text:sub(-1) == ':'
    if has_left_marker and has_right_marker then
      alignments[#alignments + 1] = 'center'
    elseif has_right_marker then
      alignments[#alignments + 1] = 'right'
    else
      alignments[#alignments + 1] = 'left'
    end
  end
  return alignments
end

local function parse_table(buffer, table_node)
  local table_start_row, table_start_column, table_end_row, table_end_column =
    table_node:range()
  local table_end_exclusive = table_end_column > 0 and table_end_row + 1 or table_end_row
  local header_node
  local delimiter_node
  local data_nodes = {}
  for child_node in table_node:iter_children() do
    local child_type = child_node:type()
    if child_type == 'pipe_table_header' then
      header_node = child_node
    elseif child_type == 'pipe_table_delimiter_row' then
      delimiter_node = child_node
    elseif child_type == 'pipe_table_row' then
      data_nodes[#data_nodes + 1] = child_node
    end
  end
  if not header_node or not delimiter_node then
    return nil
  end
  local header_cells, header_cell_ranges = row_cells(buffer, header_node)
  if #header_cells == 0 then
    return nil
  end
  local header_row = select(1, header_node:range())
  local rows = {
    {
      cell_ranges = header_cell_ranges,
      cells = header_cells,
      role = 'header',
      source_row = header_row,
    },
  }
  for _, data_node in ipairs(data_nodes) do
    local data_cells, data_cell_ranges = row_cells(buffer, data_node)
    if #data_cells == #header_cells then
      rows[#rows + 1] = {
        cell_ranges = data_cell_ranges,
        cells = data_cells,
        role = 'cell',
        source_row = select(1, data_node:range()),
      }
    end
  end
  return {
    alignments = delimiter_alignment(buffer, delimiter_node),
    column_count = #header_cells,
    delimiter_row = select(1, delimiter_node:range()),
    end_row = table_end_exclusive,
    rows = rows,
    start_column = table_start_column,
    start_row = table_start_row,
  }
end

local function chunks_width(chunks)
  local width = 0
  for _, chunk in ipairs(chunks) do
    width = width + display_width(chunk[1])
  end
  return width
end

local function padded_chunks(chunks, width, alignment, base_highlight)
  local remaining_width = math.max(width - chunks_width(chunks), 0)
  local left_padding = 0
  if alignment == 'right' then
    left_padding = remaining_width
  elseif alignment == 'center' then
    left_padding = math.floor(remaining_width / 2)
  end
  local right_padding = remaining_width - left_padding
  local padded = { { string.rep(' ', left_padding), base_highlight } }
  vim.list_extend(padded, chunks)
  padded[#padded + 1] = { string.rep(' ', right_padding), base_highlight }
  return padded, left_padding
end

local function active_cell(row, interaction)
  if not interaction
      or (interaction.mode ~= 'n'
        and interaction.mode ~= 'v'
        and interaction.mode ~= 'V'
        and interaction.mode ~= '\22')
      or interaction.cursor.row ~= row.source_row
      or not row.cell_ranges then
    return nil, nil
  end
  local cell_index = 1
  for range_index, cell_range in ipairs(row.cell_ranges) do
    if interaction.cursor.column < cell_range.start_column then
      break
    end
    cell_index = range_index
    if interaction.cursor.column < cell_range.end_column then
      break
    end
  end
  local cell_range = row.cell_ranges[cell_index]
  local source_offset = math.max(
    math.min(
      interaction.cursor.column - cell_range.start_column,
      #row.cells[cell_index]
    ),
    0
  )
  return cell_index, source_offset
end

local function layered_highlight(base, highlight)
  local highlights = type(base) == 'table' and vim.deepcopy(base) or { base }
  highlights[#highlights + 1] = highlight
  return highlights
end

local function highlighted_fragment_chunks(chunks, highlight)
  return vim.tbl_map(function(chunk)
    return { chunk[1], layered_highlight(chunk[2], highlight) }
  end, chunks)
end

local function append_chunk(chunks, text, highlight)
  local previous = chunks[#chunks]
  if previous and vim.deep_equal(previous[2], highlight) then
    previous[1] = previous[1] .. text
  else
    chunks[#chunks + 1] = { text, highlight }
  end
end

local function cursor_proxy_chunks(chunks, cursor_column)
  local rendered = {}
  local display_column = 0
  local cursor_added = false
  for _, chunk in ipairs(chunks) do
    local character_count = vim.fn.strchars(chunk[1])
    for character_index = 0, character_count - 1 do
      local character = vim.fn.strcharpart(chunk[1], character_index, 1)
      local highlight = chunk[2]
      if not cursor_added and display_column == cursor_column then
        highlight = layered_highlight(highlight, 'Cursor')
        cursor_added = true
      end
      append_chunk(rendered, character, highlight)
      display_column = display_column + display_width(character)
    end
  end
  return rendered
end

local function ordered_positions(first, second)
  if first.row < second.row
      or first.row == second.row and first.column <= second.column then
    return first, second
  end
  return second, first
end

local function visual_columns(interaction, source_row)
  if not interaction or not interaction.anchor then
    return nil, nil
  end
  local first, last = ordered_positions(interaction.anchor, interaction.cursor)
  if source_row < first.row or source_row > last.row then
    return nil, nil
  end
  if interaction.mode == 'V' then
    return 0, math.huge
  elseif interaction.mode == '\22' then
    return math.min(first.column, last.column), math.max(first.column, last.column)
  end
  local start_column = source_row == first.row and first.column or 0
  local end_column = source_row == last.row and last.column or math.huge
  return start_column, end_column
end

local function selected_character_ranges(row, wrapped_characters, interaction)
  local selection_start, selection_end = visual_columns(interaction, row.source_row)
  if not selection_start or not row.cell_ranges then
    return {}
  end
  local selected = {}
  for cell_index, cell_range in ipairs(row.cell_ranges) do
    local cell_end = cell_range.end_column - 1
    if selection_end >= cell_range.start_column and selection_start <= cell_end then
      local selected_lines = {}
      for line_index, characters in ipairs(wrapped_characters[cell_index]) do
        local display_column = 0
        local first_column
        local last_column
        for _, character in ipairs(characters) do
          local character_width = display_width(character.text)
          local character_start = cell_range.start_column
            + (character.source_start or 0)
          local character_end = cell_range.start_column
            + (character.source_end or character.source_start or 0)
          if selection_end >= character_start and selection_start < character_end then
            first_column = first_column or display_column
            last_column = display_column + character_width
          end
          display_column = display_column + character_width
        end
        if first_column then
          selected_lines[line_index] = {
            first_column = first_column,
            last_column = last_column,
          }
        end
      end
      if interaction.mode == 'V' or next(selected_lines) then
        selected[cell_index] = selected_lines
      end
    end
  end
  return selected
end

local function highlighted_range_chunks(chunks, first_column, last_column, highlight)
  local rendered = {}
  local display_column = 0
  for _, chunk in ipairs(chunks) do
    local character_count = vim.fn.strchars(chunk[1])
    for character_index = 0, character_count - 1 do
      local character = vim.fn.strcharpart(chunk[1], character_index, 1)
      local character_width = display_width(character)
      local character_highlight = chunk[2]
      if display_column < last_column
          and display_column + character_width > first_column then
        character_highlight = layered_highlight(character_highlight, highlight)
      end
      append_chunk(rendered, character, character_highlight)
      display_column = display_column + character_width
    end
  end
  return rendered
end

local function prepare_row(row, column_widths)
  local wrapped_cells = {}
  local wrapped_characters = {}
  local line_count = 1
  for column_index, cell_text in ipairs(row.cells) do
    local cell_characters = wrap_cell_characters(cell_text, column_widths[column_index])
    local cell_lines = vim.tbl_map(function(characters)
      return characters_chunks(characters, table_highlights[row.role])
    end, cell_characters)
    wrapped_characters[column_index] = cell_characters
    wrapped_cells[column_index] = cell_lines
    line_count = math.max(line_count, #cell_lines)
  end
  return {
    line_count = line_count,
    wrapped_cells = wrapped_cells,
    wrapped_characters = wrapped_characters,
  }
end

local function row_lines(
  row,
  column_widths,
  gap_width,
  alignments,
  interaction,
  prepared_row
)
  local prepared = prepared_row or prepare_row(row, column_widths)
  local wrapped_cells = prepared.wrapped_cells
  local wrapped_characters = prepared.wrapped_characters
  local active_cell_index, source_offset = active_cell(row, interaction)
  local active_fragment
  local active_character_index
  if active_cell_index then
    active_fragment, active_character_index = cursor_location(
      wrapped_characters[active_cell_index],
      source_offset
    )
  end
  local selected = selected_character_ranges(row, wrapped_characters, interaction)

  local rendered_lines = {}
  for line_index = 1, prepared.line_count do
    local line_chunks = {}
    for column_index = 1, #column_widths do
      local cell_line = wrapped_cells[column_index][line_index] or {}
      local cell_chunks, left_padding = padded_chunks(
        cell_line,
        column_widths[column_index],
        alignments[column_index],
        table_highlights[row.role]
      )
      local selected_range = selected[column_index]
        and selected[column_index][line_index]
      local active_fragment_cell = column_index == active_cell_index
        and line_index == active_fragment
      if interaction and interaction.mode == 'V' and selected[column_index] then
        cell_chunks = highlighted_fragment_chunks(cell_chunks, 'Visual')
      elseif selected_range then
        cell_chunks = highlighted_range_chunks(
          cell_chunks,
          left_padding + selected_range.first_column,
          left_padding + selected_range.last_column,
          'Visual'
        )
      elseif active_fragment_cell then
        cell_chunks = highlighted_fragment_chunks(cell_chunks, 'CursorLine')
      end
      if active_fragment_cell then
        local cursor_column = left_padding
        local characters = wrapped_characters[column_index][line_index] or {}
        for character_index = 1, active_character_index - 1 do
          cursor_column = cursor_column + display_width(characters[character_index].text)
        end
        cell_chunks = cursor_proxy_chunks(cell_chunks, cursor_column)
      end
      vim.list_extend(line_chunks, cell_chunks)
      if column_index < #column_widths then
        line_chunks[#line_chunks + 1] = {
          string.rep(' ', gap_width),
          table_highlights[row.role],
        }
      end
    end
    rendered_lines[#rendered_lines + 1] = line_chunks
  end
  return rendered_lines
end

local function preferred_column_widths(rows, column_count)
  local preferred_widths = {}
  for column_index = 1, column_count do
    preferred_widths[column_index] = 1
  end
  for _, row in ipairs(rows) do
    for column_index, cell_text in ipairs(row.cells) do
      local cell_width = display_width(cell_display_text(cell_text))
      preferred_widths[column_index] = math.max(
        preferred_widths[column_index],
        cell_width
      )
    end
  end
  return preferred_widths
end

local function indented_line(indentation, chunks)
  local rendered_chunks = { { indentation, table_highlights.cell } }
  vim.list_extend(rendered_chunks, chunks)
  return rendered_chunks
end

local function content_line(indentation, chunks)
  local content_chunks = {
    { string.rep(' ', M.cell_margins.left), table_highlights.cell },
  }
  vim.list_extend(content_chunks, chunks)
  content_chunks[#content_chunks + 1] = {
    string.rep(' ', M.cell_margins.right),
    table_highlights.cell,
  }
  return indented_line(indentation, content_chunks)
end

local function line_number_value(window, source_row)
  local number_enabled = vim.wo[window].number
  local relative_number_enabled = vim.wo[window].relativenumber
  if relative_number_enabled then
    local cursor_row = vim.api.nvim_win_get_cursor(window)[1] - 1
    if source_row == cursor_row then
      return number_enabled and source_row + 1 or 0
    end
    return math.abs(source_row - cursor_row)
  end
  return number_enabled and source_row + 1 or nil
end

local function gutter_text(window, source_row, gutter_width)
  if gutter_width == 0 then
    return ''
  end
  local number_value = source_row and line_number_value(window, source_row) or nil
  if number_value == nil then
    return string.rep(' ', gutter_width)
  end
  local number_text = tostring(number_value)
  local leading_width = math.max(gutter_width - #number_text - 1, 0)
  return string.rep(' ', leading_width) .. number_text .. ' '
end

local function add_group_gutters(window, groups, gutter_width)
  for _, group in ipairs(groups) do
    for line_index, rendered_line in ipairs(group.lines) do
      local source_row = line_index == 1 and group.source_row or nil
      local gutter_highlight = source_row and 'LineNr' or 'Normal'
      table.insert(rendered_line, 1, {
        gutter_text(window, source_row, gutter_width),
        gutter_highlight,
      })
    end
  end
end

local function table_mode(mode)
  if mode:sub(1, 1) == 'n' then
    return 'n'
  end
  if mode == 'v' or mode == 'V' or mode == '\22' then
    return mode
  end
  return nil
end

local function window_interaction(window)
  local mode = table_mode(vim.api.nvim_get_mode().mode)
  if not mode then
    return nil
  end
  local buffer = vim.api.nvim_win_get_buf(window)
  local cursor_state = cursor_states_by_window[window]
  if cursor_state
      and cursor_state.parked
      and cursor_state.buffer == buffer
      and cursor_state.interaction.mode == mode then
    return cursor_state.interaction
  end
  local cursor_position = vim.api.nvim_win_get_cursor(window)
  local interaction = {
    cursor = {
      column = cursor_position[2],
      row = cursor_position[1] - 1,
    },
    mode = mode,
  }
  if mode ~= 'n' then
    local selection_position = vim.fn.getpos('v')
    interaction.anchor = {
      column = selection_position[3] - 1,
      row = selection_position[2] - 1,
    }
  end
  return interaction
end

local function table_row_group(parsed_table, row, row_index, layout, interaction)
  local row_alignments = row_index == 1
      and layout.header_alignments
    or parsed_table.alignments
  return {
    lines = vim.tbl_map(function(rendered_line)
      return content_line(layout.indentation, rendered_line)
    end, row_lines(
      row,
      layout.column_widths,
      layout.gap_width,
      row_alignments,
      interaction,
      layout.prepared_rows[row.source_row]
    )),
    source_row = row.source_row,
  }
end

local function table_groups(window, parsed_table, interaction)
  local window_info = vim.fn.getwininfo(window)[1] or { textoff = 0 }
  local text_width = vim.api.nvim_win_get_width(window) - window_info.textoff
  local available_width = math.max(text_width - parsed_table.start_column, 1)
  local table_width_limit = M.table_width_limit(available_width)
  local horizontal_margin = M.cell_margins.left + M.cell_margins.right
  local available_content_width = math.max(table_width_limit - horizontal_margin, 1)
  local preferred_widths = preferred_column_widths(
    parsed_table.rows,
    parsed_table.column_count
  )
  local column_widths, gap_width = M.allocate_widths(
    available_content_width,
    parsed_table.column_count,
    preferred_widths
  )
  local table_width = 0
  for _, column_width in ipairs(column_widths) do
    table_width = table_width + column_width
  end
  table_width = table_width
    + (#column_widths - 1) * gap_width
    + horizontal_margin

  local indentation = string.rep(' ', parsed_table.start_column)
  local label_text = '󰈙 table'
  local label_width = display_width(label_text)
  if table_width < label_width then
    local last_column_index = #column_widths
    column_widths[last_column_index] = column_widths[last_column_index]
      + label_width - table_width
    table_width = label_width
  end
  local groups = {
    {
      lines = {
        indented_line(indentation, {
          { '󰈙 ', table_highlights.icon },
          { 'table' .. string.rep(' ', table_width - label_width), table_highlights.label },
        }),
      },
    },
  }
  local header_alignments = {}
  for column_index = 1, parsed_table.column_count do
    header_alignments[column_index] = 'center'
  end
  local layout = {
    column_widths = column_widths,
    gap_width = gap_width,
    header_alignments = header_alignments,
    indentation = indentation,
    prepared_rows = {},
    textoff = window_info.textoff,
    trailing_lines = {},
  }
  for row_index, row in ipairs(parsed_table.rows) do
    layout.prepared_rows[row.source_row] = prepare_row(row, column_widths)
    groups[#groups + 1] = table_row_group(
      parsed_table,
      row,
      row_index,
      layout,
      interaction
    )
    if row_index == 1 then
      groups[#groups + 1] = {
        lines = {
          indented_line(indentation, {
            { string.rep('─', table_width), table_highlights.rule },
          }),
        },
        source_row = parsed_table.delimiter_row,
      }
    elseif row_index < #parsed_table.rows then
      groups[#groups + 1] = {
        lines = {
          indented_line(indentation, {
            { string.rep('┈', table_width), table_highlights.row_rule },
          }),
        },
      }
    end
  end
  groups[#groups + 1] = {
    lines = {
      indented_line(indentation, {
        { string.rep('─', table_width), table_highlights.rule },
      }),
    },
  }
  add_group_gutters(window, groups, window_info.textoff)
  return groups, layout
end

local function stage_extmark(staged_extmarks, row, options, semantic_key)
  local resolved_options = vim.tbl_extend('force', {}, options, { strict = false })
  if resolved_options.virt_lines then
    resolved_options.virt_lines_leftcol = true
  end
  staged_extmarks[#staged_extmarks + 1] = {
    key = semantic_key or ('position:%d'):format(#staged_extmarks + 1),
    options = resolved_options,
    row = row,
  }
end

local function table_label_row(buffer, parsed_table)
  if parsed_table.start_row == 0 then
    return nil
  end
  local label_row = parsed_table.start_row - 1
  local preceding_line = vim.api.nvim_buf_get_lines(
    buffer,
    label_row,
    label_row + 1,
    false
  )[1] or ''
  return vim.trim(preceding_line) == '' and label_row or nil
end

local function row_in_table(row, parsed_tables)
  for _, parsed_table in ipairs(parsed_tables) do
    if row >= parsed_table.start_row and row < parsed_table.end_row then
      return true
    end
  end
  return false
end

local function row_has_cursor_proxy(row, parsed_tables)
  for _, parsed_table in ipairs(parsed_tables) do
    for _, table_row in ipairs(parsed_table.rows) do
      if table_row.source_row == row then
        return true
      end
    end
  end
  return false
end

local function release_parked_cursor(buffer, window, restore_position)
  local cursor_state = cursor_states_by_window[window]
  if not cursor_state or (buffer and cursor_state.buffer ~= buffer) then
    return
  end
  cursor_states_by_window[window] = nil
  if not restore_position
      or not cursor_state.parked
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= cursor_state.buffer then
    return
  end
  local cursor = cursor_state.interaction.cursor
  pcall(vim.api.nvim_win_set_cursor, window, { cursor.row + 1, cursor.column })
end

local function park_native_cursor(buffer, window, parsed_tables, interaction)
  if vim.api.nvim_get_current_win() ~= window
      or not interaction
      or not row_has_cursor_proxy(interaction.cursor.row, parsed_tables) then
    release_parked_cursor(buffer, window, false)
    return false
  end
  cursor_states_by_window[window] = {
    buffer = buffer,
    interaction = interaction,
    parked = true,
  }
  local cursor_position = vim.api.nvim_win_get_cursor(window)
  if cursor_position[2] ~= 0 then
    vim.api.nvim_win_set_cursor(window, { cursor_position[1], 0 })
  end
  return true
end

local function restore_cursor_for_input()
  local window = vim.api.nvim_get_current_win()
  local cursor_state = cursor_states_by_window[window]
  if not cursor_state
      or not cursor_state.parked
      or not table_mode(vim.api.nvim_get_mode().mode)
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= cursor_state.buffer then
    return
  end
  cursor_state.parked = false
  local cursor = cursor_state.interaction.cursor
  local succeeded = pcall(
    vim.api.nvim_win_set_cursor,
    window,
    { cursor.row + 1, cursor.column }
  )
  if not succeeded then
    cursor_states_by_window[window] = nil
  end
end

local function ensure_cursor_key_listener()
  if cursor_key_listener_installed then
    return
  end
  vim.on_key(restore_cursor_for_input, cursor_key_namespace)
  cursor_key_listener_installed = true
end

local function restore_native_cursor(buffer, window)
  if not hidden_cursor
      or (buffer and hidden_cursor.buffer ~= buffer)
      or (window and hidden_cursor.window ~= window) then
    return
  end
  if vim.o.guicursor == hidden_cursor.value then
    vim.o.guicursor = hidden_cursor.original
  end
  hidden_cursor = nil
end

local function sync_native_cursor(buffer, window, parsed_tables)
  if vim.api.nvim_get_current_win() ~= window then
    return
  end
  local mode = table_mode(vim.api.nvim_get_mode().mode)
  local cursor_row = vim.api.nvim_win_get_cursor(window)[1] - 1
  if not mode or not row_has_cursor_proxy(cursor_row, parsed_tables) then
    restore_native_cursor()
    return
  end
  if hidden_cursor
      and hidden_cursor.buffer == buffer
      and hidden_cursor.window == window then
    return
  end
  restore_native_cursor()
  local original = vim.o.guicursor
  local separator = original == '' and '' or ','
  local value = original
    .. separator
    .. 'n-v:block-RenderMarkdownTableHiddenCursor'
  vim.o.guicursor = value
  hidden_cursor = {
    buffer = buffer,
    original = original,
    value = value,
    window = window,
  }
end

local function table_interaction(window, parsed_tables, mode)
  local cursor_row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local normalized_mode = table_mode(mode)
  if normalized_mode == 'n' then
    return row_in_table(cursor_row, parsed_tables)
  end
  if not normalized_mode then
    return false
  end
  local selection_row = vim.fn.getpos('v')[2] - 1
  local first_row = math.min(cursor_row, selection_row)
  local last_row = math.max(cursor_row, selection_row)
  for _, parsed_table in ipairs(parsed_tables) do
    if last_row >= parsed_table.start_row and first_row < parsed_table.end_row then
      return true
    end
  end
  return false
end

local function table_intersects_view(window, parsed_tables)
  local view_rows = vim.api.nvim_win_call(window, function()
    return { vim.fn.line('w0') - 1, vim.fn.line('w$') }
  end)
  for _, parsed_table in ipairs(parsed_tables) do
    if parsed_table.start_row < view_rows[2]
        and parsed_table.end_row > view_rows[1] then
      return true
    end
  end
  return false
end

local function preserve_table_preview(context)
  local buffer = context.buf
  local window = context.win
  local mode = vim.api.nvim_get_mode().mode
  if type(window) ~= 'number'
      or not vim.api.nvim_buf_is_valid(buffer)
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= buffer
      or not require('render-markdown.state').get(buffer).enabled then
    return false
  end
  if not table_interaction(window, tables_by_buffer[buffer] or {}, mode) then
    return false
  end
  if mode == 'v' or mode == 'V' or mode == '\22' then
    return true
  end
  local left_column = vim.api.nvim_win_call(window, function()
    return vim.fn.winsaveview().leftcol
  end)
  return left_column > 0
end

local function render_table_label(buffer, staged_extmarks, parsed_table, groups)
  local label_group = groups[1]
  if not label_group or #label_group.lines == 0 then
    return
  end
  local available_label_row = table_label_row(buffer, parsed_table)
  local label_key = ('table:%d:label'):format(parsed_table.start_row)
  if available_label_row then
      local label_chunks = {}
      for chunk_index = 2, #label_group.lines[1] do
        label_chunks[#label_chunks + 1] = label_group.lines[1][chunk_index]
      end
      stage_extmark(staged_extmarks, available_label_row, {
        priority = 122,
        virt_text = label_chunks,
        virt_text_pos = 'overlay',
      }, label_key)
      return
  end
  local fallback_anchor_row = math.max(parsed_table.start_row - 1, 0)
  stage_extmark(staged_extmarks, fallback_anchor_row, {
    priority = 118,
    virt_lines = label_group.lines,
    virt_lines_above = parsed_table.start_row == 0,
  }, label_key)
end

local function source_displays(groups)
  local displays = {}
  for group_index = 2, #groups do
    local group = groups[group_index]
    if group.source_row then
      displays[#displays + 1] = {
        lines = group.lines,
        source_row = group.source_row,
        trailing_lines = {},
      }
    elseif #displays > 0 then
      vim.list_extend(displays[#displays].trailing_lines, group.lines)
    end
  end
  return displays
end

local function line_text_chunks(rendered_line)
  local text_chunks = {}
  for chunk_index = 2, #rendered_line do
    text_chunks[#text_chunks + 1] = rendered_line[chunk_index]
  end
  return text_chunks
end

local function overlay_text_chunks(rendered_line, source_line)
  local text_chunks = line_text_chunks(rendered_line)
  local padding_width = math.max(
    display_width(source_line) - chunks_width(text_chunks),
    0
  )
  if padding_width > 0 then
    text_chunks[#text_chunks + 1] = {
      string.rep(' ', padding_width),
      table_highlights.cell,
    }
  end
  return text_chunks
end

local function stage_table_row(buffer, staged_extmarks, parsed_table, display)
  local row_key = ('table:%d:row:%d'):format(
    parsed_table.start_row,
    display.source_row
  )
  local virtual_lines = {}
  local source_line = vim.api.nvim_buf_get_lines(
    buffer,
    display.source_row,
    display.source_row + 1,
    false
  )[1] or ''
  stage_extmark(staged_extmarks, display.source_row, {
    priority = 121,
    virt_text = overlay_text_chunks(display.lines[1], source_line),
    virt_text_win_col = 0,
  }, row_key .. ':overlay')
  for line_index = 2, #display.lines do
    virtual_lines[#virtual_lines + 1] = display.lines[line_index]
  end
  vim.list_extend(virtual_lines, display.trailing_lines)
  local line_options = { priority = 120 }
  if #virtual_lines > 0 then
    line_options.virt_lines = virtual_lines
  end
  stage_extmark(
    staged_extmarks,
    display.source_row,
    line_options,
    row_key .. ':lines'
  )
end

function M.stage_table_rows(buffer, staged_extmarks, parsed_table, groups)
  for _, display in ipairs(source_displays(groups)) do
    stage_table_row(buffer, staged_extmarks, parsed_table, display)
  end
end

local function set_extmark(buffer, current_id, current_spec, staged_extmark)
  local unchanged = current_id ~= nil
    and (current_spec == staged_extmark
      or vim.deep_equal(current_spec, staged_extmark))
  if unchanged then
    return current_id
  end
  local resolved_options = current_id
      and vim.tbl_extend('force', {}, staged_extmark.options, {
        id = current_id,
      })
    or staged_extmark.options
  return vim.api.nvim_buf_set_extmark(
    buffer,
    table_namespace,
    staged_extmark.row,
    0,
    resolved_options
  )
end

local function apply_extmarks(buffer, staged_extmarks)
  local current_extmark_ids = extmark_ids_by_buffer[buffer] or {}
  local current_extmark_specs = extmark_specs_by_buffer[buffer] or {}
  local next_extmark_ids = {}
  local next_extmark_specs = {}
  for _, staged_extmark in ipairs(staged_extmarks) do
    local current_extmark_id = current_extmark_ids[staged_extmark.key]
    local current_extmark_spec = current_extmark_specs[staged_extmark.key]
    next_extmark_ids[staged_extmark.key] = set_extmark(
      buffer,
      current_extmark_id,
      current_extmark_spec,
      staged_extmark
    )
    next_extmark_specs[staged_extmark.key] = staged_extmark
  end
  for semantic_key, current_extmark_id in pairs(current_extmark_ids) do
    if not next_extmark_ids[semantic_key] then
      vim.api.nvim_buf_del_extmark(buffer, table_namespace, current_extmark_id)
    end
  end
  extmark_ids_by_buffer[buffer] = next_extmark_ids
  extmark_specs_by_buffer[buffer] = next_extmark_specs
end

local function update_extmarks(buffer, staged_extmarks)
  local extmark_ids = extmark_ids_by_buffer[buffer] or {}
  local extmark_specs = extmark_specs_by_buffer[buffer] or {}
  for _, staged_extmark in ipairs(staged_extmarks) do
    extmark_ids[staged_extmark.key] = set_extmark(
      buffer,
      extmark_ids[staged_extmark.key],
      extmark_specs[staged_extmark.key],
      staged_extmark
    )
    extmark_specs[staged_extmark.key] = staged_extmark
  end
  extmark_ids_by_buffer[buffer] = extmark_ids
  extmark_specs_by_buffer[buffer] = extmark_specs
end

local function invalidate_render_states(buffer)
  for window, render_state in pairs(render_states_by_window) do
    if render_state.buffer == buffer then
      render_states_by_window[window] = nil
    end
  end
end

---@param context render.md.handler.Context
---@return render.md.Mark[]
function M.parse(context)
  invalidate_render_states(context.buf)
  local parsed_query = table_query()
  if not parsed_query then
    tables_by_buffer[context.buf] = {}
    return {}
  end
  local render_context = require('render-markdown.request.context').get(context.buf)
  local parsed_tables = {}
  render_context.view:query(context.root, parsed_query, function(_, table_node)
    if not table_node:has_error() then
      local parsed_table = parse_table(context.buf, table_node)
      if parsed_table then
        parsed_tables[#parsed_tables + 1] = parsed_table
      end
    end
  end)
  tables_by_buffer[context.buf] = parsed_tables
  return {}
end

function M.attach(context)
  ensure_cursor_key_listener()
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'ModeChanged' }, {
    buffer = context.buf,
    callback = function()
      M.sync_cursor(context.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    buffer = context.buf,
    callback = function()
      local window = vim.api.nvim_get_current_win()
      release_parked_cursor(context.buf, window, true)
      restore_native_cursor(context.buf, window)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = context.buf,
    once = true,
    callback = function()
      restore_native_cursor(context.buf)
      for window, cursor_state in pairs(cursor_states_by_window) do
        if cursor_state.buffer == context.buf then
          cursor_states_by_window[window] = nil
        end
      end
      extmark_ids_by_buffer[context.buf] = nil
      extmark_specs_by_buffer[context.buf] = nil
      tables_by_buffer[context.buf] = nil
      invalidate_render_states(context.buf)
    end,
  })
end

local function window_render_signature(window)
  local window_info = vim.fn.getwininfo(window)[1] or { textoff = 0 }
  return table.concat({
    vim.api.nvim_win_get_width(window),
    window_info.textoff,
    tostring(vim.wo[window].number),
    tostring(vim.wo[window].relativenumber),
  }, ':')
end

local function same_visual_anchor(render_state, interaction)
  if not interaction.anchor then
    return render_state.anchor_column == nil and render_state.anchor_row == nil
  end
  return render_state.anchor_column == interaction.anchor.column
    and render_state.anchor_row == interaction.anchor.row
end

local function update_cursor_row(
  buffer,
  window,
  parsed_tables,
  interaction,
  render_state
)
  if render_state.cursor_column == interaction.cursor.column then
    sync_native_cursor(buffer, window, parsed_tables)
    return true
  end
  for table_index, parsed_table in ipairs(parsed_tables) do
    local layout = render_state.layouts[table_index]
    for row_index, row in ipairs(parsed_table.rows) do
      if row.source_row == interaction.cursor.row and layout then
        local group = table_row_group(
          parsed_table,
          row,
          row_index,
          layout,
          interaction
        )
        add_group_gutters(window, { group }, layout.textoff)
        local staged_extmarks = {}
        stage_table_row(buffer, staged_extmarks, parsed_table, {
          lines = group.lines,
          source_row = row.source_row,
          trailing_lines = layout.trailing_lines[row.source_row] or {},
        })
        update_extmarks(buffer, staged_extmarks)
        render_state.cursor_column = interaction.cursor.column
        sync_native_cursor(buffer, window, parsed_tables)
        return true
      end
    end
  end
  return false
end

local function render_tables(buffer, window)
  local parsed_tables = tables_by_buffer[buffer] or {}
  local interaction = window_interaction(window)
  local mode = interaction and interaction.mode or vim.api.nvim_get_mode().mode
  vim.wo[window].wrap = not table_intersects_view(window, parsed_tables)
  local signature = window_render_signature(window)
  local changedtick = vim.api.nvim_buf_get_changedtick(buffer)
  local render_state = render_states_by_window[window]
  local incremental_mode = mode == 'n'
    or mode == 'v'
    or mode == 'V'
    or mode == '\22'
  if interaction
      and incremental_mode
      and render_state
      and render_state.buffer == buffer
      and render_state.changedtick == changedtick
      and render_state.cursor_row == interaction.cursor.row
      and render_state.mode == mode
      and same_visual_anchor(render_state, interaction)
      and render_state.parsed_tables == parsed_tables
      and render_state.signature == signature
      and update_cursor_row(
        buffer,
        window,
        parsed_tables,
        interaction,
        render_state
      ) then
    return
  end

  local staged_extmarks = {}
  local layouts = {}
  for table_index, parsed_table in ipairs(parsed_tables) do
    local groups, layout = table_groups(window, parsed_table, interaction)
    layouts[table_index] = layout
    for _, display in ipairs(source_displays(groups)) do
      layout.trailing_lines[display.source_row] = display.trailing_lines
    end
    render_table_label(buffer, staged_extmarks, parsed_table, groups)
    M.stage_table_rows(buffer, staged_extmarks, parsed_table, groups)
  end
  apply_extmarks(buffer, staged_extmarks)
  render_states_by_window[window] = {
    anchor_column = interaction and interaction.anchor
        and interaction.anchor.column
      or nil,
    anchor_row = interaction and interaction.anchor and interaction.anchor.row or nil,
    buffer = buffer,
    changedtick = changedtick,
    cursor_column = interaction and interaction.cursor.column or nil,
    cursor_row = interaction and interaction.cursor.row or nil,
    layouts = layouts,
    mode = mode,
    parsed_tables = parsed_tables,
    signature = signature,
  }
  sync_native_cursor(buffer, window, parsed_tables)
end

function M.clear(context)
  if preserve_table_preview(context) then
    render_tables(context.buf, context.win)
    return
  end
  release_parked_cursor(context.buf, context.win, true)
  restore_native_cursor(context.buf, context.win)
  if vim.api.nvim_buf_is_valid(context.buf) then
    vim.api.nvim_buf_clear_namespace(context.buf, table_namespace, 0, -1)
  end
  extmark_ids_by_buffer[context.buf] = nil
  extmark_specs_by_buffer[context.buf] = nil
  invalidate_render_states(context.buf)
end

function M.render(context)
  local buffer = context.buf
  local window = context.win
  if not vim.api.nvim_buf_is_valid(buffer)
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= buffer then
    return
  end
  local mode = vim.api.nvim_get_mode().mode
  if vim.api.nvim_get_current_win() == window
      and table_interaction(window, tables_by_buffer[buffer] or {}, mode) then
    M.sync_cursor(buffer)
    return
  end
  render_tables(buffer, window)
end

function M.sync_cursor(buffer)
  local window = vim.api.nvim_get_current_win()
  if not vim.api.nvim_buf_is_valid(buffer)
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= buffer then
    restore_native_cursor(buffer)
    return
  end
  local parsed_tables = tables_by_buffer[buffer] or {}
  local mode = vim.api.nvim_get_mode().mode
  local rendering_enabled = require('render-markdown.state').get(buffer).enabled
  local interacting_with_table = rendering_enabled
    and table_interaction(window, parsed_tables, mode)
  if not interacting_with_table then
    release_parked_cursor(buffer, window, true)
    restore_native_cursor(buffer, window)
    if rendering_enabled and table_mode(mode) == 'n' then
      vim.wo[window].wrap = not table_intersects_view(window, parsed_tables)
    end
    return
  end
  local cursor_state = cursor_states_by_window[window]
  local interaction = cursor_state
      and cursor_state.parked
      and cursor_state.buffer == buffer
      and cursor_state.interaction
    or window_interaction(window)
  park_native_cursor(buffer, window, parsed_tables, interaction)
  vim.api.nvim_win_call(window, function()
    local view = vim.fn.winsaveview()
    if view.leftcol > 0 then
      view.leftcol = 0
      vim.fn.winrestview(view)
    end
  end)
  render_tables(buffer, window)
end

M.handler = {
  extends = true,
  parse = M.parse,
}

return M
