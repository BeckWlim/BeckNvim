local repository = require('config.git.repository')

local M = {}

local function exact_commit_options(history_options)
  local exact_options = vim.deepcopy(history_options)
  exact_options.anchor_plan = nil
  exact_options.branch_name = nil
  exact_options.branch_tip_commit = nil
  exact_options.history_ref = nil
  exact_options.revision = exact_options.selected_commit
  exact_options.source = exact_options.source or 'LOCAL'
  exact_options.preloaded_history_count = nil
  exact_options.preloaded_history_output = nil
  exact_options.review_only = nil
  exact_options.window_start_offset = 0
  return exact_options
end

local function independent_preview_options(history_options, history_ref)
  local preview_options = vim.deepcopy(history_options)
  preview_options.anchor_plan = nil
  preview_options.branch_name = preview_options.checked_out_branch
  preview_options.branch_tip_commit = nil
  preview_options.history_ref = history_ref
  preview_options.independent_preview_commit = preview_options.selected_commit
  preview_options.revision = nil
  preview_options.source = 'LOCAL'
  preview_options.window_start_offset = 0
  return preview_options
end

local function selected_history_ref(history_options)
  local checked_out_branch = history_options.checked_out_branch
  if checked_out_branch and checked_out_branch ~= '' then
    return 'refs/heads/' .. checked_out_branch, true
  end
  if history_options.require_checked_out_containment then
    return nil
  end
  local selected_commit = history_options.selected_commit
  local requested_ref = history_options.history_ref
  if requested_ref and requested_ref ~= selected_commit then
    return requested_ref, false
  end
end

