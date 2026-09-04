local repository = require('config.git.repository')
local footer_loader = require('config.git.footer_loader')
local panel = require('config.git.panel')
local lifecycle = require('config.git.lifecycle')
local events = require('config.git.events')

local M = {}
local footer_annotation_namespace = vim.api.nvim_create_namespace('config-git-history-footer')
local footer_header_namespace = vim.api.nvim_create_namespace('config-git-history-header')
local state = {
  closing = false,
  configured = false,
  pending_view_closes = 0,
  pending_history_request_cancel = nil,
  repository_root = nil,
  root_view = nil,
  settled_actions = {},
}
local decorate_history_footer
local highlight_history_entry
local clear_history_render_winbars
local history_entry_for_file
local finalize_history_metadata_focus
local schedule_footer_detail_render
local request_footer_decoration

local function escaped_winbar_text(value)
  return value:gsub('%%', '%%%%')
end

local function ensure_loaded()
  if not package.loaded.diffview then
    require('lazy').load({ plugins = { 'diffview.nvim' } })
  end
end

function M.log_anchor(message, level)
  ensure_loaded()
  local diffview_global = rawget(_G, 'DiffviewGlobal')
  local logger = diffview_global and diffview_global.logger
  local log_method = logger and logger[level or 'info']
  if type(log_method) == 'function' then
    pcall(log_method, logger, '[Git anchor] ' .. message)
  end
end

local function active_view()
  local diffview_lib = package.loaded['diffview.lib']
  return diffview_lib and diffview_lib.get_current_view()
end

local function cancel_pending_history_request()
  local cancel_request = state.pending_history_request_cancel
  state.pending_history_request_cancel = nil
  if type(cancel_request) == 'function' then
    cancel_request()
  end
end

local function close_mapping()
  return {
    'n',
    panel.close_key,
    M.handle_ctrl_q,
    { desc = 'Close current Git panel layer' },
  }
end

local function history_selection_is_rendering(view)
  if not view then
    return false
  end
  local history_panel = view and view.panel
  local current_item = history_panel and history_panel.cur_item
  local selected_file = current_item and current_item[2]
  local current_entry = view and view.cur_entry
  return selected_file and (not current_entry or not current_entry.opened) or false
end

local function scoped_entry_is_still_selected(view, entry)
  local history_panel = view and view.panel
  if not history_panel
      or type(history_panel.is_focused) ~= 'function'
      or not history_panel:is_focused()
      or type(history_panel.get_item_at_cursor) ~= 'function' then
    return false
  end
  return history_panel:get_item_at_cursor() == entry
end

local function select_history_entry()
  local view = active_view()
  local history_panel = view and view.panel
  local cursor_item
  if history_panel
      and type(history_panel.is_focused) == 'function'
      and history_panel:is_focused()
      and type(history_panel.get_item_at_cursor) == 'function' then
    cursor_item = history_panel:get_item_at_cursor()
  end
  local cursor_entry = cursor_item
      and cursor_item.files
      and cursor_item
    or history_entry_for_file(view, cursor_item)
  if cursor_entry and cursor_entry.git_details_loaded == false then
    footer_loader.ensure_entry(view, cursor_entry, function(details_loaded)
      if details_loaded
          and active_view() == view
          and scoped_entry_is_still_selected(view, cursor_entry) then
        select_history_entry()
      end
    end)
    return
  end
  local selected_file = cursor_item and not cursor_item.files and cursor_item or nil
  if view and selected_file then
    view.git_diff_opened = true
    -- Only rows opened through this explicit selection may render code panes.
    view.git_explicit_file_open = selected_file
  end
  require('diffview.actions').select_entry()
end

local function history_entry_mapping(key)
  return { 'n', key, select_history_entry, { desc = 'Open selected Git history entry' } }
end

history_entry_for_file = function(view, file)
  local history_panel = view and view.panel
  if not history_panel or not file then
    return
  end
  if type(history_panel.find_entry) == 'function' then
    local find_succeeded, found_entry = pcall(history_panel.find_entry, history_panel, file)
    if find_succeeded and found_entry then
      return found_entry
    end
  end
  for _, entry in ipairs(history_panel.entries or {}) do
    for _, entry_file in ipairs(entry.files or {}) do
      if entry_file == file then
        return entry
      end
    end
  end
  local current_item = history_panel.cur_item
  if current_item and current_item[2] == file then
    return current_item[1]
  end
end

local function history_render_identity(view, file)
  local entry = history_entry_for_file(view, file)
  local commit_hash = entry and entry.commit and entry.commit.hash
    or file and file.commit and file.commit.hash
  local file_path = file and (file.path or file.oldpath)
  return commit_hash, file_path, entry
end

local function clear_history_diff(view, selected_entry)
  if not view then
    return false
  end
  local history_panel = view.panel
  local current_layout = view.cur_layout
  local layout_is_valid = current_layout
      and (
        type(current_layout.is_valid) ~= 'function'
        or current_layout:is_valid()
      )
    or false
  if layout_is_valid and type(current_layout.detach_files) == 'function' then
    pcall(current_layout.detach_files, current_layout)
  end
  if layout_is_valid and type(current_layout.open_null) == 'function' then
    pcall(current_layout.open_null, current_layout)
  end
  if history_panel and type(history_panel.set_cur_item) == 'function' then
    history_panel:set_cur_item({ selected_entry, nil })
  elseif history_panel then
    history_panel.cur_item = { selected_entry, nil }
  end
  view.cur_entry = nil
  view.nulled = true
  view.git_diff_opened = false
  if clear_history_render_winbars then
    clear_history_render_winbars(view)
  end
  pcall(vim.cmd, 'redraw')
  return true
end

local function move_anchor_from_review(view, commit_hash)
  return require('config.git').detach_commit_overview(
    view.git_repository_root,
    commit_hash,
    view,
    {
      branch_name = view.git_branch_name,
      anchor_plan = view.git_anchor_plan,
      source = view.git_result_source,
    }
  )
end

function M.checkout_selected_commit()
  local view = active_view()
  local history_panel = view and view.panel
  if not history_panel
      or history_panel.updating
      or type(history_panel.get_log_entry_at_cursor) ~= 'function'
      or not view.git_repository_root then
    return false
  end
  local selected_entry = history_panel.cur_item and history_panel.cur_item[1]
  local selected_empty_review = selected_entry
    and selected_entry.nulled
    and selected_entry.commit
    and selected_entry.commit.hash == view.git_review_target
  if history_selection_is_rendering(view) and not selected_empty_review then
    vim.notify('Wait for the selected commit diff to finish rendering', vim.log.levels.INFO)
    return false
  end
  if lifecycle.get(view) and not lifecycle.is_ready(view) then
    lifecycle.log(view, 'anchor request', 'rejected before ready', '<Space>dm', 'warn')
    vim.notify('Wait for the current Git review to finish rendering', vim.log.levels.INFO)
    return false
  end
  if view.git_review_target and not view.git_review_ready then
    vim.notify('Wait for the searched commit review to finish rendering', vim.log.levels.INFO)
    return false
  end
  local cursor_log_entry = history_panel:get_log_entry_at_cursor()
  local log_entry = selected_empty_review and selected_entry or cursor_log_entry
  local commit_hash = log_entry and log_entry.commit and log_entry.commit.hash
  if not commit_hash then
    vim.notify('Select a commit or one of its files before checkout', vim.log.levels.INFO)
    return false
  end
  if lifecycle.get(view)
      and not lifecycle.begin_anchor(view, 'selected commit ' .. commit_hash:sub(1, 12)) then
    vim.notify('Wait for the current Git review before moving its anchor', vim.log.levels.INFO)
    return false
  end
  local anchor_started = move_anchor_from_review(view, commit_hash)
  if not anchor_started then
    lifecycle.cancel_anchor(view, 'anchor command was not started')
  end
  return anchor_started
end

function M.finish_anchor_operation(view, succeeded, detail)
  if not succeeded then
    lifecycle.cancel_anchor(view, detail)
  end
  events.emit('anchor_finished', {
    detail = detail,
    generation = lifecycle.generation(view),
    succeeded = succeeded,
  })
end

local function checkout_commit_mapping()
  return {
    'n',
    '<Space>dm',
    M.checkout_selected_commit,
    { desc = 'Checkout selected Git history commit' },
  }
end

local function show_selected_commit_details()
  require('diffview.actions').open_commit_log()
end

local function commit_details_mapping()
  return {
    'n',
    '<Space>dn',
    show_selected_commit_details,
    { desc = 'Show selected Git commit details' },
  }
end

local function load_children_mapping()
  return {
    'n',
    '<Space>dl',
    M.load_history_entry_children,
    { desc = 'Load complete file list for selected Git history commit' },
  }
end

local function focus_next_window()
  vim.cmd('wincmd w')
end

local function focus_previous_window()
  vim.cmd('wincmd W')
end

local function next_window_mapping()
  return { 'n', '<Tab>', focus_next_window, { desc = 'Focus next Git pane' } }
end

local function previous_window_mapping()
  return { 'n', '<S-Tab>', focus_previous_window, { desc = 'Focus previous Git pane' } }
end

function M.toggle_commit_list()
  local view = active_view()
  local history_panel = view and view.panel
  if not history_panel or type(history_panel.toggle) ~= 'function' then
    return false
  end
  history_panel:toggle(true)
  return true
end

local function commit_list_mapping()
  return { 'n', '<Space>dp', M.toggle_commit_list, { desc = 'Toggle Git history panel' } }
end

function M.search()
  local view = active_view()
  if not view or not view.git_repository_root then
    return false
  end
  return require('config.git.search').open(
    view.git_repository_root,
    view.git_search_options or view.git_history_options,
    view
  )
end

local function search_mapping()
  return {
    'n',
    '<Space>de',
    M.search,
    { desc = 'Search Git commits and issues' },
  }
end

local ignored_search_repeat_key = '<Space>n'
local ignored_search_repeat_description = 'Ignore unassigned Git search repeat'

local function ignored_search_repeat_mapping()
  return {
    'n',
    ignored_search_repeat_key,
    '<Nop>',
    { desc = ignored_search_repeat_description },
  }
end

local git_mode_mapping_keys = {
  ['Close current Git panel layer'] = panel.close_key,
  ['Focus next Git pane'] = '<Tab>',
  ['Focus previous Git pane'] = '<S-Tab>',
  ['Toggle Git history panel'] = '<Space>dp',
  ['Search Git commits and issues'] = '<Space>de',
  ['Show selected Git commit details'] = '<Space>dn',
  ['Search definitions in this historical buffer'] = '<Space>fw',
  [ignored_search_repeat_description] = ignored_search_repeat_key,
}

local function restore_editor_mappings(buffer)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  for _, buffer_mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, 'n')) do
    local owned_key = git_mode_mapping_keys[buffer_mapping.desc]
    if owned_key and buffer_mapping.lhsraw == vim.keycode(owned_key) then
      pcall(vim.keymap.del, 'n', owned_key, { buffer = buffer })
    end
  end
end

local function preserve_global_workspace_search(buffer)
  pcall(vim.keymap.del, 'n', '<Space>fw', { buffer = buffer })
end

local function is_commit_details_buffer(buffer)
  local buffer_name = vim.api.nvim_buf_get_name(buffer)
  return buffer_name:match('/commit_log$') ~= nil
end

local function close_commit_details()
  local detail_window = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(detail_window) then
    vim.api.nvim_win_close(detail_window, true)
  end
end

local function protect_view_buffer(buffer)
  preserve_global_workspace_search(buffer)
  local commit_details_buffer = is_commit_details_buffer(buffer)
  local close_action = commit_details_buffer
      and close_commit_details
    or M.handle_ctrl_q
  local close_description = commit_details_buffer
      and 'Close Git commit details'
    or 'Close current Git panel layer'
  vim.keymap.set('n', panel.close_key, close_action, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = close_description,
  })
  vim.keymap.set('n', '<Tab>', focus_next_window, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Focus next Git pane',
  })
  vim.keymap.set('n', '<S-Tab>', focus_previous_window, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Focus previous Git pane',
  })
  vim.keymap.set('n', '<Space>dp', M.toggle_commit_list, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Toggle Git history panel',
  })
  vim.keymap.set('n', '<Space>de', M.search, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Search Git commits and issues',
  })
  vim.keymap.set('n', ignored_search_repeat_key, '<Nop>', {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = ignored_search_repeat_description,
  })
end

local function protect_view_buffers(view)
  local function protect_current_buffers()
    if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      return
    end
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
      local buffer = vim.api.nvim_win_get_buf(window)
      protect_view_buffer(buffer)
    end
  end
  vim.schedule(protect_current_buffers)
  for _, delay_milliseconds in ipairs({ 40, 120, 300 }) do
    vim.defer_fn(protect_current_buffers, delay_milliseconds)
  end
end

local function history_view_is_rendering(view)
  if view.git_force_close then
    return false
  end
  local history_panel = view.panel
  if not history_panel or not history_panel.log_options then
    return false
  end
  if lifecycle.render_is_ready(view) then
    return false
  end
  return history_selection_is_rendering(view)
end

local function cancel_history_footer_enrichment(view)
  local review_hydration = view and view.git_review_hydration
  if review_hydration then
    review_hydration.cancelled = true
    view.git_review_hydration = nil
  end
  local cancel_enrichment = view and view.git_cancel_footer_enrichment
  if type(cancel_enrichment) == 'function' then
    cancel_enrichment()
  elseif view then
    view.git_footer_enrichment_token = nil
    view.git_footer_enriching = false
  end
end

local function cancel_history_head_resolution(view)
  local cancel_resolution = view and view.git_cancel_head_resolution
  if view then
    view.git_cancel_head_resolution = nil
    lifecycle.clear_activity(view, 'head')
  end
  if type(cancel_resolution) == 'function' then
    pcall(cancel_resolution)
  end
