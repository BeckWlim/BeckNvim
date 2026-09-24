local M = {}
local option_resolvers_by_filetype = {}
local layouts_by_tabpage = {}
local layout_generation = 0
local resize_pending = false
local resized_tabs = {}
local panel_axes = {}
local panel_ratios_by_tabpage = {}
local tracked_panels = {}
local panel_preferences = {}
local preference_directory

local function editor_extent(axis)
  return axis == 'width' and vim.o.columns or vim.o.lines - vim.o.cmdheight
end

local function valid_ratio(ratio)
  return type(ratio) == 'number' and ratio > 0 and ratio < 1
end

function M.prepare_panel(filetype, axis)
  assert(axis == 'width' or axis == 'height', 'panel axis must be width or height')
  local key = filetype .. '-' .. axis
  if panel_preferences[key] then return panel_preferences[key] end
  local store = require('config.state').open('window-' .. key, { directory = preference_directory })
  local preference = { store = store, revision = 0 }
  panel_preferences[key] = preference
  local generation = layout_generation
  preference.cancel = store:read(function(document, failure)
    if generation ~= layout_generation or preference.revision ~= 0 then return end
    if failure then
      vim.notify('Window preference: ' .. failure, vim.log.levels.WARN)
      return
    end
    if document and valid_ratio(document.ratio) then
      preference.ratio = document.ratio
      -- A startup command can open the tree before its async read completes.
      -- Only untouched newly opened panels may receive that late preference.
      for winid, initial_ratio in pairs(tracked_panels) do
        if vim.api.nvim_win_is_valid(winid)
            and vim.bo[vim.api.nvim_win_get_buf(winid)].filetype == filetype then
          local size = axis == 'width' and vim.api.nvim_win_get_width(winid)
            or vim.api.nvim_win_get_height(winid)
          local extent = editor_extent(axis)
          if math.abs(size / extent - initial_ratio) < 0.000001 then
            local target_size = math.max(1, math.floor(document.ratio * extent + 0.5))
            local resize = axis == 'width' and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height
            pcall(resize, winid, target_size)
          end
        end
      end
    end
  end)
  return preference
end

-- Panels opt in through their native size callback; memory belongs to the tab,
-- not to the temporary window ID allocated on each reopen.
function M.panel_size(filetype, axis, default_size)
  assert(axis == 'width' or axis == 'height', 'panel axis must be width or height')
  panel_axes[filetype] = axis
  local preference = M.prepare_panel(filetype, axis)
  local ratios = panel_ratios_by_tabpage[vim.api.nvim_get_current_tabpage()]
  local ratio = (ratios and ratios[filetype]) or preference.ratio
  return ratio and math.max(1, math.floor(ratio * editor_extent(axis) + 0.5)) or default_size
end

-- Call after the plugin's native open/resize has completed; transient new
-- split dimensions must never replace a remembered panel preference.
function M.track_panel(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
    local axis = panel_axes[filetype]
    local size = axis == 'height' and vim.api.nvim_win_get_height(winid) or vim.api.nvim_win_get_width(winid)
    tracked_panels[winid] = size / editor_extent(axis)
  end
end

local function remember_panels(tabpage)
  local ratios = panel_ratios_by_tabpage[tabpage] or {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
    local axis = panel_axes[filetype]
    if axis and tracked_panels[winid] and vim.api.nvim_win_get_config(winid).relative == '' then
      local size = axis == 'width' and vim.api.nvim_win_get_width(winid)
        or vim.api.nvim_win_get_height(winid)
      ratios[filetype] = size / editor_extent(axis)
      local ratio = ratios[filetype]
      local preference = M.prepare_panel(filetype, axis)
      if valid_ratio(ratio) and math.abs(ratio - tracked_panels[winid]) > 0.000001 then
        preference.revision = preference.revision + 1
        preference.ratio = ratio
        tracked_panels[winid] = ratio
        local saved, failure = preference.store:write({ ratio = ratio })
        if not saved then vim.notify('Window preference: ' .. failure, vim.log.levels.WARN) end
      end
    end
  end
  panel_ratios_by_tabpage[tabpage] = ratios
end

---@class WindowProportions
---@field width number
---@field height number
---@field children? WindowProportions[]

-- winlayout excludes floats. Measure each branch so nested rows and columns
-- retain their own proportions rather than competing for editor-wide sizes.
---@return WindowProportions
local function measure(layout)
  if layout[1] == 'leaf' then
    return {
      width = vim.api.nvim_win_get_width(layout[2]),
      height = vim.api.nvim_win_get_height(layout[2]),
    }
  end
  ---@type WindowProportions
  local node = { children = {}, width = 0, height = 0 }
  for _, child_layout in ipairs(layout[2]) do
    local child = measure(child_layout)
    node.children[#node.children + 1] = child
    if layout[1] == 'row' then
      node.width = node.width + child.width
      node.height = math.max(node.height, child.height)
    else
      node.height = node.height + child.height
      node.width = math.max(node.width, child.width)
    end
  end
  if layout[1] == 'row' then
    node.width = node.width + #node.children - 1
  else
    node.height = node.height + #node.children - 1
  end
  return node
end

local function remember(tabpage)
  local layout = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tabpage))
  layouts_by_tabpage[tabpage] = { layout = layout, sizes = measure(layout) }
end

local function first_window(layout)
  if layout[1] == 'leaf' then
    return layout[2]
  end
  return first_window(layout[2][1])
end

---@param sizes WindowProportions
local function restore(layout, sizes)
  if layout[1] == 'leaf' then
    return
  end
  local axis = layout[1] == 'row' and 'width' or 'height'
  local current_sizes = measure(layout)
  local available = current_sizes[axis] - #sizes.children + 1
  local previous_available = sizes[axis] - #sizes.children + 1
  local allocated = 0
  local previous_allocated = 0
  for index, child_layout in ipairs(layout[2]) do
    local child_size = sizes.children[index]
    previous_allocated = previous_allocated + child_size[axis]
    local boundary = math.floor(available * previous_allocated / previous_available + 0.5)
    if index < #sizes.children then
      local target = boundary - allocated
      local child_current = measure(child_layout)
      local winid = first_window(child_layout)
      -- A branch may contain splits on this axis: adjust its representative
      -- leaf by the branch delta, then restore its internal ratios below.
      if axis == 'width' then
        pcall(vim.api.nvim_win_set_width, winid,
          math.max(1, vim.api.nvim_win_get_width(winid) + target - child_current.width))
      else
        pcall(vim.api.nvim_win_set_height, winid,
          math.max(1, vim.api.nvim_win_get_height(winid) + target - child_current.height))
      end
    end
    allocated = boundary
  end
  for index, child_layout in ipairs(layout[2]) do
    restore(child_layout, sizes.children[index])
  end
end

local function restore_tab(tabpage)
  local saved = layouts_by_tabpage[tabpage]
  local layout = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tabpage))
  if saved and vim.deep_equal(saved.layout, layout) then
    restore(layout, saved.sizes)
  end
  resized_tabs[tabpage] = nil
  remember(tabpage)
  remember_panels(tabpage)
