local repository = require('config.git.repository')
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
  repository_root = nil,
  root_view = nil,
  settled_actions = {},
}
local decorate_history_footer

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

local function close_mapping()
  return {
    'n',
    panel.close_key,
    M.handle_ctrl_q,
    { desc = 'Close current Git panel layer' },
  }
end

local function history_selection_is_rendering(view)
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

local function select_scoped_entry_target(view, entry)
  local pending_target = view and view.git_pending_scoped_target
  local request_generation = pending_target and pending_target.generation
  local request_is_current = view
    and active_view() == view
    and entry
    and pending_target
    and pending_target.entry == entry
    and not entry.folded
    and scoped_entry_is_still_selected(view, entry)
    and (not request_generation or lifecycle.is_current(view, request_generation))
  if not request_is_current then
    if view then
      view.git_pending_scoped_target = nil
    end
    return false
  end
  if history_selection_is_rendering(view) then
    lifecycle.log(
      view,
      'scoped commit expansion',
      'waiting for current diff render',
      entry.commit and entry.commit.hash or nil,
      'info'
    )
    return false
  end
  local target_file = entry.git_target_file
  if not target_file or type(view.set_file) ~= 'function' then
    view.git_pending_scoped_target = nil
    return false
  end
  view.git_pending_scoped_target = nil
  lifecycle.log(
    view,
    'scoped commit expansion',
    'selecting target file',
    target_file.path or target_file.oldpath,
    'info'
  )
  view:set_file(target_file, false)
  return true
end

local function resume_pending_scoped_target(view)
  local pending_target = view and view.git_pending_scoped_target
  if not pending_target then
    return
  end
  vim.schedule(function()
    if view.git_pending_scoped_target ~= pending_target then
      return
    end
    select_scoped_entry_target(view, pending_target.entry)
  end)
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
  local expanded_entry = view
      and view.git_footer_tree
      and cursor_item
      and cursor_item.files
      and cursor_item.folded
      and cursor_item
    or nil
  require('diffview.actions').select_entry()
  vim.schedule(function()
    if not view
        or active_view() ~= view
        or not view.tabpage
        or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      return
    end
    if expanded_entry and not expanded_entry.folded then
      view.git_pending_scoped_target = {
        entry = expanded_entry,
        generation = lifecycle.generation(view),
      }
      select_scoped_entry_target(view, expanded_entry)
    end
    if decorate_history_footer then
      decorate_history_footer(view)
    end
  end)
end

local function history_entry_mapping(key)
  return { 'n', key, select_history_entry, { desc = 'Open selected Git history entry' } }
end