local function history_output_contains(output, selected_commit)
  for _, row in ipairs(repository.parse_history_rows(output)) do
    local commit_hash = row.hash
    if type(commit_hash) == 'string'
        and (
          commit_hash == selected_commit
          or (#selected_commit < #commit_hash and vim.startswith(commit_hash, selected_commit))
        ) then
      return true
    end
  end
  return false
end

-- Resolve only the branch-relative offset here. The first lightweight list
-- batch is preloaded; the footer fills the rest of its metadata window after
-- that batch is mounted.
function M.prepare_selected(repository_root, history_options, callback)
  local prepared_options = vim.deepcopy(history_options)
  local selected_commit = prepared_options.selected_commit
  if not selected_commit then
    callback(prepared_options)
    return function() end
  end

  local history_ref, matched_current_branch = selected_history_ref(prepared_options)
  if not history_ref then
    callback(exact_commit_options(prepared_options))
    return function() end
  end
  if matched_current_branch then
    prepared_options.branch_name = prepared_options.checked_out_branch
    prepared_options.source = 'LOCAL'
  end

  local cancelled = false
  local finished = false
  local active_cancel
  local function finish(resolved_options)
    if cancelled or finished then
      return
    end
    finished = true
    active_cancel = nil
    callback(resolved_options)
  end
  local function fall_back_to_commit()
    finish(exact_commit_options(prepared_options))
  end
  local function prepare_independent_preview()
    if not matched_current_branch then
      fall_back_to_commit()
      return
    end
    local preview_options = independent_preview_options(prepared_options, history_ref)
    local preview_cancel = repository.start(
      repository.commands.history_rows({
        kind = 'repository',
        location = preview_options.location,
        revision = selected_commit,
      }, 0, 1),
      repository_root,
      function(preview_process)
        active_cancel = nil
        if cancelled then
          return
        end
        if preview_process.code ~= 0
            or not history_output_contains(preview_process.stdout or '', selected_commit) then
          fall_back_to_commit()
          return
        end
        preview_options.preloaded_history_count = repository.footer_list_batch_entries
        local branch_cancel = repository.start(
          repository.commands.history_rows(preview_options, 0, preview_options.preloaded_history_count),
          repository_root,
          function(branch_process)
            active_cancel = nil
            if cancelled then
              return
            end
            if branch_process.code ~= 0 then
              fall_back_to_commit()
              return
            end
            preview_options.preloaded_history_output = (preview_process.stdout or '')
              .. (branch_process.stdout or '')
            finish(preview_options)
          end
        )
        if not finished and not cancelled then
          active_cancel = branch_cancel
        end
      end
    )
    if not finished and not cancelled then
      active_cancel = preview_cancel
    end
  end

  local ancestor_cancel = repository.start(
    repository.commands.commit_is_ancestor(selected_commit, history_ref),
    repository_root,
    function(ancestor_process)
      active_cancel = nil
      if cancelled then
        return
      end
      if ancestor_process.code ~= 0 then
        prepare_independent_preview()
        return
      end
      local position_cancel = repository.start(
        repository.commands.commit_position(selected_commit, history_ref),
        repository_root,
        function(position_process)
          active_cancel = nil
          if cancelled then
            return
          end
          local commit_position = position_process.code == 0
              and repository.parse_count(position_process.stdout)
            or nil
          if not commit_position then
            fall_back_to_commit()
            return
          end
          local resolved_options = vim.deepcopy(prepared_options)
          resolved_options.history_ref = history_ref
          resolved_options.revision = nil
          local newer_capacity = math.max(
            0,
            repository.footer_list_batch_entries
              - repository.footer_preview_headroom_entries
              - 1
          )
          resolved_options.window_start_offset = math.max(
            0,
            commit_position - newer_capacity
          )
          resolved_options.preloaded_history_count = repository.footer_list_batch_entries
          local list_cancel = repository.start(
            repository.commands.history_rows(
              resolved_options,
              resolved_options.window_start_offset,
              resolved_options.preloaded_history_count
            ),
            repository_root,
            function(list_process)
              active_cancel = nil
              if cancelled then
                return
              end
              local list_output = list_process.stdout or ''
              if list_process.code ~= 0
                  or not history_output_contains(list_output, selected_commit) then
                fall_back_to_commit()
                return
              end
              resolved_options.preloaded_history_output = list_output
              finish(resolved_options)
            end
          )
          if not finished and not cancelled then
            active_cancel = list_cancel
          end
        end
      )
      if not finished and not cancelled then
        active_cancel = position_cancel
      end
    end
  )
  if not finished and not cancelled then
    active_cancel = ancestor_cancel
  end
  vim.defer_fn(function()
    if finished or cancelled then
      return
    end
    local timeout_cancel = active_cancel
    active_cancel = nil
    if type(timeout_cancel) == 'function' then
      timeout_cancel()
    end
    fall_back_to_commit()
  end, repository.footer_request_timeout_ms)

  return function()
    if cancelled or finished then
      return
    end
    cancelled = true
    local cancel_process = active_cancel
    active_cancel = nil
    if type(cancel_process) == 'function' then
      cancel_process()
    end
  end
end

function M.initial_limit(history_options)
  if history_options.unbounded then
    return repository.unbounded_history_entries
  end
  return 1
end

function M.initial_ref(history_options)
  return history_options.history_ref
end

local function row_hash(row)
  return row and row.hash or nil
end

function M.merge_rows(existing_rows, incoming_rows, direction, maximum_rows)
  local known_hashes = {}
  local merged_rows = {}
  local added_count = 0
  local trimmed_count = 0

  local function append_unique(rows, count_as_added)
    for _, row in ipairs(rows) do
      local commit_hash = row_hash(row)
      if commit_hash and not known_hashes[commit_hash] then
        known_hashes[commit_hash] = true
        merged_rows[#merged_rows + 1] = row
        if count_as_added then
          added_count = added_count + 1
        end
      end
    end
  end

  if direction == 'newer' then
    append_unique(incoming_rows, true)
    append_unique(existing_rows, false)
  elseif direction == 'older' then
    append_unique(existing_rows, false)
    append_unique(incoming_rows, true)
  else
    append_unique(incoming_rows, true)
  end

  local row_limit = maximum_rows or repository.footer_list_max_entries
  if #merged_rows > row_limit then
    trimmed_count = #merged_rows - row_limit
    if direction == 'older' then
      merged_rows = vim.list_slice(merged_rows, trimmed_count + 1)
    else
      merged_rows = vim.list_slice(merged_rows, 1, row_limit)
    end
  end
  return merged_rows, added_count, trimmed_count
end

function M.cursor_direction(loader_state, cursor_index, entry_count)
  if not loader_state
      or not loader_state.list_ready
      or loader_state.list_loading
      or not cursor_index
      or entry_count == 0 then
    return nil
  end
  if not loader_state.newer_complete
      and cursor_index <= repository.footer_list_margin_entries then
    return 'newer'
  end
  if not loader_state.older_complete
      and entry_count - cursor_index < repository.footer_list_margin_entries then
    return 'older'
  end
end

function M.boundary_load_count(loader_state)
  local retained_rows = loader_state and loader_state.rows or {}
  local unused_capacity = math.max(
    0,
    repository.footer_list_max_entries - #retained_rows
  )
  return math.max(repository.footer_list_batch_entries, unused_capacity)
end

local function loader_is_current(view, loader_state)
  return view and view.git_footer_loader == loader_state and not loader_state.cancelled
end

local function set_activity(view, loader_state, activity_name, label)
  if loader_state.activities[activity_name] == label then
    return
  end
  loader_state.activities[activity_name] = label
  local activity_handler = loader_state.handlers.activity
  if activity_handler then
    activity_handler(view, activity_name, label)
  end
end

local function report_failure(view, loader_state, request_kind, detail)
  local failure_handler = loader_state.handlers.failed
  if failure_handler then
    failure_handler(view, request_kind, detail)
  end
end

local function cancel_list_request(loader_state)
  local list_token = loader_state.list_token
  if list_token then
    list_token.cancelled = true
  end
  local cancel_process = loader_state.list_cancel
  loader_state.list_cancel = nil
  loader_state.list_token = nil
  loader_state.list_loading = nil
  if type(cancel_process) == 'function' then
    cancel_process()
  end
end

local function entry_index(entries, target_entry)
  for current_index, entry in ipairs(entries) do
    if entry == target_entry then
      return current_index
    end
  end
end

local request_list_page
local synchronize_detail_window

local function finish_list_request(
    view,
    loader_state,
    list_token,
    completed_process
)
  if loader_state.list_token ~= list_token or list_token.cancelled then
    return
  end
  loader_state.list_token = nil
  loader_state.list_cancel = nil
  local direction = list_token.direction
  loader_state.list_loading = nil
  set_activity(view, loader_state, 'history_list', nil)
  if not loader_is_current(view, loader_state) then
    return
  end
  if completed_process.code ~= 0 then
    report_failure(
      view,
      loader_state,
      direction .. ' commit list',
      repository.concise_error(completed_process)
    )
    return
  end

  local incoming_rows = repository.parse_history_rows(completed_process.stdout)
  local pinned_hash = loader_state.independent_preview_commit
  if pinned_hash then
    local branch_rows = {}
    for _, row in ipairs(incoming_rows) do
      if row.hash == pinned_hash then
        loader_state.independent_preview_row = row
      else
        branch_rows[#branch_rows + 1] = row
      end
    end
    incoming_rows = branch_rows
  end
  local merged_rows, added_count, trimmed_count = M.merge_rows(
    loader_state.branch_rows,
    incoming_rows,
    direction,
    repository.footer_list_max_entries
  )
  loader_state.branch_rows = merged_rows
  if loader_state.independent_preview_row then
    merged_rows = vim.list_extend({ loader_state.independent_preview_row }, merged_rows)
  end
  if direction == 'initial' then
    loader_state.start_offset = list_token.offset
    loader_state.newer_complete = list_token.offset == 0
    loader_state.older_complete = #incoming_rows < list_token.count
  elseif direction == 'newer' then
    loader_state.start_offset = list_token.offset
    loader_state.newer_complete = list_token.offset == 0
    if trimmed_count > 0 then
      loader_state.older_complete = false
    end
  else
    if trimmed_count > 0 then
      loader_state.start_offset = loader_state.start_offset + trimmed_count
      loader_state.newer_complete = false
    end
    loader_state.older_complete = #incoming_rows < list_token.count
  end
  loader_state.rows = merged_rows

  local install_handler = loader_state.handlers.install_rows
  if not install_handler then
    loader_state.list_ready = true
    return
  end
  loader_state.list_installing = true
  install_handler(view, merged_rows, direction, function(installed, center_entry)
    if not loader_is_current(view, loader_state) then
      return
    end
    loader_state.list_installing = false
    if not installed then
      report_failure(view, loader_state, direction .. ' commit list', 'footer install failed')
      return
    end
    local was_ready = loader_state.list_ready
    loader_state.list_ready = true
    if not was_ready and loader_state.handlers.list_ready then
      loader_state.handlers.list_ready(view, center_entry, #merged_rows)
    elseif loader_state.handlers.list_updated then
      loader_state.handlers.list_updated(
        view,
        direction,
        added_count,
        #merged_rows,
        center_entry
      )
    end
    local unused_capacity = math.max(
      0,
      repository.footer_list_max_entries - #merged_rows
    )
    if unused_capacity > 0 and not loader_state.older_complete then
      -- The first mounted rows are already usable. Begin their top-ordered
      -- child preload while the rest of the metadata window fills.
      synchronize_detail_window(view)
      request_list_page(
        view,
        loader_state,
        'older',
        loader_state.start_offset + #loader_state.branch_rows,
        math.max(repository.footer_list_batch_entries, unused_capacity)
      )
      return
    end
    synchronize_detail_window(view)
  end)
end

request_list_page = function(view, loader_state, direction, offset, count)
  if not loader_is_current(view, loader_state)
      or loader_state.list_loading
      or loader_state.list_installing then
    return false
  end
  local list_token = {
    cancelled = false,
    count = count,
    direction = direction,
    offset = offset,
  }
  loader_state.list_token = list_token
  loader_state.list_loading = direction
  set_activity(view, loader_state, 'history_list', direction .. ' commits')
  local command = repository.commands.history_rows(loader_state.history_options, offset, count)
  local cancel_process = repository.start(command, loader_state.repository_root, function(process)
    finish_list_request(view, loader_state, list_token, process)
  end)
  if loader_state.list_token == list_token then
    loader_state.list_cancel = cancel_process
  end
  vim.defer_fn(function()
    if not loader_is_current(view, loader_state)
        or loader_state.list_token ~= list_token
        or list_token.cancelled then
      return
    end
    list_token.cancelled = true
    local timeout_cancel = loader_state.list_cancel
    loader_state.list_cancel = nil
    loader_state.list_token = nil
    loader_state.list_loading = nil
    if type(timeout_cancel) == 'function' then
      timeout_cancel()
    end
    set_activity(view, loader_state, 'history_list', nil)
    report_failure(view, loader_state, direction .. ' commit list', 'request timed out')
  end, repository.footer_request_timeout_ms)
  return true
end

local function detail_token_entries(detail_token)
  return detail_token.entries or { detail_token.entry }
end

local function cancel_detail_request(detail_token)
  if detail_token.cancelled then
    return
  end
  detail_token.cancelled = true
  local cancel_request = detail_token.cancel
  detail_token.cancel = nil
  if type(cancel_request) == 'function' then
    cancel_request()
  end
  for _, entry in ipairs(detail_token_entries(detail_token)) do
    entry.git_details_loading = false
  end
end

local function finish_detail_request(view, loader_state, detail_token, succeeded)
  local entry = detail_token.entry
  if loader_state.detail_requests[entry] ~= detail_token then
    return
  end
  loader_state.detail_requests[entry] = nil
  loader_state.detail_active = math.max(0, loader_state.detail_active - 1)
  entry.git_details_loading = false
  if succeeded then
    entry.git_details_loaded = true
  end
  for _, completion_callback in ipairs(detail_token.callbacks) do
    completion_callback(succeeded)
  end
  if loader_is_current(view, loader_state) then
    M.pump_details(view)
  end
end

local function finish_detail_batch(view, loader_state, detail_token, results)
  local token_is_current = false
  for _, entry in ipairs(detail_token.entries) do
    if loader_state.detail_requests[entry] == detail_token then
      token_is_current = true
      break
    end
  end
  if not token_is_current then
    return
  end
  for entry_index, entry in ipairs(detail_token.entries) do
    if loader_state.detail_requests[entry] == detail_token then
      loader_state.detail_requests[entry] = nil
    end
    entry.git_details_loading = false
    local succeeded = results and results[entry] == true
    if succeeded then
      entry.git_details_loaded = true
    end
    local callbacks = detail_token.callbacks[entry_index]
    for _, completion_callback in ipairs(callbacks) do
      completion_callback(succeeded)
    end
  end
  loader_state.detail_active = math.max(0, loader_state.detail_active - 1)
  if loader_is_current(view, loader_state) then
    M.pump_details(view)
  end
end

local function start_detail_batch(view, loader_state, queued_items)
  local hydrate_handler = loader_state.handlers.hydrate_entries
  if not hydrate_handler then
    return false
  end
  local entries = {}
  local callbacks = {}
  local detail_token = {
    callbacks = callbacks,
    cancelled = false,
    entries = entries,
  }
  for item_index, queued_item in ipairs(queued_items) do
    local entry = queued_item.entry
    entries[item_index] = entry
    callbacks[item_index] = queued_item.callbacks
    loader_state.detail_requests[entry] = detail_token
    entry.git_details_loading = true
  end
  loader_state.detail_active = loader_state.detail_active + 1
  local cancel_request = hydrate_handler(view, entries, function(results)
    if detail_token.cancelled or not loader_is_current(view, loader_state) then
      return
    end
    finish_detail_batch(view, loader_state, detail_token, results)
  end)
  local first_entry = entries[1]
  if first_entry and loader_state.detail_requests[first_entry] == detail_token then
    detail_token.cancel = cancel_request
  end
  vim.defer_fn(function()
    if not loader_is_current(view, loader_state) or detail_token.cancelled then
      return
    end
    local request_is_current = false
    for _, entry in ipairs(entries) do
      if loader_state.detail_requests[entry] == detail_token then
        request_is_current = true
        break
      end
    end
    if not request_is_current then
      return
    end
    cancel_detail_request(detail_token)
    for entry_index, entry in ipairs(entries) do
      if loader_state.detail_requests[entry] == detail_token then
        loader_state.detail_requests[entry] = nil
      end
      for _, completion_callback in ipairs(callbacks[entry_index]) do
        completion_callback(false)
      end
    end
    loader_state.detail_active = math.max(0, loader_state.detail_active - 1)
    report_failure(view, loader_state, 'commit detail batch', 'request timed out')
    M.pump_details(view)
  end, repository.footer_request_timeout_ms)
  return true
end

local function start_detail_request(view, loader_state, entry, callbacks)
  local hydrate_handler = loader_state.handlers.hydrate_entry
  if not hydrate_handler then
    for _, completion_callback in ipairs(callbacks) do
      completion_callback(false)
    end
    return false
  end
  local detail_token = {
    callbacks = callbacks,
    cancelled = false,
    entry = entry,
  }
  loader_state.detail_requests[entry] = detail_token
  loader_state.detail_active = loader_state.detail_active + 1
  entry.git_details_loading = true
  local cancel_request = hydrate_handler(view, entry, function(succeeded)
    if detail_token.cancelled or not loader_is_current(view, loader_state) then
      return
    end
    finish_detail_request(view, loader_state, detail_token, succeeded == true)
  end)
  if loader_state.detail_requests[entry] == detail_token then
    detail_token.cancel = cancel_request
  end
  vim.defer_fn(function()
    if not loader_is_current(view, loader_state)
        or loader_state.detail_requests[entry] ~= detail_token
        or detail_token.cancelled then
      return
    end
    cancel_detail_request(detail_token)
    loader_state.detail_requests[entry] = nil
    loader_state.detail_active = math.max(0, loader_state.detail_active - 1)
    report_failure(view, loader_state, 'commit details', 'request timed out')
    for _, completion_callback in ipairs(detail_token.callbacks) do
      completion_callback(false)
    end
    M.pump_details(view)
  end, repository.footer_request_timeout_ms)
  return true
end

function M.pump_details(view)
  local loader_state = view and view.git_footer_loader
  if not loader_state or loader_state.cancelled then
    return false
  end
  local worker_count = repository.footer_detail_worker_count
  local background_worker_count = math.max(1, worker_count - 1)
  while loader_state.detail_active < worker_count do
    local next_item = loader_state.detail_queue[1]
    if not next_item
        or (
          not next_item.interactive
          and loader_state.detail_active >= background_worker_count
        ) then
      break
    end
    local queued_item = table.remove(loader_state.detail_queue, 1)
    if not queued_item then
      break
    end
    local queued_entry = queued_item.entry
    if queued_entry.git_details_loaded then
      for _, completion_callback in ipairs(queued_item.callbacks) do
        completion_callback(true)
      end
    elseif not loader_state.detail_requests[queued_entry] then
      if not queued_item.interactive and loader_state.handlers.hydrate_entries then
        local queued_batch = { queued_item }
        while #queued_batch < repository.footer_detail_batch_entries do
          local next_queued_item = loader_state.detail_queue[1]
          if not next_queued_item or next_queued_item.interactive then
            break
          end
          queued_batch[#queued_batch + 1] = table.remove(loader_state.detail_queue, 1)
        end
        start_detail_batch(view, loader_state, queued_batch)
      else
        start_detail_request(view, loader_state, queued_entry, queued_item.callbacks)
      end
    end
  end
  local details_loading = loader_state.detail_active > 0 or #loader_state.detail_queue > 0
  set_activity(
    view,
    loader_state,
    'history_detail',
    details_loading and 'current window commit details' or nil
  )
  if details_loading then
    loader_state.detail_settled_reported = false
  elseif not loader_state.detail_settled_reported then
    loader_state.detail_settled_reported = true
    local settled_handler = loader_state.handlers.details_settled
    if settled_handler then
      settled_handler(view)
    end
  end
  return details_loading
end

local function queue_detail(loader_state, entry, callback, front)
  local active_request = loader_state.detail_requests[entry]
  if active_request then
    if callback then
      if active_request.entries then
        for entry_index, active_entry in ipairs(active_request.entries) do
          if active_entry == entry then
            local entry_callbacks = active_request.callbacks[entry_index]
            entry_callbacks[#entry_callbacks + 1] = callback
            break
          end
        end
      else
        active_request.callbacks[#active_request.callbacks + 1] = callback
      end
    end
    return
  end
  for queue_index, queued_item in ipairs(loader_state.detail_queue) do
    if queued_item.entry == entry then
      if callback then
        queued_item.callbacks[#queued_item.callbacks + 1] = callback
      end
      if front and queue_index > 1 then
        queued_item.interactive = true
        table.remove(loader_state.detail_queue, queue_index)
        table.insert(loader_state.detail_queue, 1, queued_item)
      elseif front then
        queued_item.interactive = true
      end
      return
    end
  end
  local queued_item = {
    callbacks = callback and { callback } or {},
    entry = entry,
    interactive = front == true,
  }
  loader_state.detail_settled_reported = false
  if front then
    table.insert(loader_state.detail_queue, 1, queued_item)
  else
    loader_state.detail_queue[#loader_state.detail_queue + 1] = queued_item
  end
end

function M.on_cursor(view, cursor_entry)
  local loader_state = view and view.git_footer_loader
  local history_panel = view and view.panel
  local entries = history_panel and history_panel.entries or {}
  if not loader_state or not loader_state.list_ready or not cursor_entry then
    return false
  end
  local cursor_index = entry_index(entries, cursor_entry)
  if not cursor_index then
    return false
  end

  -- Cursor movement only changes the metadata window at a boundary. Detail
  -- priority is stable branch order across the whole retained list window.
  local direction = M.cursor_direction(loader_state, cursor_index, #entries)
  if direction == 'newer' then
    local requested_count = math.min(
      loader_state.start_offset,
      M.boundary_load_count(loader_state)
    )
    local next_offset = loader_state.start_offset - requested_count
    if request_list_page(
        view,
        loader_state,
        direction,
        next_offset,
        requested_count
      ) then
      return true
    end
  elseif direction == 'older' then
    if request_list_page(
        view,
        loader_state,
        direction,
        loader_state.start_offset + #loader_state.rows,
        M.boundary_load_count(loader_state)
      ) then
      return true
    end
  end

  return synchronize_detail_window(view)
end

synchronize_detail_window = function(view)
  local loader_state = view and view.git_footer_loader
  local history_panel = view and view.panel
  local entries = history_panel and history_panel.entries or {}
  if not loader_state or not loader_state.list_ready then
    return false
  end
  if loader_state.detail_entries == entries then
    M.pump_details(view)
    return true
  end
  loader_state.detail_entries = entries

  local desired_entries = {}
  for _, entry in ipairs(entries) do
    desired_entries[entry] = true
  end
  loader_state.desired_entries = desired_entries

  local tokens_to_cancel = {}
  for active_entry, detail_token in pairs(loader_state.detail_requests) do
    if not desired_entries[active_entry] then
      tokens_to_cancel[detail_token] = true
    end
  end
  for detail_token in pairs(tokens_to_cancel) do
    cancel_detail_request(detail_token)
    for _, token_entry in ipairs(detail_token_entries(detail_token)) do
      if loader_state.detail_requests[token_entry] == detail_token then
        loader_state.detail_requests[token_entry] = nil
      end
    end
    loader_state.detail_active = math.max(0, loader_state.detail_active - 1)
  end
  local retained_queue = {}
  for _, queued_item in ipairs(loader_state.detail_queue) do
    if desired_entries[queued_item.entry] then
      retained_queue[#retained_queue + 1] = queued_item
    end
  end
  loader_state.detail_queue = retained_queue

  for _, entry in ipairs(entries) do
    if not entry.git_details_loaded then
      queue_detail(loader_state, entry, nil, false)
    end
  end
  M.pump_details(view)

  return true
end

function M.ensure_entry(view, entry, callback)
  local loader_state = view and view.git_footer_loader
  local completion_callback = callback or function() end
  if not loader_state or not entry then
    completion_callback(entry ~= nil)
    return entry ~= nil
  end
  if entry.git_details_loaded then
    completion_callback(true)
    return true
  end
  queue_detail(loader_state, entry, completion_callback, true)
  M.pump_details(view)
  return true
end

function M.attach(view, history_options, handlers)
  M.detach(view)
  if history_options.unbounded or not history_options.history_ref then
    return false
  end
  local loader_history_options = vim.deepcopy(history_options)
  loader_history_options.preloaded_history_count = nil
  loader_history_options.preloaded_history_output = nil
  local loader_state = {
    activities = {},
    cancelled = false,
    desired_entries = {},
    detail_entries = nil,
    detail_active = 0,
    detail_queue = {},
    detail_requests = {},
    detail_settled_reported = true,
    handlers = handlers or {},
    history_options = loader_history_options,
    independent_preview_commit = history_options.independent_preview_commit,
    independent_preview_row = nil,
    branch_rows = {},
    list_installing = false,
    list_loading = nil,
    list_ready = false,
    newer_complete = (history_options.window_start_offset or 0) == 0,
    older_complete = false,
    repository_root = view.git_repository_root,
    rows = {},
    start_offset = history_options.window_start_offset or 0,
  }
  view.git_footer_loader = loader_state
  if type(history_options.preloaded_history_output) == 'string' then
    local list_token = {
      cancelled = false,
      count = history_options.preloaded_history_count
        or repository.footer_list_batch_entries,
      direction = 'initial',
      offset = loader_state.start_offset,
    }
    loader_state.list_token = list_token
    loader_state.list_loading = 'initial'
    vim.defer_fn(function()
      if loader_is_current(view, loader_state) then
        finish_list_request(view, loader_state, list_token, {
          code = 0,
          stderr = '',
          stdout = history_options.preloaded_history_output,
        })
      end
    end, 20)
  else
    request_list_page(
      view,
      loader_state,
      'initial',
      loader_state.start_offset,
      repository.footer_list_batch_entries
    )
  end
  return true
end

function M.list_is_ready(view)
  local loader_state = view and view.git_footer_loader
  return not loader_state or loader_state.list_ready
end

function M.window_is_settled(view)
  local loader_state = view and view.git_footer_loader
  return not loader_state
    or (
      loader_state.list_ready
      and not loader_state.list_loading
      and not loader_state.list_installing
    )
end

function M.detach(view)
  local loader_state = view and view.git_footer_loader
  if not loader_state then
    return false
  end
  loader_state.cancelled = true
  cancel_list_request(loader_state)
  for _, detail_token in pairs(loader_state.detail_requests) do
    cancel_detail_request(detail_token)
  end
  loader_state.detail_requests = {}
  loader_state.detail_queue = {}
  view.git_footer_loader = nil
  return true
end

return M
