local M = {}

---@class SourceSymbolSelectionState
---@field buffer integer
---@field changedtick integer
---@field node TSNode

---@type table<integer, SourceSymbolSelectionState>
local states_by_window = {}

---@param line string
---@return integer
local function final_character_column(line)
  if line == '' then
    return 0
  end
  local character_count = vim.str_utfindex(line, 'utf-32')
  return vim.str_byteindex(line, 'utf-32', character_count - 1, false)
end

---@param buffer integer
---@param node TSNode
---@return integer, integer, integer, integer
local function visual_range(buffer, node)
  local start_row, start_column, exclusive_end_row, exclusive_end_column = node:range()
  if exclusive_end_column > 0 then
    local end_line = vim.api.nvim_buf_get_lines(
      buffer,
      exclusive_end_row,
      exclusive_end_row + 1,
      false
    )[1] or ''
    local text_through_final_character = end_line:sub(1, exclusive_end_column)
    return start_row,
      start_column,
      exclusive_end_row,
      final_character_column(text_through_final_character)
  end
  if exclusive_end_row <= start_row then
    return start_row, start_column, start_row, start_column
  end

  local final_row = exclusive_end_row - 1
  local final_line = vim.api.nvim_buf_get_lines(buffer, final_row, final_row + 1, false)[1] or ''
  return start_row, start_column, final_row, final_character_column(final_line)
end

---@param first_row integer
---@param first_column integer
---@param second_row integer
---@param second_column integer
---@return boolean
local function position_precedes(first_row, first_column, second_row, second_column)
  return first_row < second_row
    or (first_row == second_row and first_column <= second_column)
end

---@return integer, integer, integer, integer
local function active_visual_range()
  local anchor_position = vim.fn.getpos('v')
  local cursor_position = vim.api.nvim_win_get_cursor(0)
  local anchor_row = anchor_position[2] - 1
  local anchor_column = anchor_position[3] - 1
  local cursor_row = cursor_position[1] - 1
  local cursor_column = cursor_position[2]

  if position_precedes(anchor_row, anchor_column, cursor_row, cursor_column) then
    return anchor_row, anchor_column, cursor_row, cursor_column
  end
  return cursor_row, cursor_column, anchor_row, anchor_column
end

---@param state SourceSymbolSelectionState
---@return boolean
local function state_matches_active_selection(state)
  local current_buffer = vim.api.nvim_get_current_buf()
  if state.buffer ~= current_buffer
      or state.changedtick ~= vim.api.nvim_buf_get_changedtick(current_buffer) then
    return false
  end

  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    return false
  end

  local selected_start_row, selected_start_column, selected_end_row, selected_end_column =
    active_visual_range()
  local node_start_row, node_start_column, node_end_row, node_end_column =
    visual_range(current_buffer, state.node)
  return selected_start_row == node_start_row
    and selected_start_column == node_start_column
    and selected_end_row == node_end_row
    and selected_end_column == node_end_column
end

---@return SourceSymbolSelectionState?
local function active_state()
  local current_window = vim.api.nvim_get_current_win()
  local selection_state = states_by_window[current_window]
  if selection_state and state_matches_active_selection(selection_state) then
    return selection_state
  end
  states_by_window[current_window] = nil
  return nil
end

---@return TSNode?
local function node_at_cursor()
  local current_buffer = vim.api.nvim_get_current_buf()
  local parser_succeeded = pcall(function()
    vim.treesitter.get_parser(current_buffer):parse()
  end)
  if not parser_succeeded then
    return nil
  end

  ---@type TSNode?
  local cursor_node = nil
  local node_succeeded = pcall(function()
    cursor_node = vim.treesitter.get_node({
      bufnr = current_buffer,
      ignore_injections = false,
    })
  end)
  if not node_succeeded then
    return nil
  end
  return cursor_node
end

---@param node TSNode
local function select_node(node)
  local current_buffer = vim.api.nvim_get_current_buf()
  local start_row, start_column, end_row, end_column = visual_range(current_buffer, node)
  vim.fn.setpos("'<", { 0, start_row + 1, start_column + 1, 0 })
  vim.fn.setpos("'>", { 0, end_row + 1, end_column + 1, 0 })
  vim.cmd('normal! gv')

  states_by_window[vim.api.nvim_get_current_win()] = {
    buffer = current_buffer,
    changedtick = vim.api.nvim_buf_get_changedtick(current_buffer),
    node = node,
  }
end

---@param node TSNode
---@return boolean
local function is_symbol(node)
  local node_type = node:type()
  return node_type == 'identifier' or vim.endswith(node_type, '_identifier')
end

local function start_selection()
  local cursor_node = node_at_cursor()
  if not cursor_node or not is_symbol(cursor_node) then
    vim.notify('No source symbol at the cursor', vim.log.levels.INFO)
    return
  end
  select_node(cursor_node)
end

---@param root_node TSNode
---@return TSNode?
local function first_symbol(root_node)
  if is_symbol(root_node) then
    return root_node
  end
  for child_node in root_node:iter_children() do
    if child_node:named() then
      local descendant_symbol = first_symbol(child_node)
      if descendant_symbol then
        return descendant_symbol
      end
    end
  end
  return nil
end

---@param root_node TSNode
---@return TSNode?
local function last_symbol(root_node)
  if is_symbol(root_node) then
    return root_node
  end
  for child_index = root_node:named_child_count() - 1, 0, -1 do
    local child_node = root_node:named_child(child_index)
    if child_node then
      local descendant_symbol = last_symbol(child_node)
      if descendant_symbol then
        return descendant_symbol
      end
    end
  end
  return nil
end

---@param symbol_node TSNode
---@param direction 'previous'|'next'
---@return TSNode?
local function adjacent_symbol(symbol_node, direction)
  local current_node = symbol_node
  while current_node do
    ---@type TSNode?
    local sibling_node = nil
    if direction == 'previous' then
      sibling_node = current_node:prev_named_sibling()
    else
      sibling_node = current_node:next_named_sibling()
    end
    while sibling_node do
      local descendant_symbol
      if direction == 'previous' then
        descendant_symbol = last_symbol(sibling_node)
      else
        descendant_symbol = first_symbol(sibling_node)
      end
      if descendant_symbol then
        return descendant_symbol
      end
      if direction == 'previous' then
        sibling_node = sibling_node:prev_named_sibling()
      else
        sibling_node = sibling_node:next_named_sibling()
      end
    end
    current_node = current_node:parent()
  end
  return nil
end

---@param direction 'previous'|'next'
local function select_adjacent(direction)
  local selection_state = active_state()
  if not selection_state then
    start_selection()
    return
  end

  local target_symbol = adjacent_symbol(selection_state.node, direction)
  if target_symbol then
    select_node(target_symbol)
  end
end

function M.select_previous()
  select_adjacent('previous')
end

function M.select_next()
  select_adjacent('next')
end

function M.setup()
  local selection_group = vim.api.nvim_create_augroup('config-syntax-selection', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = selection_group,
    callback = function(event)
      local closed_window = tonumber(event.match)
      if closed_window then
        states_by_window[closed_window] = nil
      end
    end,
  })
end

return M
