local repository = require('config.git.repository')
local panel = require('config.git.panel')

local M = {}
local state = {
  closing = false,
  configured = false,
  pending_view_closes = 0,
  repository_root = nil,
  root_view = nil,
}

local function ensure_loaded()
  if not package.loaded.diffview then
    require('lazy').load({ plugins = { 'diffview.nvim' } })
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

local function return_mapping()
  return { 'n', '<Space>o', M.return_to_inspector, { desc = 'Leave Git history' } }
end

local function search_historical_buffer()
  local view = active_view()
  if not view or not view.cur_layout then
    return
  end
  local current_window = vim.api.nvim_get_current_win()
  local layout = view.cur_layout
  local target_window = layout:get_main_win()
  for _, diff_window in ipairs(layout.windows or {}) do
    if diff_window.id == current_window then
      target_window = diff_window
      break
    end
  end
  if not target_window
      or not target_window.id
      or not vim.api.nvim_win_is_valid(target_window.id)
      or not target_window.file
      or not target_window.file.bufnr
      or not vim.api.nvim_buf_is_valid(target_window.file.bufnr) then
    return
  end
  local phase = target_window == layout.a and 'BEFORE' or 'AFTER'
  require('config.search.workspace_symbols').open_buffer(target_window.file.bufnr, {
    filename = target_window.file.absolute_path,
    root = state.repository_root,
    target_window = target_window.id,
    title = ('%s Commit Definitions'):format(phase),
  })
end

local function historical_search_mapping()
  return {
    'n',
    '<Space>fw',
    search_historical_buffer,
    { desc = 'Search definitions in this historical buffer' },
  }
end

local function select_history_entry()
  local view = active_view()
  local history_panel = view and view.panel
  local selected_item = history_panel
    and type(history_panel.get_item_at_cursor) == 'function'
    and history_panel:get_item_at_cursor()
  if view
      and view.git_footer_tree
      and selected_item
      and selected_item.files
      and type(history_panel.render) == 'function'
      and type(history_panel.redraw) == 'function' then
    selected_item.folded = not selected_item.folded
    history_panel:render()
    history_panel:redraw()
    return
  end
  require('diffview.actions').select_entry()
end

local function history_entry_mapping()
  return { 'n', '<cr>', select_history_entry, { desc = 'Open selected Git history entry' } }
end

local function history_selection_is_rendering(view)
  local history_panel = view and view.panel
  local current_item = history_panel and history_panel.cur_item
  local selected_file = current_item and current_item[2]
  local current_entry = view and view.cur_entry
  return selected_file and (not current_entry or not current_entry.opened) or false
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
  return require('config.git').detach_commit_overview(
    view.git_repository_root,
    commit_hash,
    view,
    {
      branch_name = view.git_branch_name,
      source = view.git_result_source,
    }
  )
end