end

local function stop_history_stream(view)
  footer_loader.detach(view)
  local history_panel = view and view.panel
  lifecycle.clear_activity(view, 'history')
  lifecycle.clear_activity(view, 'enrichment')
  if history_panel and history_panel.shutdown and type(history_panel.shutdown.send) == 'function' then
    pcall(history_panel.shutdown.send, history_panel.shutdown)
  end
end

local function editing_tab_for_view(view)
  local diffview_lib = package.loaded['diffview.lib']
  local previous_tabpage = diffview_lib
    and type(diffview_lib.get_prev_non_view_tabpage) == 'function'
    and diffview_lib.get_prev_non_view_tabpage()
  if previous_tabpage and vim.api.nvim_tabpage_is_valid(previous_tabpage) then
    return previous_tabpage
  end
  if not view.tabpage
      or not vim.api.nvim_tabpage_is_valid(view.tabpage)
      or view.tabpage ~= vim.api.nvim_get_current_tabpage() then
    return
  end
  local tabpages = vim.api.nvim_list_tabpages()
  for tab_index, tabpage in ipairs(tabpages) do
    if tabpage == view.tabpage then
      return tabpages[tab_index - 1] or tabpages[tab_index + 1]
    end
  end
end

local function focus_editing_tab(view)
  local editing_tabpage = editing_tab_for_view(view)
  if editing_tabpage then
    vim.api.nvim_set_current_tabpage(editing_tabpage)
  end
end

local function dispose_rendered_view(view, completion_callback)
  if view.tabpage and not vim.api.nvim_tabpage_is_valid(view.tabpage) then
    completion_callback()
    return
  end
  if history_view_is_rendering(view) then
    vim.defer_fn(function()
      dispose_rendered_view(view, completion_callback)
    end, 20)
    return
  end
  local close_succeeded, close_error = pcall(function()
    if type(view.close) == 'function' and view.tabpage then
      view:close()
      require('diffview.lib').dispose_view(view)
    else
      require('diffview').close()
    end
  end)
  if not close_succeeded then
    vim.notify(tostring(close_error), vim.log.levels.ERROR)
  end
  completion_callback()
end

local function release_settled_actions()
  if state.closing then
    return
  end
  local settled_actions = state.settled_actions
  state.settled_actions = {}
  for _, settled_action in pairs(settled_actions) do
    vim.schedule(settled_action)
  end
end

local function close_rendering_view(view, completion_callback)
  dispose_rendered_view(view, function()
    if lifecycle.get(view) then
      lifecycle.mark_disposed(view, 'Diffview disposed')
    end
    state.pending_view_closes = math.max(0, state.pending_view_closes - 1)
    state.closing = state.pending_view_closes > 0
    if completion_callback then
      completion_callback()
    end
    release_settled_actions()
  end)
end

function M.is_active()
  local issue_module = package.loaded['config.git.issue']
  local issue_active = issue_module
    and type(issue_module.is_active) == 'function'
    and issue_module.is_active()
  return active_view() ~= nil or issue_active
end

function M.defer_until_settled(action_name, action_callback)
  if not state.closing then
    return false
  end
  state.settled_actions[action_name] = action_callback
  return true
end

