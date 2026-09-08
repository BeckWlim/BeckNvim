local M = {
  input_close_key = '<C-q>',
  input_close_hint = 'Ctrl-Q',
  normal_close_key = 'q',
}

local active_float_by_tabpage = {}
local focus_restore_pending_by_tabpage = {}

local function is_focusable_float(window)
  if not vim.api.nvim_win_is_valid(window) then
    return false
  end
  local config_ok, window_config = pcall(vim.api.nvim_win_get_config, window)
  return config_ok
    and window_config.relative ~= ''
    and window_config.focusable ~= false
end

local function forget_window(window)
  for tabpage, active_window in pairs(active_float_by_tabpage) do
    if active_window == window then
      active_float_by_tabpage[tabpage] = nil
      focus_restore_pending_by_tabpage[tabpage] = nil
    end
  end
end

local function restore_active_float()
  local entered_window = vim.api.nvim_get_current_win()
  local entered_tabpage = vim.api.nvim_win_get_tabpage(entered_window)
  if is_focusable_float(entered_window) then
    active_float_by_tabpage[entered_tabpage] = entered_window
    return
  end

  local active_window = active_float_by_tabpage[entered_tabpage]
  if not active_window or focus_restore_pending_by_tabpage[entered_tabpage] then
    return
  end
  focus_restore_pending_by_tabpage[entered_tabpage] = true

  vim.schedule(function()
    focus_restore_pending_by_tabpage[entered_tabpage] = nil
    if active_float_by_tabpage[entered_tabpage] ~= active_window
        or not vim.api.nvim_tabpage_is_valid(entered_tabpage)
        or vim.api.nvim_get_current_tabpage() ~= entered_tabpage then
      return
    end

    local current_window = vim.api.nvim_get_current_win()
    if is_focusable_float(current_window) then
      active_float_by_tabpage[entered_tabpage] = current_window
      return
    end
    if not is_focusable_float(active_window)
        or vim.api.nvim_win_get_tabpage(active_window) ~= entered_tabpage then
      active_float_by_tabpage[entered_tabpage] = nil
      return
    end
    vim.api.nvim_set_current_win(active_window)
  end)
end

function M.setup()
  for tabpage in pairs(active_float_by_tabpage) do
    active_float_by_tabpage[tabpage] = nil
    focus_restore_pending_by_tabpage[tabpage] = nil
  end

  local focus_group = vim.api.nvim_create_augroup('float_dialog_focus_lock', { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = focus_group,
    callback = restore_active_float,
    desc = 'Keep focus inside the active floating dialog',
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = focus_group,
    callback = function(event)
      local closed_window_text = event.match
      local closed_window = tonumber(closed_window_text)
      if closed_window then
        forget_window(closed_window)
      end
    end,
    desc = 'Release closed floating-dialog focus locks',
  })
  restore_active_float()
end

function M.bind_close(options)
  local close_callback = options.close
  local mapping_function = options.map
  local accepts_input = options.accepts_input == true

  if mapping_function then
    mapping_function('n', M.normal_close_key, close_callback)
    if accepts_input then
      mapping_function('i', M.input_close_key, close_callback)
    end
    return
  end

  local buffer_number = options.buffer
  local description = options.description or 'Close floating window'
  vim.keymap.set('n', M.normal_close_key, close_callback, {
    buffer = buffer_number,
    nowait = true,
    silent = true,
    desc = description,
  })
  if accepts_input then
    vim.keymap.set('i', M.input_close_key, close_callback, {
      buffer = buffer_number,
      nowait = true,
      silent = true,
      desc = description,
    })
  end
end

return M
