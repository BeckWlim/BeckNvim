local M = {}

local namespace = vim.api.nvim_create_namespace('markdown_features')
local attached_buffers = {}
local extmark_ids_by_buffer = {}
local extmark_specs_by_buffer = {}
local cursor_states_by_window = {}
local cursor_listener_installed = false
local cursor_namespace = vim.api.nvim_create_namespace('markdown_feature_cursor_keys')
local hidden_cursor
local pending_render_requests = {}
local scroll_directions = {
  ['<ScrollWheelDown>'] = 'j',
  ['<ScrollWheelUp>'] = 'k',
}

local function current_window(window)
  if not window or window == 0 then
    return vim.api.nvim_get_current_win()
  end
  return window
end

local function restore_native_cursor(feature, buffer, window)
  local resolved_window = window and current_window(window) or nil
  if not hidden_cursor
      or (feature and hidden_cursor.feature ~= feature)
      or (buffer and hidden_cursor.buffer ~= buffer)
      or (resolved_window and hidden_cursor.window ~= resolved_window) then
    return
  end
  if vim.o.guicursor == hidden_cursor.value then
    vim.o.guicursor = hidden_cursor.original
  end
  hidden_cursor = nil
end

local function hide_native_cursor(feature, buffer, window, highlight)
  local resolved_window = current_window(window)
  if hidden_cursor
      and hidden_cursor.feature == feature
      and hidden_cursor.buffer == buffer
      and hidden_cursor.window == resolved_window
      and hidden_cursor.highlight == highlight then
    return
  end
  restore_native_cursor()
  local original = vim.o.guicursor
  local separator = original == '' and '' or ','
  local value = original .. separator .. 'n-v:block-' .. highlight
  vim.o.guicursor = value
  hidden_cursor = {
    buffer = buffer,
    feature = feature,
    highlight = highlight,
    original = original,
    value = value,
    window = resolved_window,
  }
end

local function interactive_mode(mode)
  return mode:sub(1, 1) == 'n'
    or mode == 'v'
    or mode == 'V'
    or mode == '\22'
end