function M.close(completion_callback, settled_callback)
  cancel_pending_history_request()
  local current_git_view = active_view()
  local root_view = state.root_view
  local issue_module = package.loaded['config.git.issue']
  local issue_active = issue_module
    and type(issue_module.is_active) == 'function'
    and issue_module.is_active()
  if not current_git_view and not root_view and not issue_active then
    return false
  end
  if issue_module and type(issue_module.close) == 'function' then
    issue_module.close()
  end
  local closing_views = {}
  if current_git_view then
    closing_views[#closing_views + 1] = current_git_view
  end
  if root_view and root_view ~= current_git_view then
    closing_views[#closing_views + 1] = root_view
  end
  state.pending_view_closes = #closing_views
  state.closing = state.pending_view_closes > 0
  state.repository_root = nil
  state.root_view = nil
  panel.reset()
  local focus_view = root_view or current_git_view
  for _, closing_view in ipairs(closing_views) do
    footer_loader.detach(closing_view)
    cancel_history_footer_enrichment(closing_view)
    cancel_history_head_resolution(closing_view)
    for _, retired_entry in ipairs(closing_view.git_footer_retired_entries or {}) do
      if type(retired_entry.destroy) == 'function' then
        retired_entry:destroy()
      end
    end
    closing_view.git_footer_retired_entries = nil
  end
  local return_completed = false
  local return_settled = false
  local function complete_return()
    if return_completed then
      return
    end
    return_completed = true
    if focus_view then
      focus_editing_tab(focus_view)
    end
    if completion_callback then
      completion_callback()
    end
    for _, closing_view in ipairs(closing_views) do
      if lifecycle.get(closing_view) then
        lifecycle.mark_closing(closing_view, 'editor frame rendered')
      end
    end
  end
  complete_return()
  local function settle_return()
    if return_settled then
      return
    end
    return_settled = true
    if settled_callback then
      settled_callback()
    end
  end
  if #closing_views == 0 then
    settle_return()
    release_settled_actions()
  end
  local completed_view_closes = 0
  for _, closing_view in ipairs(closing_views) do
    vim.defer_fn(function()
      close_rendering_view(closing_view, function()
        completed_view_closes = completed_view_closes + 1
        if completed_view_closes == #closing_views then
          complete_return()
          settle_return()
        end
      end)
    end, 0)
  end
  return true
end

function M.return_to_previous_git_panel()
  local view = active_view()
  local parent_view = view and view.git_parent_view
  if parent_view then
    panel.leave_search(view)
    local parent_tabpage = parent_view.tabpage
    if parent_tabpage and vim.api.nvim_tabpage_is_valid(parent_tabpage) then
      vim.api.nvim_set_current_tabpage(parent_tabpage)
    end
    state.closing = true
    state.pending_view_closes = 1
    footer_loader.detach(view)
    cancel_history_footer_enrichment(view)
    cancel_history_head_resolution(view)
    lifecycle.mark_closing(view, 'returning to parent Git view')
    vim.defer_fn(function()
      close_rendering_view(view)
    end, 0)
    return true
  end
  return M.close()
end

function M.handle_ctrl_q()
  if panel.level() == 'git' then
    return M.return_to_editor_line()
  end
  return panel.pop() ~= nil
end

local function history_editor_target(view)
  if view and view.git_diff_opened == false then
    return nil, 'no Git diff was explicitly opened'
  end
  if view and view.nulled then
    return nil, 'rendered AFTER commit has no working-tree line'
  end
  if not view
      or not view.cur_entry
      or (not view.cur_entry.opened and not lifecycle.render_is_ready(view)) then
    return nil, 'waiting for the rendered AFTER file'
  end
  if not view.cur_entry.absolute_path then
    return nil, 'rendered AFTER file has no working-tree path'
  end
  local target_path = vim.fs.normalize(view.cur_entry.absolute_path)
  if vim.fn.filereadable(target_path) ~= 1 then
    return nil, 'rendered AFTER file is absent from the working tree'
  end
  local layout = view.cur_layout
  local after_window = layout and layout.b
  local historical_cursor = after_window
      and after_window.id
      and vim.api.nvim_win_is_valid(after_window.id)
      and vim.api.nvim_win_get_cursor(after_window.id)
    or nil
  return {
    column = historical_cursor and historical_cursor[2] or nil,
    line = historical_cursor and historical_cursor[1] or nil,
    path = target_path,
  }
end

local function show_return_wait(view, detail)
  view.git_return_waiting = detail
  local history_panel = view.panel
  local panel_window = history_panel and history_panel.winid
  if not panel_window or not vim.api.nvim_win_is_valid(panel_window) then
    return
  end
  local result_source = escaped_winbar_text(view.git_result_source or 'LOCAL')
  vim.wo[panel_window].winbar = '%#DiffviewFilePanelSelected#'
    .. (' %s · RETURN · '):format(result_source)
    .. '%<'
    .. escaped_winbar_text(detail)
    .. ' %='
  vim.cmd('redraw')
end

local function refresh_editor_branch(editor_window)
  local function refresh_branch()
    local statusline_available, statusline = pcall(require, 'config.ui.statusline')
    if statusline_available and type(statusline.refresh_git_branch) == 'function' then
      pcall(statusline.refresh_git_branch)
    end
  end
  if editor_window and vim.api.nvim_win_is_valid(editor_window) then
    local window_refresh_succeeded = pcall(
      vim.api.nvim_win_call,
      editor_window,
      refresh_branch
    )
    return window_refresh_succeeded
  end
  refresh_branch()
  return true
end

local function prime_editor_branch(view)
  local editing_tabpage = editing_tab_for_view(view)
  if not editing_tabpage or not vim.api.nvim_tabpage_is_valid(editing_tabpage) then
    return false
  end
  local editor_window = vim.api.nvim_tabpage_get_win(editing_tabpage)
  return editor_window
    and vim.api.nvim_win_is_valid(editor_window)
    and refresh_editor_branch(editor_window)
    or false
end

local function close_without_editor_target(view)
  local branch_prepared = prime_editor_branch(view)
  return M.close(function()
    restore_editor_mappings(vim.api.nvim_get_current_buf())
    if not branch_prepared then
      refresh_editor_branch()
    end
    pcall(vim.cmd, 'redraw')
  end)
end

-- Git mode records only which existing working-tree file the editor should show.
local function write_editor_return_message(target)
  if not target or vim.fn.filereadable(target.path) ~= 1 then
    return nil
  end
  local target_buffer = vim.fn.bufadd(target.path)
  if target_buffer < 1 then
    return nil
  end
  return {
    buffer = target_buffer,
    path = target.path,
  }
end

local function editor_window_for_return(message)
  local current_window = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current_window) == message.buffer then
    return current_window
  end
  for _, tab_window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(tab_window) == message.buffer then
      return tab_window
    end
  end
  return current_window
end

local function apply_editor_return_message(view, message)
  vim.schedule(function()
    local applied = false
    local apply_error
    local apply_succeeded = xpcall(function()
      local editor_window = editor_window_for_return(message)
      if vim.api.nvim_win_get_buf(editor_window) ~= message.buffer then
        vim.api.nvim_win_set_buf(editor_window, message.buffer)
      end
      if vim.api.nvim_get_current_win() ~= editor_window then
        vim.api.nvim_set_current_win(editor_window)
      end
      restore_editor_mappings(message.buffer)
      vim.cmd('redraw')
      applied = true
    end, function(execution_error)
      apply_error = tostring(execution_error)
    end)
    if not apply_succeeded then
      vim.notify(apply_error, vim.log.levels.ERROR)
    end
    lifecycle.log(
      view,
      'editor render',
      applied and 'complete' or 'failed',
      message.path,
      applied and 'info' or 'error'
    )
    events.emit('editor_rendered', {
      generation = lifecycle.generation(view),
      path = message.path,
      rendered = applied,
    })
  end)
end

function M.return_to_editor_line()
  local view = active_view()
  if not M.is_active() then
    return false
  end
  local lifecycle_state = lifecycle.get(view)
  local initial_render_pending = lifecycle_state and lifecycle_state.initializing
  cancel_history_footer_enrichment(view)
  cancel_history_head_resolution(view)
  if view then
    view.git_force_close = true
    stop_history_stream(view)
  end
  if initial_render_pending then
    return close_without_editor_target(view)
  end
  local editor_target = history_editor_target(view)
  if not editor_target then
    return close_without_editor_target(view)
  end
  local return_message = write_editor_return_message(editor_target)
  if not return_message then
    return close_without_editor_target(view)
  end
  show_return_wait(view, 'restoring editor')
  return M.close(function()
    restore_editor_mappings(vim.api.nvim_get_current_buf())
    refresh_editor_branch()
    apply_editor_return_message(view, return_message)
  end, function()
    if vim.api.nvim_buf_is_valid(return_message.buffer)
        and vim.api.nvim_get_current_buf() == return_message.buffer then
      refresh_editor_branch()
      pcall(vim.cmd, 'redrawstatus')
    end
  end)
end

local function command_line_enter()
  local command_line = vim.trim(vim.fn.getcmdline())
  local partial_quit = command_line:match('^q!?$') or command_line:match('^quit!?$')
  if vim.fn.getcmdtype() == ':' and partial_quit and M.is_active() then
    vim.schedule(function()
      vim.notify('Use <C-q> to close the current Git panel', vim.log.levels.INFO)
    end)
    return vim.keycode('<C-c>')
  end
  return vim.keycode('<CR>')
end

local empty_tree_hash = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

local function history_revision_label(revision)
  local commit_hash = revision and revision.commit
  if commit_hash == empty_tree_hash then
    return 'EMPTY TREE'
  end
  if commit_hash then
    return commit_hash:sub(1, 10)
  end
  return 'UNKNOWN'
end

local function set_history_winbar(window, phase, source)
  if not window or not window.file then
    return
  end
  local revision_label = history_revision_label(window.file.rev)
  local file_path = window.file.path or ''
  local result_source = source and (' · %s'):format(source) or ''
  local priority_text = escaped_winbar_text(
    (' %s · %s%s · '):format(phase, revision_label, result_source)
  )
  local winbar = priority_text .. '%<' .. escaped_winbar_text(file_path)
  window.file.winbar = winbar
  if window.id and vim.api.nvim_win_is_valid(window.id) then
    vim.wo[window.id].winbar = winbar
    vim.wo[window.id].cursorline = true
    vim.wo[window.id].cursorlineopt = 'line'
  end
end

local function update_history_winbars(view)
  local layout = view.cur_layout
  if not layout then
    return
  end
  set_history_winbar(layout.a, 'BEFORE', view.git_result_source)
  set_history_winbar(layout.b, 'AFTER', view.git_result_source)
end

clear_history_render_winbars = function(view)
  local current_layout = view and view.cur_layout
  for _, side in ipairs({ 'a', 'b' }) do
    local diff_window = current_layout and current_layout[side]
    if diff_window
        and diff_window.id
        and vim.api.nvim_win_is_valid(diff_window.id) then
      vim.wo[diff_window.id].winbar = ''
    end
  end
end

local function synchronize_history_syntax(view)
  local syntax_module = require('config.syntax.treesitter')
  local syntax_generation = lifecycle.generation(view)
  local rendered_entry = view.cur_entry
  vim.schedule(function()
    if syntax_generation
        and not lifecycle.callback_is_current(
          view,
          syntax_generation,
          'syntax synchronization',
          rendered_entry and (rendered_entry.path or rendered_entry.oldpath) or 'no file'
        ) then
      return
    end
    if not view.tabpage
        or not vim.api.nvim_tabpage_is_valid(view.tabpage)
        or view.cur_entry ~= rendered_entry then
      return
    end
    local current_layout = view.cur_layout
    local synchronized_buffers = {}
    for _, side in ipairs({ 'a', 'b' }) do
      local diff_window = current_layout and current_layout[side]
      local file_buffer = diff_window and diff_window.file and diff_window.file.bufnr
      local window_buffer = diff_window
          and diff_window.id
          and vim.api.nvim_win_is_valid(diff_window.id)
          and vim.api.nvim_win_get_buf(diff_window.id)
        or nil
      local diff_buffer = file_buffer
          and vim.api.nvim_buf_is_valid(file_buffer)
          and file_buffer
        or window_buffer
      if diff_buffer
          and vim.api.nvim_buf_is_loaded(diff_buffer)
          and not synchronized_buffers[diff_buffer] then
        synchronized_buffers[diff_buffer] = true
        syntax_module.ensure_highlighting(diff_buffer)
      end
    end
  end)
end

local function current_anchor_label(view)
  local checked_out_branch = view.git_checked_out_branch
  if checked_out_branch and checked_out_branch ~= '' then
    return ('CURRENT BRANCH · %s'):format(checked_out_branch)
  end
  local detached_head_commit = view.git_detached_head_commit
  if detached_head_commit and detached_head_commit ~= '' then
    return ('CURRENT · DETACHED · %s'):format(detached_head_commit:sub(1, 12))
  end
end

local function scope_label(view)
  local history_options = view.git_history_options or {}
  local location = history_options.location or {}
  if history_options.kind == 'symbol' then
    local structure = location.structure or {}
    local structure_label = structure.label or 'selected scope'
    local first_line = structure.first_line or (history_options.range and history_options.range[1])
    local last_line = structure.last_line or (history_options.range and history_options.range[2])
    local line_suffix = first_line and last_line and (':%d-%d'):format(first_line, last_line) or ''
    return ('SYMBOL · %s · %s%s'):format(
      structure_label,
      location.relative_path or '',
      line_suffix
    )
  end
  if history_options.kind == 'file' then
    return ('FILE · %s'):format(location.relative_path or '')
  end
  return 'REPOSITORY'
end

local function highlighted_winbar_chunk(highlight_group, text)
  return ('%%#%s#%s'):format(highlight_group, escaped_winbar_text(text))
end

local function footer_metadata_chunks(view)
  local history_options = view.git_history_options or {}
  local source = view.git_result_source or 'LOCAL'
  local source_highlight = 'Normal'
  local chunks = {}
  local function add_divider()
    if #chunks > 0 then
      chunks[#chunks + 1] = { ' │ ', 'Normal' }
    end
  end
  local branch_name = view.git_branch_name
  if branch_name and branch_name ~= '' then
    local branch_role = history_options.review_only and 'BRANCH REVIEW' or 'BRANCH'
    chunks[#chunks + 1] = {
      (' REVIEW · %s · %s '):format(source, branch_role),
      source_highlight,
    }
    chunks[#chunks + 1] = { branch_name, 'Normal' }
    local review_tip_commit = view.git_review_tip_commit
    if review_tip_commit and review_tip_commit ~= '' then
      add_divider()
      chunks[#chunks + 1] = { ' TIP · ', 'Normal' }
      chunks[#chunks + 1] = { review_tip_commit:sub(1, 12), 'Normal' }
    end
  else
    chunks[#chunks + 1] = { (' SOURCE · %s '):format(source), source_highlight }
  end
  add_divider()
  chunks[#chunks + 1] = { ' SCOPE · ', 'Normal' }
  chunks[#chunks + 1] = { scope_label(view) .. ' ', 'Normal' }
  return chunks
end

local function history_panel_top_row(panel_window)
  local top_row
  local position_resolved = pcall(vim.api.nvim_win_call, panel_window, function()
    top_row = vim.fn.line('w0') - 1
  end)
  if not position_resolved then
    return 0
  end
  return math.max(0, top_row)
end

local function history_panel_cursor_row(panel_window)
  local cursor_position
  local position_resolved = pcall(function()
    cursor_position = vim.api.nvim_win_get_cursor(panel_window)
  end)
  if not position_resolved or not cursor_position then
    return 0
  end
  return math.max(0, cursor_position[1] - 1)
end

local function pinned_footer_branch(view)
  local history_panel = view and view.panel
  local panel_window = history_panel and history_panel.winid
  if not panel_window or not vim.api.nvim_win_is_valid(panel_window) then
    return
  end
  local cursor_row = history_panel_cursor_row(panel_window)
  local pinned_branch
  for _, segment in ipairs(view.git_footer_segments or {}) do
    if segment.row > cursor_row then
      break
    end
    pinned_branch = segment.label
  end
  return pinned_branch
end

local function update_history_footer_header(view)
  local history_panel = view and view.panel
  local panel_buffer = history_panel and history_panel.bufid
  local panel_window = history_panel and history_panel.winid
  if not panel_buffer
      or not vim.api.nvim_buf_is_valid(panel_buffer)
      or not panel_window
      or not vim.api.nvim_win_is_valid(panel_window) then
    return false
  end
  vim.api.nvim_buf_clear_namespace(panel_buffer, footer_header_namespace, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(panel_buffer)
  if line_count == 0 then
    return false
  end
  local top_row = math.min(history_panel_top_row(panel_window), line_count - 1)
  vim.api.nvim_buf_set_extmark(panel_buffer, footer_header_namespace, top_row, 0, {
    priority = 130,
    virt_lines = { footer_metadata_chunks(view) },
    virt_lines_above = true,
  })
  return true
end

local function anchor_and_pinned_label(view)
  local anchor_label = current_anchor_label(view)
  local pinned_branch = pinned_footer_branch(view)
  if not pinned_branch then
    return anchor_label
  end
  local pinned_label = ('PINNED BRANCH · %s'):format(pinned_branch)
  return anchor_label and (anchor_label .. ' · ' .. pinned_label) or pinned_label
end

local function update_history_panel_winbar(view)
  local history_panel = view.panel
  local panel_window = history_panel and history_panel.winid
  if not panel_window
      or not vim.api.nvim_win_is_valid(panel_window) then
    return
  end
  if lifecycle.phase(view) == 'failed' then
    vim.wo[panel_window].winbar = highlighted_winbar_chunk(
      'DiagnosticError',
      ' GIT MODE · FAILED '
    )
      .. '%<'
      .. escaped_winbar_text(lifecycle.failure_detail(view) or 'history loading stopped')
      .. escaped_winbar_text(' · <C-q> close ')
      .. '%='
    return
  end
  local activity_labels = lifecycle.activity_labels(view)
  if #activity_labels > 0 then
    vim.wo[panel_window].winbar = highlighted_winbar_chunk(
      'Normal',
      ' GIT MODE · LOADING '
    )
      .. '%<'
      .. escaped_winbar_text(table.concat(activity_labels, ' + '))
      .. ' %='
    return
  end
  if view.git_return_waiting then
    local return_source = escaped_winbar_text(view.git_result_source or 'LOCAL')
    local anchor_label = anchor_and_pinned_label(view)
    local anchor_prefix = anchor_label and (anchor_label .. ' · ') or ''
    vim.wo[panel_window].winbar = '%#DiffviewFilePanelSelected#'
      .. escaped_winbar_text((' %s%s · RETURN · '):format(anchor_prefix, return_source))
      .. '%<'
      .. escaped_winbar_text(view.git_return_waiting)
      .. ' %='
    return
  end
  if view.git_anchor_waiting then
    local anchor_source = escaped_winbar_text(view.git_result_source or 'LOCAL')
    local anchor_label = anchor_and_pinned_label(view)
    local anchor_prefix = anchor_label and (anchor_label .. ' · ') or ''
    vim.wo[panel_window].winbar = '%#DiffviewFilePanelSelected#'
      .. escaped_winbar_text((' %s%s · ANCHOR · '):format(anchor_prefix, anchor_source))
      .. '%<'
      .. escaped_winbar_text(view.git_anchor_waiting)
      .. ' %='
    return
  end
  local source = view.git_result_source or 'LOCAL'
  local anchor_label = anchor_and_pinned_label(view)
  local priority_label = anchor_label or ('GIT HISTORY · %s'):format(source)
  vim.wo[panel_window].winbar = highlighted_winbar_chunk(
    'Normal',
    ' ' .. priority_label .. ' '
  ) .. '%='
end

local function branch_names_from_references(reference_names)
  local branch_names = {}
  local seen_names = {}
  for _, raw_reference in ipairs(vim.split(reference_names or '', ',', { plain = true })) do
    local reference = vim.trim(raw_reference)
    local pointed_reference = reference:match('^HEAD%s*%-%>%s*(.+)$')
      or reference:match('^[^,]*HEAD%s*%-%>%s*(.+)$')
    local branch_name = pointed_reference or reference
    local is_metadata = branch_name == ''
      or branch_name == 'HEAD'
      or branch_name == 'DETACHED HEAD'
      or vim.startswith(branch_name, 'tag: ')
    if not is_metadata and not seen_names[branch_name] then
      branch_names[#branch_names + 1] = branch_name
      seen_names[branch_name] = true
    end
  end
  return branch_names
end

local function entry_component_for(history_panel, entry)
  local entry_components = history_panel.components
    and history_panel.components.log
    and history_panel.components.log.entries
  for _, component_structure in ipairs(entry_components or {}) do
    if component_structure.comp.context == entry then
      return component_structure
    end
  end
end

local function restore_history_cursor(history_panel, entry)
  local component_structure = entry_component_for(history_panel, entry)
  local entry_component = component_structure and component_structure.comp
  local panel_window = history_panel and history_panel.winid
  if not entry_component
      or not panel_window
      or not vim.api.nvim_win_is_valid(panel_window) then
    return false
  end
  return pcall(vim.api.nvim_win_set_cursor, panel_window, {
    entry_component.lstart + 1,
    0,
  })
end

local function restore_history_selection(view, fallback_entry)
  local history_panel = view and view.panel
  local current_item = history_panel and history_panel.cur_item
  local selected_file = current_item and current_item[2]
  if view and view.git_diff_opened
      and selected_file
      and type(history_panel.highlight_item) == 'function' then
    history_panel:highlight_item(selected_file)
    return true
  end
  return restore_history_cursor(history_panel, fallback_entry)
end

local function target_file_index(entry)
  for file_index, file in ipairs(entry.files or {}) do
    if file == entry.git_target_file then
      return file_index
    end
  end
end

decorate_history_footer = function(view)
  local history_panel = view and view.panel
  local panel_buffer = history_panel and history_panel.bufid
  if not history_panel
      or not panel_buffer
      or not vim.api.nvim_buf_is_valid(panel_buffer) then
    return false
  end
  vim.api.nvim_buf_clear_namespace(panel_buffer, footer_annotation_namespace, 0, -1)
  local segments = {}
  local active_branch_label
  local fallback_branch_started = false
  for entry_index, entry in ipairs(history_panel.entries or {}) do
    local component_structure = entry_component_for(history_panel, entry)
    local commit_component = component_structure and component_structure.commit
      and component_structure.commit.comp
    if entry.git_independent_preview
        and commit_component
        and commit_component.lstart >= 0 then
      vim.api.nvim_buf_set_extmark(
        panel_buffer,
        footer_annotation_namespace,
        commit_component.lstart,
        0,
        {
          virt_lines = {
            { { '── PREVIEW · OUTSIDE CURRENT BRANCH ', 'Normal' } },
          },
          virt_lines_above = true,
        }
      )
    end
    local reference_branches = entry.git_independent_preview and {}
      or branch_names_from_references(entry.commit and entry.commit.ref_names)
    if entry.git_independent_preview then
      -- This row is deliberately outside the mounted branch walk.
    elseif #reference_branches > 0 then
      active_branch_label = table.concat(reference_branches, ' · ')
    elseif not active_branch_label and view.git_branch_name then
      active_branch_label = view.git_branch_name
      fallback_branch_started = true
    end
    entry.git_branch_segment = active_branch_label
    if commit_component and commit_component.lstart >= 0 and #reference_branches > 0 then
      local commit_row = commit_component.lstart
      segments[#segments + 1] = { label = active_branch_label, row = commit_row }
      vim.api.nvim_buf_set_extmark(panel_buffer, footer_annotation_namespace, commit_row, 0, {
        virt_lines = {
          { { ('── BRANCH · %s '):format(active_branch_label), 'Normal' } },
        },
        virt_lines_above = true,
      })
    elseif commit_component
        and commit_component.lstart >= 0
        and (entry_index == 1 or fallback_branch_started)
        and active_branch_label then
      segments[#segments + 1] = { label = active_branch_label, row = commit_component.lstart }
      fallback_branch_started = false
    end

    local scoped_file_index = target_file_index(entry)
    local files_component = component_structure and component_structure.files
      and component_structure.files.comp
    if scoped_file_index
        and files_component
        and files_component.lstart >= 0
        and not entry.folded then
      local target_row = files_component.lstart + scoped_file_index - 1
      local target_file = entry.git_target_file
      local target_path = target_file.path or target_file.oldpath or ''
      local target_basename = vim.fs.basename(target_path)
      local rendered_line = vim.api.nvim_buf_get_lines(
        panel_buffer,
        target_row,
        target_row + 1,
        false
      )[1] or ''
      if rendered_line == '' then
        goto continue_entry
      end
      local basename_start = rendered_line:find(target_basename, 1, true)
      local basename_column = basename_start and basename_start - 1 or 0
      local target_mark_options = {
        priority = 120,
        virt_text = {
          { (' MATCH · %s '):format((view.git_history_kind or 'file'):upper()), 'Normal' },
        },
        virt_text_pos = 'right_align',
      }
      if basename_start then
        target_mark_options.end_col = basename_column + #target_basename
        target_mark_options.end_row = target_row
      end
      vim.api.nvim_buf_set_extmark(
        panel_buffer,
        footer_annotation_namespace,
        target_row,
        basename_column,
        target_mark_options
      )
    end
    ::continue_entry::
  end
  view.git_footer_segments = segments
  update_history_panel_winbar(view)
  update_history_footer_header(view)
  return true
end

function M.decorate_history_footer(view)
  return decorate_history_footer(view)
end

request_footer_decoration = function(view)
  if not view or view.git_footer_render_pending then
    return false
  end
  local render_token = { generation = lifecycle.generation(view) }
  view.git_footer_render_pending = render_token
  vim.schedule(function()
    if view.git_footer_render_pending ~= render_token then
      return
    end
    view.git_footer_render_pending = nil
    if render_token.generation
        and not lifecycle.is_current(view, render_token.generation) then
      return
    end
    if view.tabpage and not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      return
    end
    decorate_history_footer(view)
  end)
  return true
end

local function mark_detached_head_entry(view)
  local detached_head_commit = view.git_detached_head_commit
  local history_panel = view.panel
  if not detached_head_commit or not history_panel then
    return false
  end
  for _, entry in ipairs(history_panel.entries or {}) do
    local commit = entry.commit
    if commit and commit.hash == detached_head_commit then
      local retained_references = {}
      for _, raw_reference in ipairs(vim.split(commit.ref_names or '', ',', { plain = true })) do
        local reference = vim.trim(raw_reference)
        if reference ~= ''
            and reference ~= 'HEAD'
            and reference ~= 'DETACHED HEAD' then
          retained_references[#retained_references + 1] = reference
        end
      end
      retained_references[#retained_references + 1] = 'DETACHED HEAD'
      local normalized_references = table.concat(retained_references, ', ')
      if commit.ref_names == normalized_references then
        return false
      end
      commit.ref_names = normalized_references
      return true
    end
  end
  return false
end

local function prepare_scoped_footer_entries(view, entries)
  if not view.git_footer_tree then
    return
  end
  for _, entry in ipairs(entries) do
    entry.single_file = false
    entry.git_target_file = entry.files and entry.files[1]
    entry.git_files_enriched = false
    entry.git_files_enriching = false
  end
end

function M.adapt_history_footer(view)
  local history_panel = view and view.panel
  if not view
      or view.git_footer_enriching
      or not history_panel then
    return false
  end
  local footer_changed = mark_detached_head_entry(view)
  if view.git_footer_tree then
    for _, entry in ipairs(history_panel.entries or {}) do
      if entry.single_file then
        entry.single_file = false
        footer_changed = true
      end
    end
  end
  if footer_changed and type(history_panel.render) == 'function' then
    history_panel:render()
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
  end
  update_history_panel_winbar(view)
  request_footer_decoration(view)
  return footer_changed
end

local function destroy_history_files(files)
  for _, file in ipairs(files or {}) do
    if type(file.destroy) == 'function' then
      file:destroy()
    end
  end
end

local function target_paths(seed_file, fallback_path)
  local paths = {}
  local seen_paths = {}
  for _, candidate_path in ipairs({
    seed_file and seed_file.path,
    seed_file and seed_file.oldpath,
    fallback_path,
  }) do
    if candidate_path and candidate_path ~= '' and not seen_paths[candidate_path] then
      paths[#paths + 1] = candidate_path
      seen_paths[candidate_path] = true
    end
  end
  return paths
end

local function find_target_file(files, paths)
  for _, candidate_path in ipairs(paths) do
    for _, file in ipairs(files) do
      if file.path == candidate_path or file.oldpath == candidate_path then
        return file
      end
    end
  end
end

local function history_layout_options(view)
  local default_layout = type(view.get_default_layout) == 'function'
      and view.get_default_layout()
    or nil
  local merge_layout = type(view.get_default_merge_layout) == 'function'
      and view.get_default_merge_layout()
    or default_layout
  return {
    default_layout = default_layout,
    merge_layout = merge_layout,
  }
end

local function replace_entry_files(entry, full_files, scoped_paths)
  local previous_files = entry.files
  local retained_scoped_file = find_target_file(previous_files, scoped_paths)
  local loaded_scoped_file = find_target_file(full_files, scoped_paths)
  local obsolete_files = {}
  if retained_scoped_file and loaded_scoped_file then
    retained_scoped_file.status = loaded_scoped_file.status
    retained_scoped_file.stats = loaded_scoped_file.stats
    for file_index, file in ipairs(full_files) do
      if file == loaded_scoped_file then
        full_files[file_index] = retained_scoped_file
        break
      end
    end
    obsolete_files[#obsolete_files + 1] = loaded_scoped_file
  end
  for _, file in ipairs(full_files) do
    file.commit = entry.commit
  end
  local scoped_file = find_target_file(full_files, scoped_paths) or full_files[1]
  for _, previous_file in ipairs(previous_files) do
    if previous_file ~= scoped_file then
      obsolete_files[#obsolete_files + 1] = previous_file
    end
  end
  entry.files = full_files
  entry.git_target_file = scoped_file
  entry.single_file = false
  if type(entry.update_status) == 'function' then
    entry:update_status()
  end
  if type(entry.update_stats) == 'function' then
    entry:update_stats()
  end
  return scoped_file, obsolete_files
end

local complete_history_readiness
local finalize_history_file_render
local finish_history_render

local function install_footer_enrichment_cancellation(view)
  if view.git_cancel_footer_enrichment then
    return
  end
  view.git_cancel_footer_enrichment = function()
    local entry_tokens = view.git_footer_entry_tokens or {}
    view.git_footer_entry_tokens = {}
    view.git_cancel_footer_enrichment = nil
    view.git_footer_enriching = false
    for _, entry_token in pairs(entry_tokens) do
      entry_token.cancelled = true
      entry_token.entry.git_files_enriching = false
    end
  end
end

function M.enrich_history_footer_entry(view, entry, completion_callback)
  if not view or not entry or entry.git_files_enriched or entry.git_files_enriching then
    return false
  end
  local seed_file = entry.files and entry.files[1]
  local revisions = seed_file and seed_file.revs
  if not seed_file or not revisions or not revisions.a or not revisions.b then
    entry.git_files_enriched = true
    entry.git_target_file = seed_file
    return false
  end
  local utilities_loaded, vcs_utils = pcall(require, 'diffview.vcs.utils')
  if not utilities_loaded or type(vcs_utils.diff_file_list) ~= 'function' then
    entry.git_files_enriched = true
    entry.git_target_file = seed_file
    return false
  end

  local entry_token = {
    cancelled = false,
    entry = entry,
    generation = lifecycle.generation(view),
  }
  view.git_footer_entry_tokens = view.git_footer_entry_tokens or {}
  view.git_footer_entry_tokens[entry] = entry_token
  entry.git_files_enriching = true
  install_footer_enrichment_cancellation(view)

  local fallback_path = view.git_history_options
    and view.git_history_options.location
    and view.git_history_options.location.relative_path
  local scoped_paths = target_paths(seed_file, fallback_path)
  local layout_options = history_layout_options(view)
  vcs_utils.diff_file_list(
    view.adapter,
    revisions.a,
    revisions.b,
    {},
    { show_untracked = false },
    layout_options,
    function(errors, file_dictionary)
      vim.schedule(function()
        local entry_tokens = view.git_footer_entry_tokens or {}
        local callback_is_current = not entry_token.cancelled
          and entry_tokens[entry] == entry_token
          and view.tabpage
          and vim.api.nvim_tabpage_is_valid(view.tabpage)
          and (
            entry_token.generation == nil
            or lifecycle.is_current(view, entry_token.generation)
          )
        local loaded_files = file_dictionary and file_dictionary.working or {}
        if not callback_is_current then
          destroy_history_files(loaded_files)
          if completion_callback then
            completion_callback(view, entry)
          end
          return
        end

        entry_tokens[entry] = nil
        entry.git_files_enriching = false
        entry.git_files_enriched = true
        if not next(entry_tokens) then
          view.git_cancel_footer_enrichment = nil
        end
        local obsolete_files = {}
        if not errors and #loaded_files > 0 then
          local _, replaced_files = replace_entry_files(entry, loaded_files, scoped_paths)
          obsolete_files = replaced_files
        else
          entry.git_target_file = seed_file
          vim.notify('Could not expand the selected Git history commit', vim.log.levels.WARN)
        end
        local history_panel = view.panel
        if history_panel and type(history_panel.update_components) == 'function' then
          history_panel:update_components()
        end
        if history_panel and type(history_panel.render) == 'function' then
          history_panel:render()
        end
        if history_panel and type(history_panel.redraw) == 'function' then
          history_panel:redraw()
        end
        request_footer_decoration(view)
        lifecycle.log(
          view,
          'footer entry enrichment',
          errors and 'failed' or 'complete',
          ('commit=%s files=%d'):format(
            entry.commit and entry.commit.hash or 'none',
            #loaded_files
          ),
          errors and 'warn' or 'info'
        )
        vim.defer_fn(function()
          destroy_history_files(obsolete_files)
        end, 1000)
        if completion_callback then
          completion_callback(view, entry)
        end
      end)
    end
  )
  return true
end

-- <Space>dl: match-filtered histories ship only the traced file per commit row.
-- This explicit action loads the cursored commit's complete file list through
-- Diffview's parent-to-commit loader; repository history already carries it.
function M.load_history_entry_children()
  local view = active_view()
  local history_panel = view and view.panel
  if not view or not history_panel then
    return false
  end
  if not view.git_footer_tree then
    vim.notify('Repository history already lists every changed file', vim.log.levels.INFO)
    return false
  end
  local cursor_item
  if type(history_panel.is_focused) == 'function'
      and history_panel:is_focused()
      and type(history_panel.get_item_at_cursor) == 'function' then
    cursor_item = history_panel:get_item_at_cursor()
  end
  local entry
  if cursor_item then
    if cursor_item.files then
      entry = cursor_item
    else
      entry = history_entry_for_file(view, cursor_item)
    end
  end
  entry = entry or history_panel.cur_item and history_panel.cur_item[1]
  if not entry then
    return false
  end
  if entry.git_details_loaded == false then
    footer_loader.ensure_entry(view, entry, function(details_loaded)
      if details_loaded and active_view() == view then
        M.load_history_entry_children()
      end
    end)
    return true
  end
  if entry.git_files_enriched then
    vim.notify('Selected commit already lists every changed file', vim.log.levels.INFO)
    return true
  end
  if entry.git_files_enriching then
    return true
  end
  if entry.folded and type(history_panel.set_entry_fold) == 'function' then
    pcall(history_panel.set_entry_fold, history_panel, entry, true)
  end
  if not M.enrich_history_footer_entry(view, entry) then
    vim.notify("Could not load the selected commit's file list", vim.log.levels.WARN)
    return false
  end
  return true
end

function M.enrich_history_footer(view)
  local history_panel = view and view.panel
  local entries = history_panel and history_panel.entries or {}
  if not view or not view.git_footer_tree or not history_panel then
    if view then
      view.git_footer_enriching = false
    end
    return false
  end
  cancel_history_footer_enrichment(view)
  mark_detached_head_entry(view)
  view.git_footer_enriching = true
  local selected_entry = history_panel.cur_item and history_panel.cur_item[1] or entries[1]
  prepare_scoped_footer_entries(view, entries)

  local settlement_attempts = 500
  local enrichment_generation = lifecycle.generation(view)
  local initial_detail_finished = selected_entry == nil
    or selected_entry.git_details_loaded ~= false
  local initial_detail_requested = false
  local finish_initial_footer
  finish_initial_footer = function()
    if enrichment_generation and not lifecycle.is_current(view, enrichment_generation) then
      return
    end
    if not initial_detail_finished and selected_entry then
      if not initial_detail_requested then
        initial_detail_requested = true
        footer_loader.ensure_entry(view, selected_entry, function(details_loaded)
          initial_detail_finished = true
          if not details_loaded then
            lifecycle.log(
              view,
              'initial scoped detail',
              'preload failed; retaining seed entry',
              selected_entry.commit and selected_entry.commit.hash or 'unknown',
              'warn'
            )
          end
          finish_initial_footer()
        end)
      end
      return
    end
    if history_selection_is_rendering(view) then
      settlement_attempts = settlement_attempts - 1
      if settlement_attempts > 0 then
        vim.defer_fn(finish_initial_footer, 20)
      else
        lifecycle.mark_failed(view, 'initial Diffview file warm-up did not settle')
        finish_history_render(view, false, 'initial Diffview file warm-up did not settle')
      end
      return
    end
    view.git_footer_enriching = false
    lifecycle.clear_activity(view, 'enrichment')
    history_panel.single_file = false
    if type(history_panel.update_components) == 'function' then
      history_panel:update_components()
    end
    if type(history_panel.render) == 'function' then
      history_panel:render()
    end
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
    restore_history_selection(view, selected_entry)
    request_footer_decoration(view)
    local newest_entry = entries[1]
    if lifecycle.get(view) then
      lifecycle.mark_enrichment_ready(view)
      lifecycle.log(
        view,
        'footer redraw',
        'complete',
        ('entries=%d lazy=true'):format(#entries),
        'info'
      )
      if newest_entry then
        clear_history_diff(view, selected_entry or newest_entry)
        lifecycle.mark_idle_ready(view, 'scoped history waiting for an explicit commit open')
        finish_history_render(view, true, 'scoped history ready with lazy commit expansion')
      else
        lifecycle.mark_empty_ready(view, 'scoped history has no matches')
        finish_history_render(view, true, 'empty scoped history rendered')
      end
    end
  end
  finish_initial_footer()
  return true
end

finish_history_render = function(view, render_succeeded, detail)
  local render_callback = view.git_render_ready_callback
  if not render_callback then
    return
  end
  view.git_render_ready_callback = nil
  render_callback(view, render_succeeded, detail)
end

local function synchronize_history_footer(view)
  local remaining_attempts = 1500
  local synchronization_generation = lifecycle.generation(view)
  local function synchronize()
    if synchronization_generation
        and not lifecycle.is_current(view, synchronization_generation) then
      lifecycle.log(
        view,
        'callback history list settle',
        'discarded stale',
        ('attempts_left=%d'):format(remaining_attempts),
        'warn'
      )
      return
    end
    if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      lifecycle.log(view, 'history list settle', 'view closed', nil, 'warn')
      finish_history_render(view, false, 'history view closed before rendering')
      return
    end
    local history_panel = view.panel
    if history_panel
        and (
          history_panel.updating
          or history_selection_is_rendering(view)
          or (view.git_history_options and view.git_history_options.head_resolution_pending)
          or not footer_loader.list_is_ready(view)
        ) then
      remaining_attempts = remaining_attempts - 1
      if remaining_attempts > 0 then
        vim.defer_fn(synchronize, 20)
      else
        lifecycle.log(view, 'history list settle', 'timed out', nil, 'error')
        stop_history_stream(view)
        lifecycle.mark_failed(view, 'history list did not settle')
        update_history_panel_winbar(view)
        finish_history_render(view, false, 'history list did not settle')
      end
    else
      local entries = history_panel and history_panel.entries or {}
      lifecycle.clear_activity(view, 'history')
      update_history_panel_winbar(view)
      local selected_commit = view.git_history_options.selected_commit
      lifecycle.mark_list_ready(view, #entries)
      if #entries == 0 then
        lifecycle.mark_empty_ready(view, 'empty history rendered')
        if not selected_commit then
          finish_history_render(view, true, 'empty history rendered')
        end
      elseif view.git_footer_tree then
        lifecycle.set_activity(view, 'enrichment', 'preparing matched commits')
        vim.notify(
          ('Git history: found %d matching commits'):format(#entries),
          vim.log.levels.INFO
        )
        M.enrich_history_footer(view)
      else
        M.adapt_history_footer(view)
        local idle_entry = type(history_panel.get_log_entry_at_cursor) == 'function'
            and history_panel:get_log_entry_at_cursor()
          or history_panel.cur_item and history_panel.cur_item[1]
          or entries[1]
        if view.git_diff_opened then
          complete_history_readiness(view, 'explicit history file rendered')
        else
          clear_history_diff(view, idle_entry)
          lifecycle.mark_idle_ready(view, 'history waiting for an explicit file open')
          if not selected_commit then
            finish_history_render(view, true, 'history ready with empty diff panes')
          end
        end
      end
    end
  end
  vim.defer_fn(synchronize, 20)
end

local function expand_scoped_footer_entry(view, file)
  if not view.git_footer_tree then
    return
  end
  local history_panel = view.panel
  local entry = history_panel
    and type(history_panel.find_entry) == 'function'
    and history_panel:find_entry(file)
  if not entry then
    return
  end
  M.adapt_history_footer(view)
  if not entry.folded and type(history_panel.highlight_item) == 'function' then
    history_panel:highlight_item(file)
  end
  request_footer_decoration(view)
end

local function restore_ordinary_history_folds(layout)
  for _, side in ipairs({ 'a', 'b' }) do
    local diff_window = layout and layout[side]
    if diff_window
        and diff_window.id
        and vim.api.nvim_win_is_valid(diff_window.id) then
      if diff_window.file then
        diff_window.file.custom_folds = nil
      end
      vim.api.nvim_win_call(diff_window.id, function()
        if vim.wo.foldmethod == 'manual' then
          pcall(vim.cmd, 'normal! zE')
        end
      end)
      local ordinary_fold_options = {
        foldenable = true,
        foldlevel = 0,
        foldmethod = 'diff',
      }
      if type(diff_window.use_winopts) == 'function' then
        diff_window:use_winopts(ordinary_fold_options)
      else
        for option_name, option_value in pairs(ordinary_fold_options) do
          vim.wo[diff_window.id][option_name] = option_value
        end
      end
    end
  end
end

-- Generic post-render landing for every history kind: when the opener supplied a
-- cursor target, an explicit open of the traced file places the AFTER-pane cursor
-- on it. The target decides its own scope; the pipeline stays kind-agnostic.
local function apply_history_cursor_target(view, file)
  local history_options = view.git_history_options or {}
  local cursor_target = history_options.cursor_target
  if not cursor_target then
    return
  end
  local structure = cursor_target.structure
  local hint_line = cursor_target.line or (structure and structure.first_line)
  if not hint_line then
    return
  end
  -- Only the traced file carries the jump; other files in the same commit
  -- render at their native position.
  local opened_path = file and (file.path or file.oldpath)
  if cursor_target.path and opened_path and opened_path ~= cursor_target.path then
    return
  end
  local current_layout = view.cur_layout
  local after_window = current_layout and current_layout.b
  local window_id = after_window and after_window.id
  if not window_id or not vim.api.nvim_win_is_valid(window_id) then
    return
  end
  -- Stale-render guard: the AFTER pane must show the file being finalized.
  -- (layout.b.file is a revision File, not the panel's FileEntry — compare paths.)
  local after_file = after_window.file
  local after_path = after_file and (after_file.path or after_file.oldpath)
  if after_path and opened_path and after_path ~= opened_path then
    return
  end
  local target_buffer = vim.api.nvim_win_get_buf(window_id)
  local line_count = vim.api.nvim_buf_line_count(target_buffer)
  if line_count == 0 then
    return
  end
  local declaration_line
  if structure then
    local treesitter_context = require('config.syntax.treesitter_context')
    if type(treesitter_context.match_declaration_line) == 'function' then
      declaration_line = treesitter_context.match_declaration_line(target_buffer, structure)
    end
  end
  local target_line = math.max(1, math.min(declaration_line or hint_line, line_count))
  pcall(vim.api.nvim_win_set_cursor, window_id, { target_line, 0 })
  pcall(vim.api.nvim_win_call, window_id, function()
    vim.cmd('normal! zvzz')
  end)
end

complete_history_readiness = function(view, detail)
  local lifecycle_state = lifecycle.get(view)
  if not lifecycle_state then
    return false
  end
  local was_initializing = lifecycle_state.initializing
  if not lifecycle.try_ready(view, detail) then
    return false
  end
  update_history_panel_winbar(view)
  if was_initializing then
    local scope_name = view.git_history_kind == 'symbol' and 'symbol'
      or view.git_history_kind == 'file' and 'file'
      or 'commit'
    local selected_commit = view.git_history_options
      and view.git_history_options.selected_commit
    local render_notice = selected_commit
        and ('Git history: selected commit %s rendered'):format(selected_commit:sub(1, 12))
      or ('Git history: newest %s match rendered'):format(scope_name)
    vim.notify(render_notice, vim.log.levels.INFO)
  end
  if lifecycle_state.return_requested then
    show_return_wait(view, 'ready; press <C-q> to return')
  end
  finish_history_render(view, true, detail)
  return true
end

finalize_history_file_render = function(view, file, reason)
  if not file then
    return false
  end
  local lifecycle_state = lifecycle.get(view)
  local render_sequence = file.git_lifecycle_render_sequence
  if lifecycle_state and not render_sequence then
    local commit_hash, file_path = history_render_identity(view, file)
    render_sequence = lifecycle.begin_render(view, commit_hash, file_path, reason)
    file.git_lifecycle_render_sequence = render_sequence
  end
  -- Line-range (-L) history ships Diffview's patch-hunk folds; swap them for
  -- ordinary full-file folds so the code pane behaves like a normal buffer.
  if (view.git_history_options or {}).range then
    restore_ordinary_history_folds(view.cur_layout)
  end
  pcall(vim.cmd, 'redraw')
  if not lifecycle_state then
    finish_history_render(view, true, reason)
    return true
  end
  local commit_hash, file_path = history_render_identity(view, file)
  if not lifecycle.complete_render(
      view,
      render_sequence,
      commit_hash,
      file_path,
      true
    ) then
    return false
  end
  local readiness_completed = complete_history_readiness(view, reason)
  -- Cursor landing is independent of the readiness transition: the view usually
  -- reaches 'ready' with an empty layout, long before any explicit file open.
  apply_history_cursor_target(view, file)
  return readiness_completed
end

local function suppress_implicit_history_buffers(view, file)
  local file_layout = file and file.layout
  local revision_files = file_layout
      and type(file_layout.files) == 'function'
      and file_layout:files()
    or {}
  local suppressed_buffers = {}
  for _, revision_file in ipairs(revision_files) do
    suppressed_buffers[#suppressed_buffers + 1] = {
      file = revision_file,
      was_nulled = revision_file.nulled,
    }
    revision_file.nulled = true
  end
  view.git_implicit_suppressed_buffers = suppressed_buffers
end

local function restore_implicit_history_buffers(view)
  local suppressed_buffers = view.git_implicit_suppressed_buffers or {}
  view.git_implicit_suppressed_buffers = nil
  for _, suppressed_buffer in ipairs(suppressed_buffers) do
    local revision_file = suppressed_buffer.file
    revision_file.nulled = suppressed_buffer.was_nulled
    if type(revision_file.dispose_buffer) == 'function' then
      revision_file:dispose_buffer()
    else
      revision_file.bufnr = nil
    end
  end
end

local function attach_history_behavior(view, history_kind)
  local behavior_generation = lifecycle.generation(view)
  view.emitter:on('file_open_pre', function(_, file)
    if behavior_generation
        and not lifecycle.callback_is_current(
          view,
          behavior_generation,
          'file_open_pre',
          file and (file.path or file.oldpath) or 'no file'
        ) then
      return
    end
    local granted_file = view.git_explicit_file_open
    view.git_explicit_file_open = nil
    local explicit_file_open = granted_file ~= nil
      and (granted_file == true or granted_file == file)
    local commit_hash, file_path = history_render_identity(view, file)
    local lifecycle_state = lifecycle.get(view)
    -- Diffview auto-selects a file while streaming its list (and once more from a
    -- trailing throttled render after the list settles). History panes stay empty
    -- until an explicit open grants a one-shot render token.
    local implicit_file = file
      and not explicit_file_open
      and not view.git_diff_opened
    if implicit_file then
      view.git_implicit_history_file = file
      if type(file.set_active) == 'function' then
        file:set_active(false)
      else
        file.active = false
      end
      suppress_implicit_history_buffers(view, file)
      if lifecycle_state and lifecycle_state.initializing then
        local warm_up_sequence = lifecycle.begin_render(
          view,
          commit_hash,
          file_path,
          'Diffview file_open_pre'
        )
        if file then
          file.git_lifecycle_render_sequence = warm_up_sequence
        end
      end
      return
    end
    if lifecycle_state and not lifecycle_state.initializing then
      view.git_diff_opened = true
    end
    if view.git_diff_opened then
      lifecycle.expect_target(view, commit_hash, file_path, 'explicit history file open')
    end
    local render_sequence = lifecycle.begin_render(
      view,
      commit_hash,
      file_path,
      'Diffview file_open_pre'
    )
    if file then
      file.git_lifecycle_render_sequence = render_sequence
    end
  end)
  view.emitter:on('file_open_post', function(_, file)
    if behavior_generation
        and not lifecycle.callback_is_current(
          view,
          behavior_generation,
          'file_open_post',
          file and (file.path or file.oldpath) or 'no file'
        ) then
      return
    end
    local implicit_initial_file = view.git_implicit_history_file == file
    if implicit_initial_file then
      view.git_implicit_history_file = nil
      restore_implicit_history_buffers(view)
      clear_history_render_winbars(view)
      local implicit_state = lifecycle.get(view)
      if implicit_state and implicit_state.initializing then
        local implicit_commit_hash, implicit_file_path = history_render_identity(view, file)
        local implicit_render_sequence = file and file.git_lifecycle_render_sequence
        if implicit_render_sequence then
          lifecycle.complete_render(
            view,
            implicit_render_sequence,
            implicit_commit_hash,
            implicit_file_path,
            false
          )
        end
        lifecycle.try_ready(view, 'waiting for the initial history list')
      else
        -- A spurious auto-open that arrived after initialization (Diffview's trailing
        -- throttled stream render). Diffview's own open flow still holds a reference
        -- to the selection, so retire it only after that flow settles.
        local implicit_entry = history_entry_for_file(view, file)
        local retire_generation = lifecycle.generation(view)
        vim.schedule(function()
          if retire_generation
              and not lifecycle.is_current(view, retire_generation) then
            return
          end
          if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
            return
          end
          if view.git_diff_opened then
            return
          end
          if implicit_entry then
            clear_history_diff(view, implicit_entry)
          end
          lifecycle.log(
            view,
            'implicit file open',
            'retired to the empty history layout',
            file and (file.path or file.oldpath) or 'no file',
            'info'
          )
        end)
      end
      return
    end
    protect_view_buffers(view)
    synchronize_history_syntax(view)
    expand_scoped_footer_entry(view, file)
    update_history_winbars(view)
    local lifecycle_state = lifecycle.get(view)
    if lifecycle_state
        and view.git_footer_tree
        and not lifecycle_state.enrichment_ready then
      local commit_hash, file_path = history_render_identity(view, file)
      local render_sequence = file and file.git_lifecycle_render_sequence
      lifecycle.complete_render(
        view,
        render_sequence,
        commit_hash,
        file_path,
        false
      )
      lifecycle.try_ready(view, 'waiting for scoped footer enrichment')
    elseif lifecycle_state then
      local render_sequence = file and file.git_lifecycle_render_sequence
      vim.schedule(function()
        if not lifecycle.callback_is_current(
            view,
            behavior_generation,
            'file render finalization',
            ('seq=%s'):format(tostring(render_sequence))
          ) then
          return
        end
        if view.cur_entry ~= file then
          lifecycle.log(
            view,
            'file render finalization',
            'discarded selection change',
            file and (file.path or file.oldpath) or 'no file',
            'warn'
          )
          return
        end
        finalize_history_file_render(view, file, 'scheduled file_open_post alignment')
      end)
    else
      finalize_history_file_render(view, file, 'file_open_post aligned')
    end
  end)
  view.emitter:on('post_layout', function()
    if behavior_generation
        and not lifecycle.callback_is_current(
          view,
          behavior_generation,
          'post_layout',
          'history layout'
        ) then
      return
    end
    request_footer_decoration(view)
  end)
end

local function attach_history_footer_tracking(view)
  local tracking_generation = lifecycle.generation(view)
  vim.schedule(function()
    if tracking_generation and not lifecycle.is_current(view, tracking_generation) then
      return
    end
    local history_panel = view.panel
    local panel_buffer = history_panel and history_panel.bufid
    if not panel_buffer or not vim.api.nvim_buf_is_valid(panel_buffer) then
      return
    end
    local function entry_at_cursor()
      return type(history_panel.get_log_entry_at_cursor) == 'function'
          and history_panel:get_log_entry_at_cursor()
        or history_panel.cur_item and history_panel.cur_item[1]
        or nil
    end
    local function remember_cursor_entry()
      local cursor_entry = entry_at_cursor()
      local cursor_commit = cursor_entry and cursor_entry.commit
      if cursor_commit and cursor_commit.hash then
        view.git_footer_cursor_hash = cursor_commit.hash
      end
      return cursor_entry
    end
    local function restore_remembered_cursor()
      local remembered_hash = view.git_footer_cursor_hash
      if remembered_hash then
        for _, entry in ipairs(history_panel.entries or {}) do
          local commit = entry.commit
          if commit and commit.hash == remembered_hash then
            restore_history_selection(view, entry)
            break
          end
        end
      end
      request_footer_decoration(view)
    end
    local settled_token
    local function schedule_settled_footer()
      local pending_token = {}
      settled_token = pending_token
      vim.defer_fn(function()
        if settled_token ~= pending_token
            or (tracking_generation and not lifecycle.is_current(view, tracking_generation))
            or not view.tabpage
            or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
          return
        end
        if history_panel.updating
            or history_selection_is_rendering(view)
            or not footer_loader.window_is_settled(view) then
          schedule_settled_footer()
          return
        end
        local pending_commit = view.git_pending_review_focus
        if pending_commit then
          for _, entry in ipairs(history_panel.entries or {}) do
            local commit = entry.commit
            if commit and commit.hash == pending_commit then
              finalize_history_metadata_focus(view, entry, pending_commit)
              return
            end
          end
        end
        restore_remembered_cursor()
      end, 30)
    end
    view.git_schedule_footer_settle = schedule_settled_footer
    remember_cursor_entry()
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = panel_buffer,
      callback = function()
        if tracking_generation and lifecycle.is_current(view, tracking_generation) then
          local cursor_entry = remember_cursor_entry()
          update_history_panel_winbar(view)
          update_history_footer_header(view)
          if cursor_entry then
            footer_loader.on_cursor(view, cursor_entry)
          end
        end
      end,
      desc = 'Pin the active Git history branch segment',
      group = vim.api.nvim_create_augroup('ConfigGitHistoryFooter', { clear = false }),
    })
    vim.api.nvim_create_autocmd('WinScrolled', {
      pattern = tostring(history_panel.winid),
      callback = function()
        if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
          return true
        end
        if tracking_generation and lifecycle.is_current(view, tracking_generation) then
          update_history_footer_header(view)
        end
      end,
      desc = 'Refresh the pinned Git history branch line while scrolling',
      group = vim.api.nvim_create_augroup('ConfigGitHistoryFooter', { clear = false }),
    })
    request_footer_decoration(view)
  end)
end

function M.setup()
  if state.configured then
    return
  end
  state.configured = true
  require('diffview').setup({
    enhanced_diff_hl = true,
    view = {
      file_history = {
        layout = 'diff2_horizontal',
        disable_diagnostics = true,
        winbar_info = true,
      },
    },
    file_history_panel = {
      win_config = {
        position = 'bottom',
        height = 10,
        win_opts = {},
      },
    },
    keymaps = {
      view = {
        close_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        ignored_search_repeat_mapping(),
      },
      file_panel = {
        close_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        ignored_search_repeat_mapping(),
      },
      file_history_panel = {
        history_entry_mapping('<cr>'),
        history_entry_mapping('o'),
        history_entry_mapping('l'),
        history_entry_mapping('<2-LeftMouse>'),
        checkout_commit_mapping(),
        commit_details_mapping(),
        load_children_mapping(),
        close_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        ignored_search_repeat_mapping(),
      },
      option_panel = { close_mapping() },
      help_panel = { close_mapping() },
    },
    hooks = {
      diff_buf_read = protect_view_buffer,
      diff_buf_win_enter = protect_view_buffer,
      view_opened = protect_view_buffers,
      view_post_layout = protect_view_buffers,
    },
  })
  require('config.syntax.highlights').apply()
  local protection_group = vim.api.nvim_create_augroup('ConfigGitDiffviewProtection', {
    clear = true,
  })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = protection_group,
    callback = function()
      local view = active_view()
      if view
          and view.tabpage == vim.api.nvim_get_current_tabpage() then
        protect_view_buffer(vim.api.nvim_get_current_buf())
      end
    end,
    desc = 'Protect generated Diffview buffers with Git-mode mappings',
  })
  vim.keymap.set('c', '<CR>', command_line_enter, {
    expr = true,
    desc = 'Protect combined Diffview from partial :q',
  })
end

local function prepare_history_search_options(history_options)
  local search_options = vim.deepcopy(history_options)
  search_options.head_resolution_pending = nil
  search_options.history_ref = nil
  search_options.open_selected_file = nil
  search_options.parent_view = nil
  search_options.revision = nil
  search_options.render_ready_callback = nil
  search_options.anchor_plan = nil
  search_options.fallback_unbounded = nil
  search_options.selected_commit = nil
  search_options.source = nil
  search_options.unbounded = nil
  search_options.preview_commit = nil
  search_options.independent_preview_commit = nil
  search_options.preloaded_history_count = nil
  search_options.preloaded_history_output = nil
  search_options.window_ref = nil
  search_options.window_start_offset = nil
  return search_options
end

local function footer_entry_hash(entry)
  return entry and entry.commit and entry.commit.hash or nil
end

local function update_footer_entry_commit(entry, row)
  local commit = entry.commit
  commit.author = row.author
  commit.hash = row.hash
  commit.ref_names = row.ref_names ~= '' and row.ref_names or nil
  commit.reflog_selector = row.reflog_selector ~= '' and row.reflog_selector or nil
  commit.rel_date = row.rel_date
  commit.subject = row.subject
  entry.git_parent_hashes = vim.deepcopy(row.parent_hashes or {})
end

local function new_footer_placeholder(view, row, path_args)
  local GitCommit = require('diffview.vcs.adapters.git.commit').GitCommit
  local LogEntry = require('diffview.vcs.log_entry').LogEntry
  local commit = GitCommit({
    author = row.author,
    hash = row.hash,
    ref_names = row.ref_names,
    reflog_selector = row.reflog_selector,
    rel_date = row.rel_date,
    subject = row.subject,
    time = row.time,
    time_offset = row.time_offset,
  })
  local entry = LogEntry.new_null_entry(view.adapter, {
    commit = commit,
    path_args = vim.deepcopy(path_args),
    single_file = false,
  })
  -- The null file is a navigation sentinel. Enter is intercepted until the
  -- real entry has loaded, so the sentinel is never rendered as a child.
  entry.nulled = false
  entry.git_details_loaded = false
  entry.git_details_loading = false
  entry.git_target_buffers_warmed = false
  entry.git_target_buffers_warming = false
  entry.git_files_enriched = false
  entry.git_files_enriching = false
  entry.git_parent_hashes = vim.deepcopy(row.parent_hashes or {})
  return entry
end

local function install_footer_rows(view, rows, direction, completion_callback)
  local history_panel = view.panel
  local attempts_remaining = 500
  local function install_when_settled()
    if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      completion_callback(false)
      return
    end
    if history_panel.updating or history_selection_is_rendering(view) then
      attempts_remaining = attempts_remaining - 1
      if attempts_remaining > 0 then
        vim.defer_fn(install_when_settled, 20)
      else
        completion_callback(false)
      end
      return
    end

    local cursor_entry = type(history_panel.get_log_entry_at_cursor) == 'function'
        and history_panel:get_log_entry_at_cursor()
      or nil
    local cursor_hash = footer_entry_hash(cursor_entry)
    local active_entry = history_panel.cur_item and history_panel.cur_item[1]
    local existing_entries = {}
    for _, entry in ipairs(history_panel.entries or {}) do
      local commit_hash = footer_entry_hash(entry)
      if commit_hash then
        existing_entries[commit_hash] = entry
      end
    end

    local path_args = history_panel.log_options
        and history_panel.log_options.single_file
        and history_panel.log_options.single_file.path_args
      or {}
    local installed_entries = {}
    local retained_entries = {}
    for _, row in ipairs(rows) do
      local entry = existing_entries[row.hash]
      if entry then
        retained_entries[entry] = true
        update_footer_entry_commit(entry, row)
        if entry.git_details_loaded == nil then
          -- Diffview can expose its native seed as soon as the first changed
          -- file arrives. Reusing the object preserves selection identity, but
          -- does not prove that the commit's complete file list has settled.
          entry.git_details_loaded = false
          entry.git_details_loading = false
        end
      else
        entry = new_footer_placeholder(view, row, path_args)
      end
      entry.git_independent_preview = view.git_history_options
          and view.git_history_options.independent_preview_commit == row.hash
        or false
      if direction == 'initial' and not view.git_diff_opened then
        entry.folded = true
      end
      installed_entries[#installed_entries + 1] = entry
    end

    local retired_entries = view.git_footer_retired_entries or {}
    view.git_footer_retired_entries = retired_entries
    for _, entry in ipairs(history_panel.entries or {}) do
      if not retained_entries[entry] then
        if view.git_diff_opened and entry == active_entry then
          retired_entries[#retired_entries + 1] = entry
        elseif type(entry.destroy) == 'function' then
          entry:destroy()
        end
      end
    end

    history_panel.entries = installed_entries
    history_panel.single_file = false
    local retained_cursor_entry = installed_entries[1]
    for _, entry in ipairs(installed_entries) do
      local commit_hash = footer_entry_hash(entry)
      if commit_hash == cursor_hash then
        retained_cursor_entry = entry
        break
      end
    end
    if not (view.git_diff_opened and retained_entries[active_entry]) then
      history_panel.cur_item = retained_cursor_entry and { retained_cursor_entry, nil } or {}
    end
    prepare_scoped_footer_entries(view, installed_entries)
    mark_detached_head_entry(view)
    if type(history_panel.update_components) == 'function' then
      history_panel:update_components()
    end
    if type(history_panel.render) == 'function' then
      history_panel:render()
    end
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
    restore_history_selection(view, retained_cursor_entry)
    completion_callback(true, retained_cursor_entry)
  end
  install_when_settled()
end

local function footer_detail_revisions(entry)
  local GitRev = require('diffview.vcs.adapters.git.rev').GitRev
  local RevType = require('diffview.vcs.rev').RevType
  local parent_hashes = entry.git_parent_hashes or {}
  local parent_hash = parent_hashes[1] or GitRev.NULL_TREE_SHA
  return GitRev(RevType.COMMIT, parent_hash), GitRev(RevType.COMMIT, footer_entry_hash(entry))
end

local function warm_scoped_target_buffers(view, entry, completion_callback)
  if not view.git_footer_tree then
    completion_callback(true)
    return
  end
  local target_file = entry.git_target_file
  local target_layout = target_file and target_file.layout
  if not target_layout or type(target_layout.files) ~= 'function' then
    completion_callback(true)
    return
  end
  local revision_files = target_layout:files() or {}
  local revision_index = 1
  entry.git_target_buffers_warming = true
  local function finish_warming()
    entry.git_target_buffers_warming = false
    entry.git_target_buffers_warmed = true
    completion_callback(true)
  end
  local function warm_next_revision()
    if entry.git_details_loading == false then
      entry.git_target_buffers_warming = false
      completion_callback(false)
      return
    end
    local revision_file = revision_files[revision_index]
    revision_index = revision_index + 1
    if not revision_file then
      finish_warming()
      return
    end
    local validity_checked, buffer_is_valid = pcall(
      revision_file.is_valid,
      revision_file
    )
    if revision_file.nulled or (validity_checked and buffer_is_valid) then
      warm_next_revision()
      return
    end
    if type(revision_file.create_buffer) ~= 'function' then
      warm_next_revision()
      return
    end
    local creation_started = pcall(
      revision_file.create_buffer,
      revision_file,
      warm_next_revision
    )
    if not creation_started then
      warm_next_revision()
    end
  end
  warm_next_revision()
end

local function finish_footer_detail(view, entry, loaded_files, completion_callback)
  local fallback_path = view.git_history_options
    and view.git_history_options.location
    and view.git_history_options.location.relative_path
  local scoped_paths = target_paths(nil, fallback_path)
  local _, obsolete_files = replace_entry_files(entry, loaded_files, scoped_paths)
  entry.nulled = false
  entry.single_file = false
  entry.git_files_enriched = true
  destroy_history_files(obsolete_files)

  mark_detached_head_entry(view)
  warm_scoped_target_buffers(view, entry, function(buffers_ready)
    entry.git_details_loaded = buffers_ready
    completion_callback(buffers_ready)
  end)
end

local function finish_empty_footer_detail(entry, completion_callback)
  entry.git_details_loaded = true
  entry.git_files_enriched = true
  entry.nulled = true
  completion_callback(true)
end

schedule_footer_detail_render = function(view, fallback_entry)
  if view.git_footer_detail_render_token then
    return false
  end
  local render_token = {
    fallback_entry = fallback_entry,
    generation = lifecycle.generation(view),
  }
  view.git_footer_detail_render_token = render_token
  vim.defer_fn(function()
    if view.git_footer_detail_render_token ~= render_token then
      return
    end
    view.git_footer_detail_render_token = nil
    if active_view() ~= view
        or not view.tabpage
        or not vim.api.nvim_tabpage_is_valid(view.tabpage)
        or (render_token.generation
          and not lifecycle.is_current(view, render_token.generation)) then
      return
    end
    local history_panel = view.panel
    if not history_panel or history_panel.updating or history_selection_is_rendering(view) then
      schedule_footer_detail_render(view, render_token.fallback_entry)
      return
    end
    if type(history_panel.update_components) == 'function' then
      history_panel:update_components()
    end
    if type(history_panel.render) == 'function' then
      history_panel:render()
    end
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
    local retained_entry = render_token.fallback_entry
    local remembered_hash = view.git_footer_cursor_hash
    if remembered_hash then
      for _, entry in ipairs(history_panel.entries or {}) do
        local commit = entry.commit
        if commit and commit.hash == remembered_hash then
          retained_entry = entry
          break
        end
      end
    end
    restore_history_selection(view, retained_entry)
    request_footer_decoration(view)
  end, 80)
  return true
end

local function hydrate_footer_entry(view, entry, completion_callback)
  local vcs_utils = require('diffview.vcs.utils')
  local detail_token = { cancelled = false }
  local left_revision, right_revision = footer_detail_revisions(entry)
  local request_started = pcall(
    vcs_utils.diff_file_list,
    view.adapter,
    left_revision,
    right_revision,
    {},
    { show_untracked = false },
    history_layout_options(view),
    function(errors, file_dictionary)
      local loaded_files = file_dictionary and file_dictionary.working or {}
      vim.schedule(function()
        if detail_token.cancelled
          or active_view() ~= view
          or not view.tabpage
          or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
          destroy_history_files(loaded_files)
          return
        end
        if errors then
          destroy_history_files(loaded_files)
          completion_callback(false)
          return
        end
        if #loaded_files == 0 then
          finish_empty_footer_detail(entry, completion_callback)
          return
        end
        finish_footer_detail(view, entry, loaded_files, completion_callback)
      end)
    end
  )
  if not request_started then
    vim.schedule(function()
      if not detail_token.cancelled then
        completion_callback(false)
      end
    end)
  end
  return function()
    detail_token.cancelled = true
  end
end

local function batch_footer_files(view, entry, detail_rows)
  local FileEntry = require('diffview.scene.file_entry').FileEntry
  local left_revision, right_revision = footer_detail_revisions(entry)
  local default_layout = history_layout_options(view).default_layout
  local loaded_files = {}
  for _, detail_row in ipairs(detail_rows) do
    loaded_files[#loaded_files + 1] = FileEntry.with_layout(default_layout, {
      adapter = view.adapter,
      commit = entry.commit,
      kind = 'working',
      oldpath = detail_row.original_path,
      path = detail_row.path,
      revs = {
        a = left_revision,
        b = right_revision,
      },
      stats = detail_row.stats,
      status = detail_row.status,
    })
  end
  return loaded_files
end

local function hydrate_footer_entries(view, entries, completion_callback)
  local commit_hashes = {}
  for _, entry in ipairs(entries) do
    commit_hashes[#commit_hashes + 1] = footer_entry_hash(entry)
  end
  local batch_token = {
    cancelled = false,
    process_cancellations = {},
    fallback_cancel = nil,
  }
  local completed_processes = {}
  local function finish_with_fallback()
    local fallback_results = {}
    local fallback_index = 1
    local function hydrate_next_entry()
      if batch_token.cancelled then
        return
      end
      local fallback_entry = entries[fallback_index]
      fallback_index = fallback_index + 1
      if not fallback_entry then
        completion_callback(fallback_results)
        return
      end
      batch_token.fallback_cancel = hydrate_footer_entry(
        view,
        fallback_entry,
        function(succeeded)
          batch_token.fallback_cancel = nil
          fallback_results[fallback_entry] = succeeded == true
          hydrate_next_entry()
        end
      )
    end
    hydrate_next_entry()
  end
  local function finish_batch()
    if batch_token.cancelled
        or not completed_processes.name_status
        or not completed_processes.numstat then
      return
    end
    local name_status_process = completed_processes.name_status
    local numstat_process = completed_processes.numstat
    if name_status_process.code ~= 0 or numstat_process.code ~= 0 then
      finish_with_fallback()
      return
    end
    local details_by_hash = repository.parse_history_details(
      name_status_process.stdout,
      numstat_process.stdout
    )
    local batch_results = {}
    local entry_index = 1
    local function install_next_entry()
      if batch_token.cancelled then
        return
      end
      local entry = entries[entry_index]
      entry_index = entry_index + 1
      if not entry then
        completion_callback(batch_results)
        return
      end
      local commit_hash = footer_entry_hash(entry)
      local detail_rows = details_by_hash[commit_hash]
      if not detail_rows then
        batch_token.fallback_cancel = hydrate_footer_entry(view, entry, function(succeeded)
          batch_token.fallback_cancel = nil
          batch_results[entry] = succeeded == true
          install_next_entry()
        end)
        return
      end
      local loaded_files = batch_footer_files(view, entry, detail_rows)
      if #loaded_files == 0 then
        finish_empty_footer_detail(entry, function(succeeded)
          batch_results[entry] = succeeded == true
          install_next_entry()
        end)
        return
      end
      finish_footer_detail(view, entry, loaded_files, function(succeeded)
        batch_results[entry] = succeeded == true
        install_next_entry()
      end)
    end
    install_next_entry()
  end
  for _, output_kind in ipairs({ 'name_status', 'numstat' }) do
    local command_kind = output_kind == 'name_status' and 'name-status' or 'numstat'
    local cancel_process = repository.start(
      repository.commands.history_detail_rows(commit_hashes, command_kind),
      view.git_repository_root,
      function(completed_process)
        if batch_token.cancelled then
          return
        end
        completed_processes[output_kind] = completed_process
        finish_batch()
      end
    )
    batch_token.process_cancellations[#batch_token.process_cancellations + 1] = cancel_process
  end
  return function()
    if batch_token.cancelled then
      return
    end
    batch_token.cancelled = true
    for _, cancel_process in ipairs(batch_token.process_cancellations) do
      cancel_process()
    end
    if batch_token.fallback_cancel then
      batch_token.fallback_cancel()
      batch_token.fallback_cancel = nil
    end
  end
end

local function release_footer_entries(view, released_entries)
  local FileEntry = require('diffview.scene.file_entry').FileEntry
  local history_panel = view.panel
  local cursor_entry = type(history_panel.get_log_entry_at_cursor) == 'function'
      and history_panel:get_log_entry_at_cursor()
    or nil
  for _, entry in ipairs(released_entries) do
    destroy_history_files(entry.files)
    entry.files = { FileEntry.new_null_entry(view.adapter) }
    entry.folded = true
    entry.nulled = false
    entry.single_file = false
    entry.git_details_loaded = false
    entry.git_details_loading = false
    entry.git_target_buffers_warmed = false
    entry.git_target_buffers_warming = false
    entry.git_files_enriched = false
    entry.git_files_enriching = false
    entry.git_target_file = nil
    if type(entry.update_status) == 'function' then
      entry:update_status()
    end
    if type(entry.update_stats) == 'function' then
      entry:update_stats()
    end
  end
  if #released_entries > 0 then
    history_panel:update_components()
    history_panel:render()
    history_panel:redraw()
    restore_history_selection(view, cursor_entry)
    request_footer_decoration(view)
  end
end

local function attach_footer_loader(view, history_options)
  local attached = footer_loader.attach(view, history_options, {
    activity = function(active_history_view, activity_name, activity_label)
      if activity_label then
        lifecycle.set_activity(active_history_view, activity_name, activity_label)
      else
        lifecycle.clear_activity(active_history_view, activity_name)
      end
      update_history_panel_winbar(active_history_view)
    end,
    failed = function(active_history_view, request_kind, request_error)
      lifecycle.log(
        active_history_view,
        request_kind,
        'failed',
        request_error,
        'warn'
      )
      vim.notify('Could not load Git ' .. request_kind .. ': ' .. request_error, vim.log.levels.WARN)
    end,
    details_settled = function(active_history_view)
      local history_panel = active_history_view.panel
      local cursor_entry = type(history_panel.get_log_entry_at_cursor) == 'function'
          and history_panel:get_log_entry_at_cursor()
        or history_panel.cur_item and history_panel.cur_item[1]
        or nil
      schedule_footer_detail_render(active_history_view, cursor_entry)
    end,
    hydrate_entry = hydrate_footer_entry,
    hydrate_entries = hydrate_footer_entries,
    install_rows = install_footer_rows,
    list_ready = function(active_history_view, center_entry, entry_count)
      M.adapt_history_footer(active_history_view)
      lifecycle.log(
        active_history_view,
        'commit list window',
        'complete',
        ('entries=%d'):format(entry_count),
        'info'
      )
    end,
    list_updated = function(active_history_view, direction, added_count, entry_count)
      M.adapt_history_footer(active_history_view)
      lifecycle.log(
        active_history_view,
        'commit list window ' .. direction,
        'complete',
        ('added=%d entries=%d'):format(added_count, entry_count),
        'info'
      )
    end,
    release_entries = release_footer_entries,
  })
  if view.git_history_options then
    view.git_history_options.preloaded_history_output = nil
  end
  return attached
end

function M.set_history_activity(view, activity_name, label)
  if not lifecycle.is_current(view, lifecycle.generation(view)) then
    return false
  end
  local activity_changed = lifecycle.set_activity(view, activity_name, label)
  if activity_changed then
    update_history_panel_winbar(view)
    pcall(vim.cmd, 'redraw')
  end
  return activity_changed
end

function M.attach_history_head_request(view, cancel_resolution)
  if not lifecycle.is_current(view, lifecycle.generation(view)) then
    if type(cancel_resolution) == 'function' then
      pcall(cancel_resolution)
    end
    return false
  end
  view.git_cancel_head_resolution = cancel_resolution
  return true
end

function M.finish_history_head_request(view)
  if not lifecycle.is_current(view, lifecycle.generation(view)) then
    return false
  end
  view.git_cancel_head_resolution = nil
  lifecycle.clear_activity(view, 'head')
  update_history_panel_winbar(view)
  return true
end

function M.apply_history_context(view, options)
  local history_options = vim.deepcopy(options or {})
  if not M.finish_history_head_request(view) then
    return false
  end
  history_options.head_resolution_pending = nil
  history_options.render_ready_callback = nil
  view.git_anchor_plan = vim.deepcopy(history_options.anchor_plan)
  view.git_result_source = history_options.source
  view.git_branch_name = history_options.branch_name
  view.git_checked_out_branch = history_options.checked_out_branch
  view.git_detached_head_commit = history_options.detached_head_commit
  view.git_history_ref = history_options.history_ref
  view.git_review_tip_commit = history_options.branch_tip_commit
  view.git_history_options = history_options
  view.git_search_options = prepare_history_search_options(history_options)
  attach_footer_loader(view, history_options)
  M.adapt_history_footer(view)
  return true
end

function M.open_file_history(options)
  ensure_loaded()
  local history_options = options or {}
  if state.closing then
    vim.defer_fn(function()
      M.open_file_history(history_options)
    end, 50)
    return
  end
  local location = history_options.location
  if not location then
    vim.notify('Diffview history requires a repository location', vim.log.levels.INFO)
    return
  end

  local history_args = {
    '-C' .. location.root,
  }
  history_args[#history_args + 1] = '--max-count=' .. footer_loader.initial_limit(history_options)
  local initial_history_ref = footer_loader.initial_ref(history_options)
  if initial_history_ref then
    history_args[#history_args + 1] = '--range=' .. initial_history_ref
  elseif history_options.revision then
    history_args[#history_args + 1] = '--range=' .. history_options.revision .. '^!'
  end
  if history_options.kind == 'file' then
    history_args[#history_args + 1] = '--follow'
    history_args[#history_args + 1] = location.relative_path
  elseif history_options.kind == 'symbol' then
    history_args[#history_args + 1] = location.relative_path
  end
  local view = require('diffview.lib').file_history(history_options.range, history_args)
  if not view then
    return
  end
  state.repository_root = location.root
  view.git_repository_root = location.root
  view.git_anchor_plan = vim.deepcopy(history_options.anchor_plan)
  view.git_result_source = history_options.source
  view.git_history_kind = history_options.kind
  view.git_footer_tree = history_options.kind == 'file' or history_options.kind == 'symbol'
  view.git_footer_enriching = view.git_footer_tree
  view.git_diff_opened = false
  view.git_history_options = vim.deepcopy(history_options)
  view.git_history_options.render_ready_callback = nil
  view.git_branch_name = history_options.branch_name
  view.git_checked_out_branch = history_options.checked_out_branch
  view.git_detached_head_commit = history_options.detached_head_commit
  view.git_history_ref = history_options.history_ref
  view.git_review_tip_commit = history_options.branch_tip_commit
  view.git_render_ready_callback = history_options.render_ready_callback
  view.git_search_options = prepare_history_search_options(history_options)
  view.git_parent_view = history_options.parent_view
  if not history_options.parent_view then
    state.root_view = view
  end
  lifecycle.attach(view, history_options.kind)
  lifecycle.transition(view, 'listing', 'history open', location.relative_path or location.root)
  local history_scope = history_options.kind == 'symbol' and 'symbol matches'
    or history_options.kind == 'file' and 'file commits'
    or 'repository commits'
  lifecycle.set_activity(view, 'history', history_scope)
  if history_options.head_resolution_pending then
    lifecycle.set_activity(view, 'head', 'current branch')
  end
  vim.notify(('Git history: loading %s'):format(history_scope), vim.log.levels.INFO)
  attach_history_behavior(view, history_options.kind)
  view:open()
  attach_footer_loader(view, history_options)
  update_history_panel_winbar(view)
  pcall(vim.cmd, 'redraw')
  attach_history_footer_tracking(view)
  synchronize_history_footer(view)
  if history_options.parent_view then
    panel.enter_search(view, function()
      M.return_to_previous_git_panel()
    end)
  else
    panel.enter_git(view, function()
      M.return_to_editor_line()
    end)
  end
  if history_options.selected_commit then
    local remaining_attempts = 1500
    local selection_generation = lifecycle.generation(view)
    local function select_when_ready()
      if selection_generation
          and not lifecycle.is_current(view, selection_generation) then
        return
      end
      if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
        finish_history_render(view, false, 'replacement view closed before selection')
        return
      end
      if M.focus_history_commit(view, history_options.selected_commit, {
          open_file = history_options.open_selected_file == true,
        }) then
        return
      end
      local history_panel = view.panel
      remaining_attempts = remaining_attempts - 1
      local settled_list_lacks_commit = lifecycle.is_ready(view)
        and footer_loader.window_is_settled(view)
        and history_panel
        and not history_panel.updating
        and not history_selection_is_rendering(view)
      if settled_list_lacks_commit then
        -- The complete list already settled without the commit; polling a
        -- settled list cannot produce it.
        remaining_attempts = 0
      end
      if remaining_attempts > 0 then
        vim.defer_fn(select_when_ready, 20)
      else
        vim.notify(
          ('Commit %s is not present in the rendered history'):format(
            history_options.selected_commit:sub(1, 12)
          ),
          vim.log.levels.INFO
        )
        finish_history_render(view, false, 'selected commit missing from rendered history')
      end
    end
    vim.defer_fn(select_when_ready, 20)
  end
  return view
end

function M.replace_file_history(previous_view, history_options)
  if not previous_view
      or not previous_view.tabpage
      or not vim.api.nvim_tabpage_is_valid(previous_view.tabpage) then
    return false
  end
  local replacement_options = vim.deepcopy(history_options or {})
  replacement_options.parent_view = nil
  local requested_render_callback = replacement_options.render_ready_callback
  replacement_options.render_ready_callback = function(replacement_view, render_succeeded, detail)
    lifecycle.mark_closing(previous_view, 'replacement history rendered')
    dispose_rendered_view(previous_view, function()
      lifecycle.mark_disposed(previous_view, 'replacement history retired')
      if requested_render_callback then
        requested_render_callback(replacement_view, render_succeeded, detail)
      end
    end)
  end
  local replacement_view = M.open_file_history(replacement_options)
  if not replacement_view then
    return false
  end
  footer_loader.detach(previous_view)
  cancel_history_footer_enrichment(previous_view)
  cancel_history_head_resolution(previous_view)
  return true
end

function M.open_selected_history(previous_view, history_options)
  local selected_options = vim.deepcopy(history_options or {})
  local history_location = selected_options.location
  local repository_root = history_location and history_location.root
  if not repository_root or not selected_options.selected_commit then
    return false
  end

  selected_options.unbounded = nil
  cancel_pending_history_request()
  local request_finished = false
  local cancel_request = footer_loader.prepare_selected(
    repository_root,
    selected_options,
    function(prepared_options)
      request_finished = true
      state.pending_history_request_cancel = nil
      local mount_succeeded
      if previous_view then
        mount_succeeded = M.replace_file_history(previous_view, prepared_options)
      else
        mount_succeeded = M.open_file_history(prepared_options) ~= nil
      end
      if not mount_succeeded and prepared_options.render_ready_callback then
        prepared_options.render_ready_callback(
          previous_view,
          false,
          'failed to mount prepared history'
        )
      end
    end
  )
  if not request_finished then
    state.pending_history_request_cancel = cancel_request
  end
  return true
end

highlight_history_entry = function(history_panel, entry)
  if type(history_panel.highlight_item) == 'function' then
    history_panel:highlight_item(entry)
  end
  restore_history_cursor(history_panel, entry)
end

finalize_history_metadata_focus = function(view, entry, commit_hash)
  local history_panel = view and view.panel
  if not history_panel or view.git_pending_review_focus ~= commit_hash then
    return false
  end
  if entry.folded == false then
    entry.folded = true
    if type(history_panel.update_components) == 'function' then
      history_panel:update_components()
    end
    if type(history_panel.render) == 'function' then
      history_panel:render()
    end
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
  end
  clear_history_diff(view, entry)
  history_panel.cur_item = { entry, nil }
  highlight_history_entry(history_panel, entry)
  local panel_window = history_panel.winid
  if panel_window and vim.api.nvim_win_is_valid(panel_window) then
    vim.api.nvim_set_current_win(panel_window)
  end
  view.git_footer_cursor_hash = commit_hash
  view.git_pending_review_focus = nil
  view.git_review_ready = true
  request_footer_decoration(view)
  lifecycle.mark_idle_ready(view, 'selected commit metadata focused')
  finish_history_render(view, true, 'selected commit metadata focused')
  return true
end

function M.focus_history_commit(view, commit_hash, options)
  local focus_options = options or {}
  local history_panel = view and view.panel
  if not history_panel
      or history_panel.updating
      or history_selection_is_rendering(view) then
    return false
  end
  for _, entry in ipairs(history_panel.entries or {}) do
    if entry.commit and entry.commit.hash == commit_hash then
      if focus_options.open_file == false then
        view.git_review_target = commit_hash
        view.git_review_ready = false
        view.git_pending_review_focus = commit_hash
        if type(view.git_schedule_footer_settle) == 'function' then
          view.git_schedule_footer_settle()
        else
          finalize_history_metadata_focus(view, entry, commit_hash)
        end
        return true
      end
      if entry.git_details_loaded == false then
        local active_hydration = view.git_review_hydration
        if active_hydration
            and not active_hydration.cancelled
            and active_hydration.commit_hash == commit_hash then
          return true
        end
        if active_hydration then
          active_hydration.cancelled = true
        end
        local hydration_token = {
          cancelled = false,
          commit_hash = commit_hash,
          generation = lifecycle.generation(view),
        }
        view.git_review_hydration = hydration_token
        view.git_review_target = commit_hash
        view.git_review_ready = false
        footer_loader.ensure_entry(view, entry, function(details_loaded)
          if hydration_token.cancelled or view.git_review_hydration ~= hydration_token then
            return
          end
          view.git_review_hydration = nil
          if hydration_token.generation
              and not lifecycle.is_current(view, hydration_token.generation) then
            return
          end
          if not details_loaded then
            if view.git_render_ready_callback and lifecycle.get(view) then
              lifecycle.mark_failed(view, 'selected commit details did not load')
            end
            finish_history_render(view, false, 'selected commit details did not load')
            return
          end
          if not M.focus_history_commit(view, commit_hash, focus_options) then
            finish_history_render(view, false, 'selected commit disappeared after detail load')
          end
        end)
        return true
      end
      local target_file = entry.git_target_file or (entry.files and entry.files[1])
      local current_item = history_panel.cur_item
      local current_entry = current_item and current_item[1]
      local current_file = current_item and current_item[2]
      local target_path = target_file and (target_file.path or target_file.oldpath)
      lifecycle.expect_target(view, commit_hash, target_path, 'focused history commit')
      view.git_review_target = commit_hash
      view.git_review_ready = false
      local review_generation = lifecycle.generation(view)
      local review_completed = false
      local unsubscribe_ready
      local function finish_review(render_succeeded, detail)
        if review_completed then
          return
        end
        review_completed = true
        if unsubscribe_ready then
          unsubscribe_ready()
        end
        view.git_review_ready = render_succeeded
        finish_history_render(view, render_succeeded, detail)
      end
      if current_entry == entry
          and current_file == target_file
          and lifecycle.render_is_ready(view) then
        highlight_history_entry(history_panel, entry)
        finish_review(true, 'selected commit already rendered')
        return true
      end
      if entry.nulled
          and type(history_panel.set_cur_item) == 'function'
          and view.cur_layout
          and type(view.cur_layout.open_null) == 'function' then
        if type(view.cur_layout.detach_files) == 'function' then
          view.cur_layout:detach_files()
        end
        view.cur_layout:open_null()
        view.nulled = true
        view.git_diff_opened = false
        history_panel:set_cur_item({ entry, target_file })
        if type(history_panel.render) == 'function' then
          history_panel:render()
        end
        if type(history_panel.redraw) == 'function' then
          history_panel:redraw()
        end
        highlight_history_entry(history_panel, entry)
        lifecycle.mark_empty_ready(view, 'selected empty commit rendered')
        finish_review(true, 'empty commit rendered')
        return true
      end
      if review_generation then
        unsubscribe_ready = events.on('ready', function(payload)
          if payload.generation ~= review_generation
              or view.git_review_target ~= commit_hash
              or not history_panel.cur_item
              or history_panel.cur_item[1] ~= entry
              or not lifecycle.render_is_ready(view) then
            return
          end
          highlight_history_entry(history_panel, entry)
          finish_review(true, 'selected commit rendered')
        end)
      end
      if (current_entry ~= entry or current_file ~= target_file)
          and target_file
          and type(view.set_file) == 'function' then
        view.git_diff_opened = true
        view.git_explicit_file_open = target_file
        view:set_file(target_file, false)
      elseif type(history_panel.set_cur_item) == 'function' then
        history_panel:set_cur_item({ entry, target_file })
      end
      if current_entry == entry
          and current_file == target_file
          and target_file
          and review_generation then
        vim.schedule(function()
          if lifecycle.callback_is_current(
              view,
              review_generation,
              'focused commit render',
              commit_hash
            ) then
            finalize_history_file_render(view, target_file, 'focused current commit')
          end
        end)
      elseif not review_generation then
        highlight_history_entry(history_panel, entry)
        finish_review(true, 'selected commit rendered without lifecycle')
      end
      vim.defer_fn(function()
        if review_completed then
          return
        end
        if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
          finish_review(false, 'replacement view closed during diff render')
          return
        end
        if view.git_review_target ~= commit_hash
            or not history_panel.cur_item
            or history_panel.cur_item[1] ~= entry then
          finish_review(false, 'selection changed during diff render')
          return
        end
        lifecycle.log(
          view,
          'focused commit render',
          'timed out',
          commit_hash,
          'error'
        )
        lifecycle.mark_failed(view, 'selected commit diff did not settle')
        finish_review(false, 'selected commit diff did not settle')
      end, 10000)
      return true
    end
  end
  return false
end

function M.open_search_commit(parent_view, history_options, commit)
  local parent_options = history_options or {}
  local parent_location = parent_options.location or {}
  local repository_root = parent_location.root or (parent_view and parent_view.git_repository_root)
  if not repository_root then
    return false
  end
  if parent_view then
    request_footer_decoration(parent_view)
  end
  if M.focus_history_commit(parent_view, commit.hash, { open_file = false }) then
    M.adapt_history_footer(parent_view)
    return true
  end
  local checked_out_branch = parent_options.checked_out_branch
  local detached_head_commit = parent_options.detached_head_commit
  if parent_view then
    checked_out_branch = parent_view.git_checked_out_branch
    detached_head_commit = parent_view.git_detached_head_commit
  end
  local review_options = {
    anchor_plan = commit.anchor_plan,
    branch_name = commit.branch_name,
    branch_tip_commit = commit.anchor_plan and commit.anchor_plan.branch_tip_commit,
    checked_out_branch = checked_out_branch,
    detached_head_commit = detached_head_commit,
    history_ref = commit.history_ref or commit.branch_name,
    kind = 'repository',
    location = { root = repository_root },
    preview_commit = commit.hash,
    require_checked_out_containment = true,
    review_only = true,
    selected_commit = commit.hash,
    source = commit.source,
  }
  return M.open_selected_history(parent_view, review_options)
end

function M.jump_to_search_commit(parent_view, history_options, commit)
  return M.open_search_commit(parent_view, history_options, commit)
end

return M
