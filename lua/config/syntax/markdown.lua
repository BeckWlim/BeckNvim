local M = {}

M.cell_margins = { left = 1, right = 2 }
M.table_editing = { wrap = false }
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

local function append_display_characters(target, text, is_code)
  local character_count = vim.fn.strchars(text)
  for character_index = 0, character_count - 1 do
    target[#target + 1] = {
      is_code = is_code,
      text = vim.fn.strcharpart(text, character_index, 1),
    }
  end
end

local function cell_display_characters(raw_text)
  local normalized_text = raw_text:gsub('\r', '')
  local image_labels_removed = normalized_text:gsub('!%[([^%]]-)%]%([^%)]-%)', '%1')
  local link_destinations_removed = image_labels_removed:gsub('%[([^%]]-)%]%([^%)]-%)', '%1')
  local parsed_characters = {}
  local next_byte = 1
  while next_byte <= #link_destinations_removed do
    local open_byte, close_byte, code_text = link_destinations_removed:find(
      '`([^`]*)`',
      next_byte
    )
    if not open_byte then
      local plain_tail = link_destinations_removed:sub(next_byte):gsub('\\|', '|')
      append_display_characters(parsed_characters, plain_tail, false)
      break
    end
    local plain_text = link_destinations_removed
      :sub(next_byte, open_byte - 1)
      :gsub('\\|', '|')
    append_display_characters(parsed_characters, plain_text, false)
    append_display_characters(parsed_characters, code_text:gsub('\\|', '|'), true)
    next_byte = close_byte + 1
  end

  local display_characters = {}
  local pending_space
  for _, parsed_character in ipairs(parsed_characters) do
    if parsed_character.text:match('%s') then
      pending_space = pending_space or {
        is_code = parsed_character.is_code,
        text = ' ',
      }
    else
      if pending_space and #display_characters > 0 then
        display_characters[#display_characters + 1] = pending_space
      end
      display_characters[#display_characters + 1] = parsed_character
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

---@param cursor_row integer
---@param start_row integer
---@param end_row integer
---@param label_row? integer
---@return boolean
function M.uses_row_layout(cursor_row, start_row, end_row, label_row)
  local cursor_in_table = cursor_row >= start_row and cursor_row < end_row
  local cursor_on_label = label_row ~= nil and cursor_row == label_row
  return cursor_in_table or cursor_on_label
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
  for _, cell_node in ipairs(cell_nodes) do
    cell_texts[#cell_texts + 1] = vim.treesitter.get_node_text(cell_node, buffer)
  end
  return cell_texts
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
  local header_cells = row_cells(buffer, header_node)
  if #header_cells == 0 then
    return nil
  end
  local header_row = select(1, header_node:range())
  local rows = {
    { cells = header_cells, role = 'header', source_row = header_row },
  }
  for _, data_node in ipairs(data_nodes) do
    local data_cells = row_cells(buffer, data_node)
    if #data_cells == #header_cells then
      rows[#rows + 1] = {
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
  return padded
end

local function row_lines(row, column_widths, gap_width, alignments)
  local wrapped_cells = {}
  local line_count = 1
  for column_index, cell_text in ipairs(row.cells) do
    local cell_lines = M.wrap_cell_chunks(
      cell_text,
      column_widths[column_index],
      table_highlights[row.role]
    )
    wrapped_cells[column_index] = cell_lines
    line_count = math.max(line_count, #cell_lines)
  end

  local rendered_lines = {}
  for line_index = 1, line_count do
    local line_chunks = {}
    for column_index = 1, #column_widths do
      local cell_line = wrapped_cells[column_index][line_index] or {}
      vim.list_extend(line_chunks, padded_chunks(
        cell_line,
        column_widths[column_index],
        alignments[column_index],
        table_highlights[row.role]
      ))
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

local function table_groups(window, parsed_table)
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
  for row_index, row in ipairs(parsed_table.rows) do
    local row_alignments = row_index == 1 and header_alignments or parsed_table.alignments
    groups[#groups + 1] = {
      lines = vim.tbl_map(function(rendered_line)
        return content_line(indentation, rendered_line)
      end, row_lines(row, column_widths, gap_width, row_alignments)),
      source_row = row.source_row,
    }
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
  return groups
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

local function append_group_lines(target_lines, groups, first_group, last_group)
  for group_index = first_group, last_group do
    local group = groups[group_index]
    if group then
      vim.list_extend(target_lines, group.lines)
    end
  end
end

local function empty_rendered_line(rendered_line)
  local empty_chunks = {}
  for chunk_index, chunk in ipairs(rendered_line) do
    local empty_highlight = chunk_index == 1 and 'Normal' or table_highlights.cell
    empty_chunks[#empty_chunks + 1] = {
      string.rep(' ', display_width(chunk[1])),
      empty_highlight,
    }
  end
  return empty_chunks
end

local function conceal_line(staged_extmarks, row)
  stage_extmark(staged_extmarks, row, {
    conceal_lines = '',
    end_col = 0,
    end_row = row + 1,
    priority = 120,
  })
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

local function render_row_local(buffer, staged_extmarks, parsed_table, groups, active_row)
  for _, display in ipairs(source_displays(groups)) do
    local row_key = ('table:%d:row:%d'):format(
      parsed_table.start_row,
      display.source_row
    )
    local virtual_lines = {}
    if display.source_row == active_row then
      stage_extmark(staged_extmarks, display.source_row, {
        priority = 121,
      }, row_key .. ':overlay')
      for line_index = 2, #display.lines do
        virtual_lines[#virtual_lines + 1] = empty_rendered_line(
          display.lines[line_index]
        )
      end
    else
      local source_line = vim.api.nvim_buf_get_lines(
        buffer,
        display.source_row,
        display.source_row + 1,
        false
      )[1] or ''
      stage_extmark(staged_extmarks, display.source_row, {
        conceal = '',
        end_col = #source_line,
        priority = 121,
        virt_text = line_text_chunks(display.lines[1]),
        virt_text_pos = 'overlay',
      }, row_key .. ':overlay')
      for line_index = 2, #display.lines do
        virtual_lines[#virtual_lines + 1] = display.lines[line_index]
      end
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
end

local function render_complete_table(buffer, staged_extmarks, parsed_table, groups)
  local rendered_lines = {}
  append_group_lines(rendered_lines, groups, 2, #groups)
  if parsed_table.start_row > 0 then
    for source_row = parsed_table.start_row, parsed_table.end_row - 1 do
      conceal_line(staged_extmarks, source_row)
    end
    stage_extmark(staged_extmarks, parsed_table.start_row - 1, {
      priority = 120,
      virt_lines = rendered_lines,
    })
    return
  end

  local source_header = vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or ''
  local header_line = {}
  for chunk_index = 2, #rendered_lines[1] do
    header_line[#header_line + 1] = rendered_lines[1][chunk_index]
  end
  stage_extmark(staged_extmarks, 0, {
    conceal = '',
    end_col = #source_header,
    priority = 121,
    virt_text = header_line,
    virt_text_pos = 'overlay',
  })
  for source_row = 1, parsed_table.end_row - 1 do
    conceal_line(staged_extmarks, source_row)
  end
  local remaining_lines = {}
  for line_index = 2, #rendered_lines do
    remaining_lines[#remaining_lines + 1] = rendered_lines[line_index]
  end
  if #remaining_lines > 0 then
    stage_extmark(staged_extmarks, 0, {
      priority = 120,
      virt_lines = remaining_lines,
    })
  end
end

local function apply_extmarks(buffer, staged_extmarks)
  local current_extmark_ids = extmark_ids_by_buffer[buffer] or {}
  local current_extmark_specs = extmark_specs_by_buffer[buffer] or {}
  local next_extmark_ids = {}
  local next_extmark_specs = {}
  for _, staged_extmark in ipairs(staged_extmarks) do
    local current_extmark_id = current_extmark_ids[staged_extmark.key]
    local current_extmark_spec = current_extmark_specs[staged_extmark.key]
    local unchanged = current_extmark_id ~= nil
      and vim.deep_equal(current_extmark_spec, staged_extmark)
    if unchanged then
      next_extmark_ids[staged_extmark.key] = current_extmark_id
    else
      local resolved_options = current_extmark_id
          and vim.tbl_extend('force', {}, staged_extmark.options, {
            id = current_extmark_id,
          })
        or staged_extmark.options
      next_extmark_ids[staged_extmark.key] = vim.api.nvim_buf_set_extmark(
        buffer,
        table_namespace,
        staged_extmark.row,
        0,
        resolved_options
      )
    end
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

---@param context render.md.handler.Context
---@return render.md.Mark[]
function M.parse(context)
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
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = context.buf,
    once = true,
    callback = function()
      extmark_ids_by_buffer[context.buf] = nil
      extmark_specs_by_buffer[context.buf] = nil
      tables_by_buffer[context.buf] = nil
    end,
  })
end

function M.clear(context)
  if vim.api.nvim_buf_is_valid(context.buf) then
    vim.api.nvim_buf_clear_namespace(context.buf, table_namespace, 0, -1)
  end
  extmark_ids_by_buffer[context.buf] = nil
  extmark_specs_by_buffer[context.buf] = nil
end

function M.render(context)
  local buffer = context.buf
  local window = context.win
  if not vim.api.nvim_buf_is_valid(buffer)
      or not vim.api.nvim_win_is_valid(window)
      or vim.api.nvim_win_get_buf(window) ~= buffer then
    return
  end
  local staged_extmarks = {}
  local cursor_row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local parsed_tables = tables_by_buffer[buffer] or {}
  local interactive_tables = {}
  local cursor_near_table = false
  for table_index, parsed_table in ipairs(parsed_tables) do
    local label_row = table_label_row(buffer, parsed_table)
    interactive_tables[table_index] = M.uses_row_layout(
      cursor_row,
      parsed_table.start_row,
      parsed_table.end_row,
      label_row
    )
    cursor_near_table = cursor_near_table or interactive_tables[table_index]
  end
  local table_wrap_enabled = not cursor_near_table or M.table_editing.wrap
  vim.wo[window].wrap = table_wrap_enabled
  for table_index, parsed_table in ipairs(parsed_tables) do
    local groups = table_groups(window, parsed_table)
    render_table_label(buffer, staged_extmarks, parsed_table, groups)
    local cursor_in_table = cursor_row >= parsed_table.start_row
      and cursor_row < parsed_table.end_row
    if interactive_tables[table_index] then
      local active_row = cursor_in_table and cursor_row or nil
      render_row_local(buffer, staged_extmarks, parsed_table, groups, active_row)
    else
      render_complete_table(buffer, staged_extmarks, parsed_table, groups)
    end
  end
  apply_extmarks(buffer, staged_extmarks)
end

M.handler = {
  extends = true,
  parse = M.parse,
}

return M