local function layered_highlight(base, highlight)
  local highlights = type(base) == 'table' and vim.deepcopy(base) or { base }
  highlights[#highlights + 1] = highlight
  return highlights
end

local function append_chunk(chunks, text, highlight)
  local previous = chunks[#chunks]
  if previous and vim.deep_equal(previous[2], highlight) then
    previous[1] = previous[1] .. text
  else
    chunks[#chunks + 1] = { text, highlight }
  end
end

function M.chunks_width(chunks)
  local width = 0
  for _, chunk in ipairs(chunks) do
    width = width + vim.fn.strdisplaywidth(chunk[1])
  end
  return width
end

function M.pad_overlay_chunks(chunks, source_text, padding_highlight)
  local padded = vim.deepcopy(chunks)
  local padding_width = math.max(
    vim.fn.strdisplaywidth(source_text) - M.chunks_width(padded),
    0
  )
  if padding_width > 0 then
    padded[#padded + 1] = {
      string.rep(' ', padding_width),
      padding_highlight,
    }
  end
  return padded
end

function M.highlighted_chunks(chunks, highlight)
  return vim.tbl_map(function(chunk)
    return { chunk[1], layered_highlight(chunk[2], highlight) }
  end, chunks)
end

function M.highlighted_range_chunks(chunks, first_column, last_column, highlight)
  local rendered = {}
  local display_column = 0
  for _, chunk in ipairs(chunks) do
    local character_count = vim.fn.strchars(chunk[1])
    for character_index = 0, character_count - 1 do
      local character = vim.fn.strcharpart(chunk[1], character_index, 1)
      local character_width = vim.fn.strdisplaywidth(character)
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

function M.cursor_proxy_chunks(chunks, cursor_column, cursor_highlight)
  local rendered = {}
  local display_column = 0
  local cursor_added = false
  for _, chunk in ipairs(chunks) do
    local character_count = vim.fn.strchars(chunk[1])
    for character_index = 0, character_count - 1 do
      local character = vim.fn.strcharpart(chunk[1], character_index, 1)
      local character_width = vim.fn.strdisplaywidth(character)
      local highlight = chunk[2]
      if not cursor_added
          and cursor_column >= display_column
          and cursor_column < display_column + character_width then
        highlight = layered_highlight(
          highlight,
          cursor_highlight or 'Cursor'
        )
        cursor_added = true
      end
      append_chunk(rendered, character, highlight)
      display_column = display_column + character_width
    end
  end
  return rendered
end

local function set_extmark(buffer, current_id, current_spec, staged_extmark)
  if current_id and vim.deep_equal(current_spec, staged_extmark) then
    return current_id
  end
  local options = current_id
      and vim.tbl_extend('force', {}, staged_extmark.options, {
        id = current_id,
      })
    or staged_extmark.options
  return vim.api.nvim_buf_set_extmark(
    buffer,
    namespace,
    staged_extmark.row,
    0,
    options
  )
end

function M.apply(feature, buffer, staged_extmarks)
  local buffer_ids = extmark_ids_by_buffer[buffer] or {}
  local buffer_specs = extmark_specs_by_buffer[buffer] or {}
  local current_ids = buffer_ids[feature] or {}
  local current_specs = buffer_specs[feature] or {}
  local next_ids = {}
  local next_specs = {}
  for _, staged_extmark in ipairs(staged_extmarks) do
    local key = staged_extmark.key
    next_ids[key] = set_extmark(
      buffer,
      current_ids[key],
      current_specs[key],
      staged_extmark
    )
    next_specs[key] = staged_extmark
  end
  for key, extmark_id in pairs(current_ids) do
    if not next_ids[key] then
      vim.api.nvim_buf_del_extmark(buffer, namespace, extmark_id)
    end
  end
  buffer_ids[feature] = next_ids
  buffer_specs[feature] = next_specs
  extmark_ids_by_buffer[buffer] = buffer_ids
  extmark_specs_by_buffer[buffer] = buffer_specs
end

function M.update(feature, buffer, staged_extmarks)
  local buffer_ids = extmark_ids_by_buffer[buffer] or {}
  local buffer_specs = extmark_specs_by_buffer[buffer] or {}
  local ids = buffer_ids[feature] or {}
  local specs = buffer_specs[feature] or {}
  for _, staged_extmark in ipairs(staged_extmarks) do
    local key = staged_extmark.key
    ids[key] = set_extmark(buffer, ids[key], specs[key], staged_extmark)
    specs[key] = staged_extmark
  end
  buffer_ids[feature] = ids
  buffer_specs[feature] = specs
  extmark_ids_by_buffer[buffer] = buffer_ids
  extmark_specs_by_buffer[buffer] = buffer_specs
end

function M.clear(feature, buffer)
  local buffer_ids = extmark_ids_by_buffer[buffer]
  if not buffer_ids then
    return
  end
  for _, extmark_id in pairs(buffer_ids[feature] or {}) do
    pcall(vim.api.nvim_buf_del_extmark, buffer, namespace, extmark_id)
  end
  buffer_ids[feature] = nil
  local buffer_specs = extmark_specs_by_buffer[buffer]
  if buffer_specs then
    buffer_specs[feature] = nil
  end
end

function M.parked_interaction(feature, buffer, window)
  window = current_window(window)
  local cursor_state = cursor_states_by_window[window]
  if cursor_state
      and cursor_state.parked
      and cursor_state.feature == feature
      and cursor_state.buffer == buffer then
    return cursor_state.interaction
  end
  return nil
end

function M.park_cursor(feature, buffer, window, interaction, cursor_highlight)
  window = current_window(window)
  if vim.api.nvim_get_current_win() ~= window or not interaction then
    M.release_cursor(feature, buffer, window, false)
    return false
  end
  cursor_states_by_window[window] = {
    buffer = buffer,
    feature = feature,
    interaction = interaction,
    parked = true,
  }
  local position = vim.api.nvim_win_get_cursor(window)
  if position[2] ~= 0 then
    vim.api.nvim_win_set_cursor(window, { position[1], 0 })
  end
  if cursor_highlight then
    hide_native_cursor(feature, buffer, window, cursor_highlight)
  end
  return true
end

function M.release_cursor(feature, buffer, window, restore_position)
  window = current_window(window)
  restore_native_cursor(feature, buffer, window)
  local cursor_state = cursor_states_by_window[window]
  if not cursor_state
      or cursor_state.feature ~= feature
      or (buffer and cursor_state.buffer ~= buffer) then
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

local function vertical_view(window)
  return vim.api.nvim_win_call(window, function()
    local view = vim.fn.winsaveview()
    return { topfill = view.topfill, topline = view.topline }
  end)
end

local function recover_stalled_scroll(window, buffer, feature, motion, cursor, view)
  vim.defer_fn(function()
    if not vim.api.nvim_win_is_valid(window)
        or not vim.api.nvim_buf_is_valid(buffer)
        or vim.api.nvim_win_get_buf(window) ~= buffer then
      return
    end
    local current_cursor = vim.api.nvim_win_get_cursor(window)
    local current_view = vertical_view(window)
    if current_cursor[1] ~= cursor[1]
        or current_view.topline ~= view.topline
        or current_view.topfill ~= view.topfill then
      return
    end
    if feature then
      M.release_cursor(feature, buffer, window, true)
    end
    vim.api.nvim_win_call(window, function()
      vim.cmd.normal({ args = { motion }, bang = true })
    end)
  end, 10)
end

local function restore_cursor_for_input(key)
  local window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode
  if not interactive_mode(mode)
      or not vim.api.nvim_win_is_valid(window)
      or not attached_buffers[buffer] then
    return
  end
  local cursor_state = cursor_states_by_window[window]
  local feature
  if cursor_state
      and cursor_state.parked
      and cursor_state.buffer == buffer then
    cursor_state.parked = false
    feature = cursor_state.feature
    local cursor = cursor_state.interaction.cursor
    if not pcall(
      vim.api.nvim_win_set_cursor,
      window,
      { cursor.row + 1, cursor.column }
    ) then
      cursor_states_by_window[window] = nil
      return
    end
  end
  local scroll_motion = scroll_directions[vim.fn.keytrans(key)]
  if scroll_motion then
    recover_stalled_scroll(
      window,
      buffer,
      feature,
      scroll_motion,
      vim.api.nvim_win_get_cursor(window),
      vertical_view(window)
    )
  end
end

function M.setup_cursor_listener(buffer)
  attached_buffers[buffer] = true
  if cursor_listener_installed then
    return
  end
  vim.on_key(restore_cursor_for_input, cursor_namespace)
  cursor_listener_installed = true
end

function M.request_render(buffer, event)
  local pending = pending_render_requests[buffer]
  if pending then
    pending.event = event or pending.event
    return
  end
  pending = { event = event or 'MarkdownFeature' }
  pending_render_requests[buffer] = pending
  vim.schedule(function()
    if pending_render_requests[buffer] ~= pending then
      return
    end
    pending_render_requests[buffer] = nil
    if not vim.api.nvim_buf_is_valid(buffer) then
      return
    end
    pcall(function()
      require('render-markdown').render({
        buf = buffer,
        event = pending.event,
      })
    end)
  end)
end

function M.dispatch(features, method, context)
  for _, feature in ipairs(features) do
    if feature[method] then
      feature[method](context)
    end
  end
end

function M.parse(features, context)
  local marks = {}
  for _, feature in ipairs(features) do
    if feature.parse then
      vim.list_extend(marks, feature.parse(context) or {})
    end
  end
  return marks
end

function M.forget_buffer(buffer)
  attached_buffers[buffer] = nil
  restore_native_cursor(nil, buffer)
  extmark_ids_by_buffer[buffer] = nil
  extmark_specs_by_buffer[buffer] = nil
  pending_render_requests[buffer] = nil
  for window, cursor_state in pairs(cursor_states_by_window) do
    if cursor_state.buffer == buffer then
      cursor_states_by_window[window] = nil
    end
  end
end

return M