local function history_entry_for_file(view, file)
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
  local history_panel = view and view.panel
  if not history_panel or not view.git_repository_root then
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
  local cancel_enrichment = view and view.git_cancel_footer_enrichment
  if type(cancel_enrichment) == 'function' then
    cancel_enrichment()
  elseif view then
    view.git_footer_enrichment_token = nil
    view.git_footer_enriching = false
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
      if view.git_editor_alignment_pending then
        lifecycle.mark_aligning(view, 'Diffview disposed; editor target is stable')
      else
        lifecycle.mark_disposed(view, 'Diffview disposed')
      end
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
    cancel_history_footer_enrichment(closing_view)
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
    cancel_history_footer_enrichment(view)
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
  local layout = view.cur_layout
  local cursor_window = layout and layout.b
  if not cursor_window
      or not cursor_window.id
      or not vim.api.nvim_win_is_valid(cursor_window.id) then
    return nil, 'waiting for the rendered AFTER pane'
  end
  local target_path = vim.fs.normalize(view.cur_entry.absolute_path)
  if vim.fn.filereadable(target_path) ~= 1 then
    return nil, 'rendered AFTER file is absent from the working tree'
  end
  local cursor = vim.api.nvim_win_get_cursor(cursor_window.id)
  local cursor_buffer = vim.api.nvim_win_get_buf(cursor_window.id)
  local declaration
  local structure
  local structure_resolved = pcall(function()
    structure = require('config.syntax.treesitter_context').enclosing_structure(
      cursor_buffer,
      cursor[1] - 1,
      cursor[2]
    )
  end)
  if structure_resolved and structure and structure.first_line then
    local declaration_text = vim.api.nvim_buf_get_lines(
      cursor_buffer,
      structure.first_line - 1,
      structure.first_line,
      false
    )[1]
    if declaration_text and vim.trim(declaration_text) ~= '' then
      local definition_parser = require('config.search.workspace_symbols')
      local parsed_definition = type(definition_parser.definition) == 'function'
          and definition_parser.definition(target_path, declaration_text)
        or nil
      declaration = {
        label = structure.label,
        node_type = structure.node_type,
        relative_line = math.max(0, cursor[1] - structure.first_line),
        symbol_kind = parsed_definition and parsed_definition.kind or nil,
        symbol_name = parsed_definition and parsed_definition.name or nil,
        text = declaration_text,
      }
    end
  end
  return {
    column = cursor[2],
    declaration = declaration,
    line = cursor[1],
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

local function normalized_declaration(source_line)
  return vim.trim(source_line):gsub('%s+', ' ')
end

local function structure_at_declaration(buffer, candidate_line)
  local candidate_source = vim.api.nvim_buf_get_lines(
    buffer,
    candidate_line - 1,
    candidate_line,
    false
  )[1] or ''
  local first_nonblank_byte = candidate_source:find('%S')
  local candidate_column = first_nonblank_byte and first_nonblank_byte - 1 or 0
  local candidate_structure
  local structure_resolved = pcall(function()
    candidate_structure = require('config.syntax.treesitter_context').enclosing_structure(
      buffer,
      candidate_line - 1,
      candidate_column
    )
  end)
  if structure_resolved
      and candidate_structure
      and candidate_structure.first_line == candidate_line then
    return candidate_structure
  end
end

local function declaration_identity_matches(buffer, candidate_line, declaration)
  if not declaration.label or declaration.label == '' then
    return false
  end
  local candidate_structure = structure_at_declaration(buffer, candidate_line)
  return candidate_structure
    and candidate_structure.label == declaration.label
    and (
      not declaration.node_type
      or candidate_structure.node_type == declaration.node_type
    )
end

local function unique_identity_line(buffer, candidate_lines, declaration)
  local identified_line
  for _, candidate_line in ipairs(candidate_lines) do
    if declaration_identity_matches(buffer, candidate_line, declaration) then
      if identified_line then
        return
      end
      identified_line = candidate_line
    end
  end
  return identified_line
end

local function matched_declaration_line(buffer, filename, declaration)
  if not declaration or not declaration.text then
    return
  end
  local expected_text = normalized_declaration(declaration.text)
  if expected_text == '' then
    return
  end
  local matching_lines = {}
  for line_number, source_line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
    if normalized_declaration(source_line) == expected_text then
      matching_lines[#matching_lines + 1] = line_number
    end
  end
  if #matching_lines == 1 then
    return matching_lines[1]
  end
  local exact_identity_line = unique_identity_line(buffer, matching_lines, declaration)
  if exact_identity_line then
    return exact_identity_line
  end
  if not declaration.symbol_name or not declaration.symbol_kind then
    return
  end

  local definition_parser = require('config.search.workspace_symbols')
  if type(definition_parser.definition) ~= 'function' then
    return
  end
  local symbol_lines = {}
  for line_number, source_line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
    local parsed_definition = definition_parser.definition(filename, source_line)
    if parsed_definition
        and parsed_definition.name == declaration.symbol_name
        and parsed_definition.kind == declaration.symbol_kind then
      symbol_lines[#symbol_lines + 1] = line_number
      if #symbol_lines > 1 and not declaration.label then
        return
      end
    end
  end
  if #symbol_lines == 1 then
    return symbol_lines[1]
  end
  return unique_identity_line(buffer, symbol_lines, declaration)
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

local function rendered_editor_target_is_current(rendered_target)
  return vim.api.nvim_tabpage_is_valid(rendered_target.tabpage)
    and vim.api.nvim_win_is_valid(rendered_target.window)
    and vim.api.nvim_buf_is_valid(rendered_target.buffer)
    and vim.api.nvim_get_current_tabpage() == rendered_target.tabpage
    and vim.api.nvim_get_current_win() == rendered_target.window
    and vim.api.nvim_win_get_buf(rendered_target.window) == rendered_target.buffer
end

local function jump_to_rendered_editor_target(view, rendered_target)
  if not rendered_editor_target_is_current(rendered_target) then
    lifecycle.log(view, 'editor alignment', 'cancelled', 'editor target changed', 'warn')
    return false
  end
  local target = rendered_target.target
  local line_count = vim.api.nvim_buf_line_count(rendered_target.buffer)
  local declaration_target_line = matched_declaration_line(
    rendered_target.buffer,
    target.path,
    target.declaration
  )
  local declaration_relative_line = target.declaration
      and target.declaration.relative_line
    or 0
  local aligned_declaration_line = declaration_target_line
      and declaration_target_line + declaration_relative_line
    or nil
  local matched_structure = declaration_target_line
      and structure_at_declaration(rendered_target.buffer, declaration_target_line)
    or nil
  local alignment_last_line = matched_structure
      and matched_structure.last_line
    or line_count
  local target_line = aligned_declaration_line
      and math.max(1, math.min(aligned_declaration_line, alignment_last_line, line_count))
    or math.max(1, math.min(target.line, line_count))
  local source_line = vim.api.nvim_buf_get_lines(
    rendered_target.buffer,
    target_line - 1,
    target_line,
    false
  )[1] or ''
  local target_column = math.max(0, math.min(target.column, #source_line))
  local alignment_succeeded, alignment_error = pcall(
    vim.api.nvim_win_call,
    rendered_target.window,
    function()
      vim.api.nvim_win_set_cursor(rendered_target.window, { target_line, target_column })
      vim.cmd('normal! zvzz')
    end
  )
  if not alignment_succeeded then
    lifecycle.log(view, 'editor alignment', 'failed', tostring(alignment_error), 'error')
    vim.notify(('Editor cursor alignment failed: %s'):format(alignment_error), vim.log.levels.ERROR)
    return false
  end
  local redraw_succeeded, redraw_error = pcall(vim.cmd, 'redraw')
  if not redraw_succeeded then
    lifecycle.log(view, 'editor alignment redraw', 'failed', tostring(redraw_error), 'error')
    vim.notify(('Editor cursor redraw failed: %s'):format(redraw_error), vim.log.levels.ERROR)
    return false
  end
  lifecycle.log(
    view,
    'editor alignment',
    declaration_target_line and 'matched declaration' or 'used file line fallback',
    ('line=%d column=%d'):format(target_line, target_column),
    'info'
  )
  local completion_message = 'Git return: editor cursor aligned'
  vim.notify(completion_message, vim.log.levels.INFO)
  vim.defer_fn(function()
    pcall(vim.api.nvim_echo, {}, false, {})
  end, 1200)
  return true
end

local function prepare_history_editor_target(view, target)
  if not target or vim.fn.filereadable(target.path) ~= 1 then
    return
  end
  local editing_tabpage = editing_tab_for_view(view)
  if not editing_tabpage or not vim.api.nvim_tabpage_is_valid(editing_tabpage) then
    return
  end

  local editor_window = vim.api.nvim_tabpage_get_win(editing_tabpage)
  if not editor_window or not vim.api.nvim_win_is_valid(editor_window) then
    return
  end
  local target_buffer
  for _, editor_tab_window in ipairs(vim.api.nvim_tabpage_list_wins(editing_tabpage)) do
    local editor_buffer = vim.api.nvim_win_get_buf(editor_tab_window)
    local editor_buffer_path = vim.api.nvim_buf_get_name(editor_buffer)
    if editor_buffer_path ~= '' and vim.fs.normalize(editor_buffer_path) == target.path then
      editor_window = editor_tab_window
      target_buffer = editor_buffer
      break
    end
  end
  if not target_buffer then
    local existing_buffer = vim.fn.bufnr(target.path)
    target_buffer = existing_buffer > 0 and existing_buffer or vim.fn.bufadd(target.path)
  end
  if not target_buffer or target_buffer < 1 or not vim.api.nvim_buf_is_valid(target_buffer) then
    return
  end
  if not vim.api.nvim_buf_is_loaded(target_buffer) then
    local load_succeeded = pcall(vim.fn.bufload, target_buffer)
    if not load_succeeded or not vim.api.nvim_buf_is_loaded(target_buffer) then
      return
    end
  end
  local stage_succeeded = pcall(vim.api.nvim_win_set_buf, editor_window, target_buffer)
  if not stage_succeeded or vim.api.nvim_win_get_buf(editor_window) ~= target_buffer then
    return
  end
  local select_succeeded = pcall(
    vim.api.nvim_tabpage_set_win,
    editing_tabpage,
    editor_window
  )
  if not select_succeeded then
    return
  end
  restore_editor_mappings(target_buffer)
  refresh_editor_branch(editor_window)
  return {
    buffer = target_buffer,
    tabpage = editing_tabpage,
    target = target,
    window = editor_window,
  }
end

local function render_history_editor_target(rendered_target)
  if not rendered_target
      or vim.api.nvim_get_current_tabpage() ~= rendered_target.tabpage
      or vim.api.nvim_get_current_win() ~= rendered_target.window
      or vim.api.nvim_win_get_buf(rendered_target.window) ~= rendered_target.buffer then
    refresh_editor_branch()
    return false
  end
  restore_editor_mappings(rendered_target.buffer)
  local render_succeeded, render_error = pcall(vim.cmd, 'redraw')
  if not render_succeeded then
    vim.notify(tostring(render_error), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.return_to_editor_line()
  local view = active_view()
  if not M.is_active() then
    return false
  end
  if view and lifecycle.get(view)
      and not lifecycle.request_return(view, 'Ctrl-Q from ordinary Git history') then
    view.git_return_requested = true
    show_return_wait(view, 'waiting for the current Git render')
    vim.notify('Git exit: waiting for the current Git render', vim.log.levels.INFO)
    return false
  end
  cancel_history_footer_enrichment(view)
  if view then
    view.git_return_requested = false
    lifecycle.log(view, 'exit target capture', 'started', 'editor restore has priority', 'info')
  end
  local editor_target, target_error = history_editor_target(view)
  if not editor_target then
    local target_pending = vim.startswith(target_error, 'waiting for')
    if view and target_pending then
      view.git_return_requested = true
      show_return_wait(view, target_error)
      lifecycle.log(view, 'exit target capture', 'waiting', target_error, 'info')
      return false
    end
    local branch_prepared = prime_editor_branch(view)
    return M.close(function()
      restore_editor_mappings(vim.api.nvim_get_current_buf())
      if not branch_prepared then
        refresh_editor_branch()
      end
      pcall(vim.cmd, 'redraw')
    end)
  end
  view.git_return_requested = false
  local rendered_target = prepare_history_editor_target(view, editor_target)
  if not rendered_target then
    local branch_prepared = prime_editor_branch(view)
    return M.close(function()
      restore_editor_mappings(vim.api.nvim_get_current_buf())
      if not branch_prepared then
        refresh_editor_branch()
      end
      pcall(vim.cmd, 'redraw')
    end)
  end
  view.git_editor_alignment_pending = true
  show_return_wait(view, 'restoring editor; cursor alignment follows render')
  vim.notify('Git exit: restoring editor before cursor alignment', vim.log.levels.INFO)
  local editor_render_succeeded = false
  return M.close(function()
    editor_render_succeeded = render_history_editor_target(rendered_target)
    lifecycle.log(
      view,
      'editor render',
      editor_render_succeeded and 'complete' or 'failed',
      rendered_target.target.path,
      editor_render_succeeded and 'info' or 'error'
    )
    events.emit('editor_rendered', {
      generation = lifecycle.generation(view),
      path = rendered_target.target.path,
      rendered = editor_render_succeeded,
    })
  end, function()
    if rendered_editor_target_is_current(rendered_target) then
      refresh_editor_branch(rendered_target.window)
      pcall(vim.cmd, 'redrawstatus')
      if editor_render_succeeded then
        vim.schedule(function()
          jump_to_rendered_editor_target(view, rendered_target)
          view.git_editor_alignment_pending = false
          lifecycle.mark_disposed(view, 'editor alignment callback completed')
        end)
      else
        view.git_editor_alignment_pending = false
        lifecycle.mark_disposed(view, 'editor render failed; alignment skipped')
      end
    else
      view.git_editor_alignment_pending = false
      lifecycle.mark_disposed(view, 'editor target changed before alignment')
    end
  end)
end

local function refresh_pending_editor_return(view)
  if not view.git_return_requested then
    return
  end
  vim.schedule(function()
    if view.git_return_requested
        and active_view() == view
        and panel.level() == 'git' then
      local editor_target, target_error = history_editor_target(view)
      local return_status
      if editor_target and lifecycle.is_ready(view) then
        return_status = 'ready; press <C-q> to return'
      else
        return_status = target_error or 'waiting for the current Git render'
      end
      show_return_wait(view, return_status)
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
  local source_highlight = source == 'REMOTE'
      and 'GitHistoryRemoteTag'
    or 'GitHistoryLocalTag'
  local chunks = {}
  local function add_divider()
    if #chunks > 0 then
      chunks[#chunks + 1] = { ' │ ', 'GitHistorySectionDivider' }
    end
  end
  local branch_name = view.git_branch_name
  if branch_name and branch_name ~= '' then
    local branch_role = history_options.review_only and 'BRANCH REVIEW' or 'BRANCH'
    chunks[#chunks + 1] = {
      (' REVIEW · %s · %s '):format(source, branch_role),
      source_highlight,
    }
    chunks[#chunks + 1] = { branch_name, 'DiffviewFilePanelTitle' }
    local review_tip_commit = view.git_review_tip_commit
    if review_tip_commit and review_tip_commit ~= '' then
      add_divider()
      chunks[#chunks + 1] = { ' TIP · ', 'GitHistoryReviewTag' }
      chunks[#chunks + 1] = { review_tip_commit:sub(1, 12), 'DiffviewHash' }
    end
  else
    chunks[#chunks + 1] = { (' SOURCE · %s '):format(source), source_highlight }
  end
  add_divider()
  chunks[#chunks + 1] = { ' SCOPE · ', 'GitHistoryScopeTag' }
  chunks[#chunks + 1] = { scope_label(view) .. ' ', 'DiffviewFilePanelTitle' }
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
    'GitHistoryCurrentTag',
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
  for entry_index, entry in ipairs(history_panel.entries or {}) do
    local component_structure = entry_component_for(history_panel, entry)
    local commit_component = component_structure and component_structure.commit
      and component_structure.commit.comp
    local reference_branches = branch_names_from_references(
      entry.commit and entry.commit.ref_names
    )
    if #reference_branches > 0 then
      active_branch_label = table.concat(reference_branches, ' · ')
    elseif entry_index == 1 and view.git_branch_name then
      active_branch_label = view.git_branch_name
    end
    entry.git_branch_segment = active_branch_label
    if commit_component and commit_component.lstart >= 0 and #reference_branches > 0 then
      local commit_row = commit_component.lstart
      segments[#segments + 1] = { label = active_branch_label, row = commit_row }
      vim.api.nvim_buf_set_extmark(panel_buffer, footer_annotation_namespace, commit_row, 0, {
        virt_lines = {
          { { ('── BRANCH · %s '):format(active_branch_label), 'DiffviewReference' } },
        },
        virt_lines_above = true,
      })
    elseif commit_component
        and commit_component.lstart >= 0
        and entry_index == 1
        and active_branch_label then
      segments[#segments + 1] = { label = active_branch_label, row = commit_component.lstart }
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
          { (' MATCH · %s '):format((view.git_history_kind or 'file'):upper()), 'DiffviewReference' },
        },
        virt_text_pos = 'right_align',
      }
      if basename_start then
        target_mark_options.end_col = basename_column + #target_basename
        target_mark_options.end_row = target_row
        target_mark_options.hl_group = 'DiffviewReference'
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
  decorate_history_footer(view)
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

function M.enrich_history_footer(view)
  local history_panel = view and view.panel
  local entries = history_panel and history_panel.entries or {}
  if not view
      or not view.git_footer_tree
      or not history_panel
      or not view.adapter then
    if view then
      view.git_footer_enriching = false
    end
    return false
  end
  mark_detached_head_entry(view)

  local utilities_loaded, vcs_utils = pcall(require, 'diffview.vcs.utils')
  if not utilities_loaded or type(vcs_utils.diff_file_list) ~= 'function' then
    view.git_footer_enriching = false
    return false
  end

  cancel_history_footer_enrichment(view)
  local enrichment_token = {}
  local enrichment_generation = lifecycle.generation(view)
  view.git_footer_enrichment_token = enrichment_token
  view.git_footer_enriching = true
  local selected_entry = history_panel.cur_item and history_panel.cur_item[1] or entries[1]
  local fallback_path = view.git_history_options
    and view.git_history_options.location
    and view.git_history_options.location.relative_path
  local layout_options = history_layout_options(view)
  local obsolete_files = {}
  local failed_entries = 0
  local entry_index = 1
  local enrichment_cancelled = false

  local function cancel_enrichment()
    if enrichment_cancelled then
      return
    end
    enrichment_cancelled = true
    if view.git_footer_enrichment_token == enrichment_token then
      view.git_footer_enrichment_token = nil
      view.git_footer_enriching = false
      view.git_cancel_footer_enrichment = nil
    end
    local cancelled_files = obsolete_files
    obsolete_files = {}
    destroy_history_files(cancelled_files)
  end

  view.git_cancel_footer_enrichment = cancel_enrichment

  local function enrichment_is_current()
    local token_is_current = not enrichment_cancelled
      and view.git_footer_enrichment_token == enrichment_token
      and view.tabpage
      and vim.api.nvim_tabpage_is_valid(view.tabpage)
    if not token_is_current then
      return false
    end
    if enrichment_generation == nil or lifecycle.is_current(view, enrichment_generation) then
      return true
    end
    lifecycle.log(
      view,
      'callback footer enrichment',
      'discarded stale',
      ('entry=%d/%d'):format(math.min(entry_index, #entries), #entries),
      'warn'
    )
    return false
  end

  local function finish_enrichment()
    if not enrichment_is_current() then
      return
    end
    view.git_footer_enriching = false
    view.git_cancel_footer_enrichment = nil
    history_panel.single_file = false
    for _, entry in ipairs(entries) do
      entry.single_file = false
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
    decorate_history_footer(view)
    local newest_entry = entries[1]
    local newest_file = newest_entry
      and (newest_entry.git_target_file or (newest_entry.files and newest_entry.files[1]))
    local newest_commit = newest_entry and newest_entry.commit and newest_entry.commit.hash
    local newest_path = newest_file and (newest_file.path or newest_file.oldpath)
    if newest_entry and type(history_panel.highlight_item) == 'function' then
      history_panel:highlight_item(newest_entry)
    elseif selected_entry and type(history_panel.highlight_item) == 'function' then
      history_panel:highlight_item(selected_entry)
    end
    if lifecycle.get(view) then
      lifecycle.mark_enrichment_ready(view, newest_commit, newest_path)
      lifecycle.log(
        view,
        'footer redraw',
        'complete',
        ('entries=%d failed=%d'):format(#entries, failed_entries),
        failed_entries > 0 and 'warn' or 'info'
      )
      if newest_file then
        local rendered_file = view.cur_entry
        local rendered_commit, rendered_path = history_render_identity(view, rendered_file)
        if rendered_commit == newest_commit and rendered_path == newest_path then
          vim.schedule(function()
            if lifecycle.callback_is_current(
                view,
                enrichment_generation,
                'post-enrichment alignment',
                newest_commit .. ':' .. newest_path
              ) then
              finalize_history_file_render(view, rendered_file, 'footer enrichment complete')
            end
          end)
        elseif type(view.set_file) == 'function' then
          lifecycle.log(
            view,
            'newest match render',
            'requested',
            ('rendered=%s:%s expected=%s:%s'):format(
              rendered_commit or 'none',
              rendered_path or 'none',
              newest_commit or 'none',
              newest_path or 'none'
            ),
            'info'
          )
          lifecycle.expect_target(view, newest_commit, newest_path, 'newest scoped match')
          view:set_file(newest_file, false)
        end
      else
        lifecycle.mark_empty_ready(view, 'scoped history has no matches')
        finish_history_render(view, true, 'empty scoped history rendered')
      end
    end
    resume_pending_scoped_target(view)
    local retired_files = obsolete_files
    obsolete_files = {}
    vim.defer_fn(function()
      destroy_history_files(retired_files)
    end, 1000)
    if failed_entries > 0 then
      vim.notify(
        ('Could not expand complete file lists for %d Git history entries'):format(
          failed_entries
        ),
        vim.log.levels.WARN
      )
    end
  end

  local enrich_next_entry
  enrich_next_entry = function()
    if not enrichment_is_current() then
      return
    end
    local entry = entries[entry_index]
    entry_index = entry_index + 1
    if not entry then
      finish_enrichment()
      return
    end
    local seed_file = entry.files and entry.files[1]
    local revisions = seed_file and seed_file.revs
    if not revisions or not revisions.a or not revisions.b then
      failed_entries = failed_entries + 1
      enrich_next_entry()
      return
    end
    local scoped_paths = target_paths(seed_file, fallback_path)
    vcs_utils.diff_file_list(
      view.adapter,
      revisions.a,
      revisions.b,
      {},
      { show_untracked = false },
      layout_options,
      function(errors, file_dictionary)
        vim.schedule(function()
          if not enrichment_is_current() then
            local stale_files = file_dictionary and file_dictionary.working or {}
            destroy_history_files(stale_files)
            return
          end
          local full_files = file_dictionary and file_dictionary.working or {}
          if errors or #full_files == 0 then
            failed_entries = failed_entries + 1
          else
            local _, replaced_files = replace_entry_files(entry, full_files, scoped_paths)
            vim.list_extend(obsolete_files, replaced_files)
            lifecycle.log(
              view,
              'footer entry enrichment',
              'complete',
              ('entry=%d/%d commit=%s files=%d'):format(
                entry_index - 1,
                #entries,
                entry.commit and entry.commit.hash or 'none',
                #full_files
              ),
              'info'
            )
          end
          enrich_next_entry()
        end)
      end
    )
  end

  enrich_next_entry()
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
    if history_panel and history_panel.updating then
      remaining_attempts = remaining_attempts - 1
      if remaining_attempts > 0 then
        vim.defer_fn(synchronize, 20)
      else
        lifecycle.log(view, 'history list settle', 'timed out', nil, 'error')
        finish_history_render(view, false, 'history list did not settle')
      end
    else
      local entries = history_panel and history_panel.entries or {}
      local selected_commit = view.git_history_options.selected_commit
      if selected_commit then
        for _, entry in ipairs(entries) do
          if entry.commit and entry.commit.hash == selected_commit then
            local selected_file = entry.git_target_file or (entry.files and entry.files[1])
            local selected_path = selected_file and (selected_file.path or selected_file.oldpath)
            lifecycle.expect_target(
              view,
              selected_commit,
              selected_path,
              'requested commit review'
            )
            break
          end
        end
      end
      lifecycle.mark_list_ready(view, #entries)
      if #entries == 0 then
        lifecycle.mark_empty_ready(view, 'empty history rendered')
        finish_history_render(view, true, 'empty history rendered')
      elseif view.git_footer_tree then
        vim.notify(
          ('Git history: preparing %d matching commits'):format(#entries),
          vim.log.levels.INFO
        )
        M.enrich_history_footer(view)
      else
        M.adapt_history_footer(view)
        complete_history_readiness(view, 'history list settled')
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
  decorate_history_footer(view)
end

local function is_scoped_target_file(view, file)
  local history_options = view.git_history_options or {}
  local location = history_options.location or {}
  local target_path = location.relative_path
  if not target_path or not file then
    return false
  end
  return file.path == target_path or file.oldpath == target_path
end

local function changed_line(hunk, side)
  local content_key = side == 'old' and 'old_content' or 'new_content'
  local row_key = side == 'old' and 'old_row' or 'new_row'
  local changed_content = hunk[content_key]
  local first_change = changed_content and changed_content[1]
  if first_change then
    return hunk[row_key] + first_change[1] - 1
  end
  return hunk[row_key]
end

local function declaration_line(buffer, candidate_line)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return candidate_line
  end
  local line_count = vim.api.nvim_buf_line_count(buffer)
  local bounded_line = math.max(1, math.min(candidate_line, line_count))
  local source_line = vim.api.nvim_buf_get_lines(buffer, bounded_line - 1, bounded_line, false)[1]
    or ''
  local first_nonblank_byte = source_line:find('%S')
  local source_column = first_nonblank_byte and first_nonblank_byte - 1 or 0
  local structure
  local structure_resolved = pcall(function()
    structure = require('config.syntax.treesitter_context').enclosing_structure(
      buffer,
      bounded_line - 1,
      source_column
    )
  end)
  if structure_resolved and structure then
    return structure.first_line
  end
  return bounded_line
end

local function reveal_modified_scope(window, candidate_line, focus_definition)
  if not window
      or not window.id
      or not vim.api.nvim_win_is_valid(window.id)
      or not window.file
      or not window.file.bufnr then
    return
  end
  local definition_line = declaration_line(window.file.bufnr, candidate_line)
  local line_count = vim.api.nvim_buf_line_count(window.file.bufnr)
  local changed_line_number = math.max(1, math.min(candidate_line, line_count))
  vim.api.nvim_win_call(window.id, function()
    vim.api.nvim_win_set_cursor(window.id, { definition_line, 0 })
    vim.cmd('normal! zv')
    local focus_line = focus_definition and definition_line or changed_line_number
    vim.api.nvim_win_set_cursor(window.id, { focus_line, 0 })
    vim.cmd('normal! zvzz')
  end)
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

local function reveal_changed_structure(view, file, focus_definition)
  local panel_item = view.panel and view.panel.cur_item
  local log_entry = panel_item and panel_item[1]
  local traced_diff = log_entry and log_entry:get_diff(file.path)
  local first_hunk = traced_diff and traced_diff.hunks and traced_diff.hunks[1]
  local layout = view.cur_layout
  if not first_hunk or not layout then
    return
  end

  local left_line = changed_line(first_hunk, 'old')
  local right_line = changed_line(first_hunk, 'new')
  if first_hunk.new_size == 0 then
    reveal_modified_scope(layout.b, right_line, focus_definition)
    reveal_modified_scope(layout.a, left_line, focus_definition)
  else
    reveal_modified_scope(layout.a, left_line, focus_definition)
    reveal_modified_scope(layout.b, right_line, focus_definition)
  end
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
  if view.git_history_kind == 'symbol' then
    restore_ordinary_history_folds(view.cur_layout)
  end
  local focus_target_symbol = view.git_history_kind == 'symbol'
    and is_scoped_target_file(view, file)
  reveal_changed_structure(view, file, focus_target_symbol)
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
  return complete_history_readiness(view, reason)
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
    local commit_hash, file_path = history_render_identity(view, file)
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
    protect_view_buffers(view)
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
        refresh_pending_editor_return(view)
      end)
    else
      finalize_history_file_render(view, file, 'file_open_post aligned')
    end
    resume_pending_scoped_target(view)
    refresh_pending_editor_return(view)
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
    decorate_history_footer(view)
    refresh_pending_editor_return(view)
  end)
end

local function attach_history_footer_tracking(view)
  local tracking_generation = lifecycle.generation(view)
  vim.schedule(function()
    local history_panel = view.panel
    local panel_buffer = history_panel and history_panel.bufid
    if not panel_buffer or not vim.api.nvim_buf_is_valid(panel_buffer) then
      return
    end
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = panel_buffer,
      callback = function()
        if tracking_generation and lifecycle.is_current(view, tracking_generation) then
          update_history_panel_winbar(view)
          update_history_footer_header(view)
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
    decorate_history_footer(view)
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
  if not history_options.unbounded then
    history_args[#history_args + 1] = '--max-count=' .. repository.max_history_entries
  end
  if history_options.history_ref then
    history_args[#history_args + 1] = '--range=' .. history_options.history_ref
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
  view.git_history_options = vim.deepcopy(history_options)
  view.git_history_options.render_ready_callback = nil
  view.git_branch_name = history_options.branch_name
  view.git_checked_out_branch = history_options.checked_out_branch
  view.git_detached_head_commit = history_options.detached_head_commit
  view.git_history_ref = history_options.history_ref
  view.git_review_tip_commit = history_options.branch_tip_commit
  view.git_render_ready_callback = history_options.render_ready_callback
  local search_options = vim.deepcopy(history_options)
  search_options.detached_head_commit = nil
  search_options.history_ref = nil
  search_options.parent_view = nil
  search_options.revision = nil
  search_options.render_ready_callback = nil
  search_options.anchor_plan = nil
  search_options.selected_commit = nil
  search_options.source = nil
  search_options.unbounded = nil
  view.git_search_options = search_options
  view.git_parent_view = history_options.parent_view
  if not history_options.parent_view then
    state.root_view = view
  end
  lifecycle.attach(view, history_options.kind)
  lifecycle.transition(view, 'listing', 'history open', location.relative_path or location.root)
  local history_scope = history_options.kind == 'symbol' and 'symbol matches'
    or history_options.kind == 'file' and 'file commits'
    or 'repository commits'
  vim.notify(('Git history: loading %s'):format(history_scope), vim.log.levels.INFO)
  attach_history_behavior(view, history_options.kind)
  view:open()
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
    local function select_when_ready()
      if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
        finish_history_render(view, false, 'replacement view closed before selection')
        return
      end
      if M.focus_history_commit(view, history_options.selected_commit) then
        return
      end
      remaining_attempts = remaining_attempts - 1
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
  cancel_history_footer_enrichment(previous_view)
  return true
end

local function highlight_history_entry(history_panel, entry)
  if type(history_panel.highlight_item) == 'function' then
    history_panel:highlight_item(entry)
  end
  local entry_components = history_panel.components
    and history_panel.components.log
    and history_panel.components.log.entries
  if not entry_components
      or not history_panel.winid
      or not vim.api.nvim_win_is_valid(history_panel.winid) then
    return
  end
  for _, component_structure in ipairs(entry_components) do
    if component_structure.comp.context == entry then
      pcall(vim.api.nvim_win_set_cursor, history_panel.winid, {
        component_structure.comp.lstart + 1,
        0,
      })
      return
    end
  end
end

function M.focus_history_commit(view, commit_hash)
  local history_panel = view and view.panel
  if not history_panel
      or history_panel.updating
      or history_selection_is_rendering(view) then
    return false
  end
  for _, entry in ipairs(history_panel.entries or {}) do
    if entry.commit and entry.commit.hash == commit_hash then
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
  if M.focus_history_commit(parent_view, commit.hash) then
    return true
  end
  return M.replace_file_history(parent_view, {
    anchor_plan = commit.anchor_plan,
    branch_name = commit.branch_name,
    branch_tip_commit = commit.anchor_plan and commit.anchor_plan.branch_tip_commit,
    checked_out_branch = parent_view and parent_view.git_checked_out_branch,
    detached_head_commit = parent_view and parent_view.git_detached_head_commit,
    history_ref = commit.history_ref or commit.branch_name or commit.hash,
    kind = 'repository',
    location = { root = repository_root },
    review_only = true,
    selected_commit = commit.hash,
    source = commit.source,
    unbounded = true,
  })
end

function M.jump_to_search_commit(parent_view, history_options, commit)
  return M.open_search_commit(parent_view, history_options, commit)
end

return M