local function checkout_commit_mapping()
  return {
    'n',
    '<Space>dm',
    M.checkout_selected_commit,
    { desc = 'Checkout selected Git history commit' },
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

local function protect_view_buffer(buffer)
  vim.keymap.set('n', panel.close_key, M.handle_ctrl_q, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Close current Git panel layer',
  })
  vim.keymap.set('n', '<Space>o', M.return_to_inspector, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Leave Git history',
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
  vim.keymap.set('n', '<Space>fw', search_historical_buffer, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Search definitions in this historical buffer',
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
  if history_panel.updating then
    return true
  end
  return history_selection_is_rendering(view)
end

local function focus_editing_tab(view)
  local diffview_lib = package.loaded['diffview.lib']
  local editing_tabpage = diffview_lib
    and type(diffview_lib.get_prev_non_view_tabpage) == 'function'
    and diffview_lib.get_prev_non_view_tabpage()
  if editing_tabpage and vim.api.nvim_tabpage_is_valid(editing_tabpage) then
    vim.api.nvim_set_current_tabpage(editing_tabpage)
    return
  end
  if not view.tabpage
      or not vim.api.nvim_tabpage_is_valid(view.tabpage)
      or view.tabpage ~= vim.api.nvim_get_current_tabpage() then
    return
  end
  local tabpages = vim.api.nvim_list_tabpages()
  for tab_index, tabpage in ipairs(tabpages) do
    if tabpage == view.tabpage then
      local editing_tabpage = tabpages[tab_index - 1] or tabpages[tab_index + 1]
      if editing_tabpage then
        vim.api.nvim_set_current_tabpage(editing_tabpage)
      end
      return
    end
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

local function close_rendering_view(view)
  dispose_rendered_view(view, function()
    state.pending_view_closes = math.max(0, state.pending_view_closes - 1)
    state.closing = state.pending_view_closes > 0
  end)
end

function M.is_active()
  local issue_module = package.loaded['config.git.issue']
  local issue_active = issue_module
    and type(issue_module.is_active) == 'function'
    and issue_module.is_active()
  return active_view() ~= nil or issue_active
end

function M.close()
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
  if focus_view then
    focus_editing_tab(focus_view)
  end
  for _, closing_view in ipairs(closing_views) do
    vim.defer_fn(function()
      close_rendering_view(closing_view)
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
    vim.defer_fn(function()
      close_rendering_view(view)
    end, 0)
    return true
  end
  return M.close()
end

function M.handle_ctrl_q()
  return panel.pop() ~= nil
end

function M.return_to_inspector()
  if not M.is_active() then
    return false
  end
  M.close()
  return true
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

local function escaped_winbar_text(value)
  return value:gsub('%%', '%%%%')
end

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

local function update_history_panel_winbar(view)
  local history_panel = view.panel
  local panel_window = history_panel and history_panel.winid
  if not panel_window
      or not vim.api.nvim_win_is_valid(panel_window) then
    return
  end
  local history_options = view.git_history_options or {}
  local location = history_options.location or {}
  local source = view.git_result_source or 'LOCAL'
  local branch_name = view.git_branch_name
  local scope_prefix
  local scope_detail = ''
  if branch_name and branch_name ~= '' then
    scope_prefix = (' %s · BRANCH · '):format(source)
    scope_detail = branch_name
  elseif history_options.kind == 'symbol' then
    local structure = location.structure or {}
    local structure_label = structure.label or 'selected scope'
    local first_line = structure.first_line or (history_options.range and history_options.range[1])
    local last_line = structure.last_line or (history_options.range and history_options.range[2])
    local line_suffix = first_line and last_line and (':%d-%d'):format(first_line, last_line) or ''
    scope_prefix = (' %s · SYMBOL · '):format(source)
    scope_detail = ('%s · %s%s'):format(
      structure_label,
      location.relative_path or '',
      line_suffix
    )
  elseif history_options.kind == 'file' then
    scope_prefix = (' %s · FILE · '):format(source)
    scope_detail = location.relative_path or ''
  else
    scope_prefix = (' %s · REPOSITORY '):format(source)
  end
  vim.wo[panel_window].winbar = '%#DiffviewFilePanelSelected#'
    .. escaped_winbar_text(scope_prefix)
    .. '%<'
    .. escaped_winbar_text(scope_detail)
    .. ' %='
end

function M.adapt_history_footer(view)
  local history_panel = view and view.panel
  if not view or not view.git_footer_tree or not history_panel then
    return false
  end
  local footer_changed = false
  for _, entry in ipairs(history_panel.entries or {}) do
    if entry.single_file then
      entry.single_file = false
      footer_changed = true
    end
  end
  local current_entry = history_panel.cur_item and history_panel.cur_item[1]
  if current_entry and current_entry.folded then
    current_entry.folded = false
    footer_changed = true
  end
  if footer_changed and type(history_panel.render) == 'function' then
    history_panel:render()
    if type(history_panel.redraw) == 'function' then
      history_panel:redraw()
    end
  end
  update_history_panel_winbar(view)
  return footer_changed
end

local function synchronize_history_footer(view)
  local remaining_attempts = 150
  local function synchronize()
    if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      return
    end
    M.adapt_history_footer(view)
    local history_panel = view.panel
    if history_panel and history_panel.updating then
      remaining_attempts = remaining_attempts - 1
      if remaining_attempts > 0 then
        vim.defer_fn(synchronize, 20)
      end
    end
  end
  vim.defer_fn(synchronize, 20)
end

local function expand_filtered_footer_entry(view, file)
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
  if type(history_panel.highlight_item) == 'function' then
    history_panel:highlight_item(file)
  end
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

local function attach_history_behavior(view, history_kind)
  view.emitter:on('file_open_post', function(_, file)
    expand_filtered_footer_entry(view, file)
    update_history_winbars(view)
    reveal_changed_structure(view, file, history_kind == 'symbol')
  end)
  view.emitter:on('post_layout', function()
    update_history_panel_winbar(view)
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
        return_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        historical_search_mapping(),
      },
      file_panel = {
        close_mapping(),
        return_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        historical_search_mapping(),
      },
      file_history_panel = {
        history_entry_mapping(),
        checkout_commit_mapping(),
        close_mapping(),
        return_mapping(),
        next_window_mapping(),
        previous_window_mapping(),
        commit_list_mapping(),
        search_mapping(),
        historical_search_mapping(),
      },
      option_panel = { close_mapping(), return_mapping() },
      help_panel = { close_mapping(), return_mapping() },
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
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = protection_group,
    callback = function(event)
      local view = active_view()
      local buffer_name = vim.api.nvim_buf_get_name(event.buf)
      if view
          and view.tabpage == vim.api.nvim_get_current_tabpage()
          and vim.startswith(buffer_name, 'diffview://') then
        protect_view_buffer(event.buf)
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
  view.git_result_source = history_options.source
  view.git_history_kind = history_options.kind
  view.git_footer_tree = history_options.kind == 'file' or history_options.kind == 'symbol'
  view.git_history_options = vim.deepcopy(history_options)
  view.git_branch_name = history_options.branch_name
  view.git_history_ref = history_options.history_ref
  local search_options = vim.deepcopy(history_options)
  search_options.history_ref = nil
  search_options.parent_view = nil
  search_options.revision = nil
  search_options.selected_commit = nil
  search_options.source = nil
  search_options.unbounded = nil
  view.git_search_options = search_options
  view.git_parent_view = history_options.parent_view
  if not history_options.parent_view then
    state.root_view = view
  end
  attach_history_behavior(view, history_options.kind)
  view:open()
  synchronize_history_footer(view)
  if history_options.parent_view then
    panel.enter_search(view, function()
      M.return_to_previous_git_panel()
    end)
  else
    panel.enter_git(view, function()
      M.close()
    end)
  end
  if history_options.selected_commit then
    local remaining_attempts = 150
    local function select_when_ready()
      if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
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
  local replacement_view = M.open_file_history(replacement_options)
  if not replacement_view then
    return false
  end
  vim.defer_fn(function()
    dispose_rendered_view(previous_view, function() end)
  end, 0)
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
  if not history_panel or history_panel.updating then
    return false
  end
  for _, entry in ipairs(history_panel.entries or {}) do
    if entry.commit and entry.commit.hash == commit_hash then
      local first_file = entry.files and entry.files[1]
      local current_entry = history_panel.cur_item and history_panel.cur_item[1]
      view.git_review_target = commit_hash
      view.git_review_ready = false
      if entry.nulled
          and type(history_panel.set_cur_item) == 'function'
          and view.cur_layout
          and type(view.cur_layout.open_null) == 'function' then
        if type(view.cur_layout.detach_files) == 'function' then
          view.cur_layout:detach_files()
        end
        view.cur_layout:open_null()
        view.nulled = true
        history_panel:set_cur_item({ entry, first_file })
        if type(history_panel.render) == 'function' then
          history_panel:render()
        end
        if type(history_panel.redraw) == 'function' then
          history_panel:redraw()
        end
        highlight_history_entry(history_panel, entry)
        view.git_review_ready = true
        return true
      end
      if current_entry ~= entry and first_file and type(view.set_file) == 'function' then
        view:set_file(first_file, false)
      elseif type(history_panel.set_cur_item) == 'function' then
        history_panel:set_cur_item({ entry, first_file })
      end
      local remaining_attempts = 150
      local function highlight_when_rendered()
        if not view.tabpage or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
          return
        end
        if view.git_review_target ~= commit_hash
            or not history_panel.cur_item
            or history_panel.cur_item[1] ~= entry then
          return
        end
        if history_selection_is_rendering(view) then
          remaining_attempts = remaining_attempts - 1
          if remaining_attempts > 0 then
            vim.defer_fn(highlight_when_rendered, 20)
          end
          return
        end
        highlight_history_entry(history_panel, entry)
        vim.defer_fn(function()
          if view.git_review_target == commit_hash
              and history_panel.cur_item
              and history_panel.cur_item[1] == entry
              and not history_selection_is_rendering(view) then
            view.git_review_ready = true
          end
        end, 200)
      end
      vim.defer_fn(highlight_when_rendered, 20)
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
    branch_name = commit.branch_name,
    history_ref = commit.history_ref or commit.branch_name or commit.hash,
    kind = 'repository',
    location = { root = repository_root },
    selected_commit = commit.hash,
    source = commit.source,
    unbounded = true,
  })
end

function M.jump_to_search_commit(parent_view, history_options, commit)
  return M.open_search_commit(parent_view, history_options, commit)
end

return M