end

function M.setup(options)
  local settings = options or {}
  preference_directory = settings.state_directory
  for _, preference in pairs(panel_preferences) do
    if preference.cancel then preference.cancel() end
  end
  panel_preferences = {}
  layout_generation = layout_generation + 1
  local generation = layout_generation
  layouts_by_tabpage = {}
  panel_ratios_by_tabpage = {}
  tracked_panels = {}
  resize_pending = false
  resized_tabs = {}
  -- New splits divide the active pane without equalizing unrelated panes.
  vim.o.equalalways = false
  local group = vim.api.nvim_create_augroup('workspace_window_proportions', { clear = true })
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    remember(tabpage)
  end
  vim.api.nvim_create_autocmd({ 'WinResized', 'WinLeave', 'TabLeave' }, {
    group = group,
    callback = function(event)
      local tabpage = vim.api.nvim_get_current_tabpage()
      if not resize_pending and not resized_tabs[tabpage] then
        remember(tabpage)
        if event.event == 'WinResized' or event.event == 'TabLeave' then
          remember_panels(tabpage)
        end
      end
    end,
    desc = 'Remember manually adjusted split proportions per tab',
  })
  vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'TabEnter' }, {
    group = group,
    callback = function(event)
      local tabpage = vim.api.nvim_get_current_tabpage()
      if event.event == 'WinClosed' and not resize_pending and not resized_tabs[tabpage] then
        remember_panels(tabpage)
      end
      if event.event == 'WinClosed' then
        tracked_panels[tonumber(event.match)] = nil
      end
      vim.schedule(function()
        if generation == layout_generation and not resize_pending
            and vim.api.nvim_tabpage_is_valid(tabpage) then
          if resized_tabs[tabpage] and tabpage == vim.api.nvim_get_current_tabpage() then
            restore_tab(tabpage)
          elseif not resized_tabs[tabpage] then
            remember(tabpage)
            remember_panels(tabpage)
          end
        end
      end)
    end,
    desc = 'Adopt changed split layouts after window transitions settle',
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      if resize_pending then
        return
      end
      resize_pending = true
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        resized_tabs[tabpage] = true
      end
      vim.schedule(function()
        if generation ~= layout_generation then
          return
        end
        -- Neovim resizes hidden tabs only when they become current.
        restore_tab(vim.api.nvim_get_current_tabpage())
        resize_pending = false
      end)
    end,
    desc = 'Scale existing split proportions with the editor size',
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function()
      for tabpage in pairs(layouts_by_tabpage) do
        if not vim.api.nvim_tabpage_is_valid(tabpage) then
          layouts_by_tabpage[tabpage] = nil
          resized_tabs[tabpage] = nil
          panel_ratios_by_tabpage[tabpage] = nil
        end
      end
    end,
  })
end

function M.register(filetype, option_resolver)
  if type(filetype) ~= 'string' or filetype == '' then
    error('window-state filetype must be a non-empty string')
  end
  if type(option_resolver) ~= 'function' then
    error('window-state option resolver must be a function')
  end
  option_resolvers_by_filetype[filetype] = option_resolver
end

function M.resolve(winid, option_names)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  local window_buffer = vim.api.nvim_win_get_buf(winid)
  local window_filetype = vim.bo[window_buffer].filetype
  local option_resolver = option_resolvers_by_filetype[window_filetype]
  local registered_options = option_resolver and option_resolver(winid) or nil
  local resolved_options = {}
  for _, option_name in ipairs(option_names) do
    local registered_value = registered_options and registered_options[option_name]
    if registered_value ~= nil then
      resolved_options[option_name] = registered_value
    else
      resolved_options[option_name] = vim.wo[winid][option_name]
    end
  end
  return resolved_options
end

return M
