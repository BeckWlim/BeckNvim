local project = require('config.project')
local panel = require('config.git.panel')
local repository = require('config.git.repository')
local ui = require('config.git.ui')
local events = require('config.git.events')

local M = {}
local commit_transitioning = false
local history_request_generation = 0

function M.on(event_name, callback)
  return events.on(event_name, callback)
end

function M.supports_event(event_name)
  return events.supports(event_name)
end

local function anchor_elapsed_milliseconds(operation)
  return (vim.uv.hrtime() - operation.started_at_ns) / 1000000
end

local function anchor_target(operation)
  return (operation.resolved_commit or operation.requested_commit):sub(1, 12)
end

local function log_anchor_operation(operation, stage, level)
  require('config.git.diffview').log_anchor(
    ('%s · %s · %.1f ms'):format(
      anchor_target(operation),
      stage,
      anchor_elapsed_milliseconds(operation)
    ),
    level
  )
end

local function set_anchor_footer(operation, status)
  local parent_view = operation.parent_view
  if not parent_view then
    return
  end
  parent_view.git_anchor_waiting = status
  require('config.git.diffview').adapt_history_footer(parent_view)
end

local function finish_anchor_lifecycle(view, succeeded, detail)
  local git_diffview = require('config.git.diffview')
  if type(git_diffview.finish_anchor_operation) == 'function' then
    git_diffview.finish_anchor_operation(view, succeeded, detail)
  end
end

local function current_file_location()
  local source_buffer = vim.api.nvim_get_current_buf()
  local source_path = vim.api.nvim_buf_get_name(source_buffer)
  if source_path == '' or vim.bo[source_buffer].buftype ~= '' then
    return nil, 'Git history requires a saved file buffer'
  end

  local normalized_path = vim.fs.normalize(source_path)
  local repository_root = project.detect_repository(normalized_path)
  if not repository_root then
    return nil, 'The current file is not inside a Git repository'
  end

  local relative_path = vim.fs.relpath(repository_root, normalized_path)
  if not relative_path then
    return nil, 'The current file is outside the detected Git repository'
  end

  return {
    buffer = source_buffer,
    relative_path = relative_path,
    root = repository_root,
  }
end

local function current_repository()
  local workspace_root = project.for_buffer(0)
  local repository_root = workspace_root and project.detect_repository(workspace_root) or nil
  if not repository_root then
    return nil, 'The current workspace is not a Git repository'
  end
  return {
    root = repository_root,
  }
end

local resolve_history_head_options

local function mount_history_while_resolving_head(history_options)
  local git_diffview = require('config.git.diffview')
  local mounting_options = vim.deepcopy(history_options)
  mounting_options.head_resolution_pending = true
  local mounted_view = git_diffview.open_file_history(mounting_options)
  if not mounted_view then
    return
  end

  local resolution_finished = false
  local cancel_resolution = resolve_history_head_options(
    history_options,
    function(resolved_history_options)
      resolution_finished = true
      local final_history_options = vim.deepcopy(resolved_history_options)
      final_history_options.head_resolution_pending = nil
      if final_history_options.revision then
        if not git_diffview.finish_history_head_request(mounted_view) then
          return
        end
        git_diffview.replace_file_history(mounted_view, final_history_options)
        return
      end
      git_diffview.apply_history_context(mounted_view, final_history_options)
    end,
    function(progress_label)
      git_diffview.set_history_activity(mounted_view, 'head', progress_label)
    end
  )
  if not resolution_finished then
    git_diffview.attach_history_head_request(mounted_view, cancel_resolution)
  end
  return mounted_view
end

local function open_history(kind)
  history_request_generation = history_request_generation + 1
  local request_generation = history_request_generation
  local location, location_error
  if kind == 'repository' then
    location, location_error = current_repository()
  else
    location, location_error = current_file_location()
  end
  if not location then
    vim.notify(location_error, vim.log.levels.INFO)
    return
  end

  if kind ~= 'symbol' then
    mount_history_while_resolving_head({
      kind = kind,
      location = location,
      -- Generic post-render landing: an explicit open of the traced file places
      -- the AFTER-pane cursor on the line it had in the editor.
      cursor_target = kind == 'file' and {
        path = location.relative_path,
        line = vim.api.nvim_win_get_cursor(0)[1],
      } or nil,
    })
    return
  end

  local source_buffer = location.buffer
  local source_cursor = vim.api.nvim_win_get_cursor(0)
  require('config.syntax.treesitter_context').enclosing_structure_async(
    source_buffer,
    source_cursor[1] - 1,
    source_cursor[2],
    function(structure, parse_error)
      if request_generation ~= history_request_generation
          or not vim.api.nvim_buf_is_valid(source_buffer) then
        return
      end
      if parse_error then
        vim.notify('Could not resolve cursor symbol: ' .. parse_error, vim.log.levels.WARN)
        return
      end
      if not structure then
        vim.notify(
          'Place the cursor inside a function or class for symbol history',
          vim.log.levels.INFO
        )
        return
      end
      local symbol_location = vim.tbl_extend('force', location, {
        structure = structure,
      })
      mount_history_while_resolving_head({
        kind = kind,
        location = symbol_location,
        range = { structure.first_line, structure.last_line },
        cursor_target = {
          path = location.relative_path,
          line = structure.first_line,
          structure = structure,
        },
      })
    end
  )
end

function M.history_file()
  open_history('file')
end

function M.history_symbol()
  open_history('symbol')
end

function M.history_repository()
  open_history('repository')
end

resolve_history_head_options = function(history_options, callback, progress_callback)
  local resolved_options = vim.deepcopy(history_options)
  local history_location = resolved_options.location
  local resolution_cancelled = false
  local active_cancel
  local resolution_finished = false
  local function report_progress(progress_label)
    if not resolution_cancelled and progress_callback then
      progress_callback(progress_label)
    end
  end
  local function finish_resolution()
    if resolution_cancelled then
      return
    end
    resolution_finished = true
    active_cancel = nil
    callback(resolved_options)
  end
  local head_cancel = repository.start(
    repository.commands.head_state(),
    history_location.root,
    function(head_process)
      active_cancel = nil
      if resolution_cancelled then
        return
      end
      if head_process.code ~= 0 then
        vim.notify(repository.concise_error(head_process), vim.log.levels.WARN)
        finish_resolution()
        return
      end
      local head_state = repository.parse_head_state(head_process.stdout)
      resolved_options.checked_out_branch = head_state.branch_name
      -- Repository history can expose the live worktree as a synthetic newest
      -- row. File and symbol histories remain commit-only.
      resolved_options.worktree_dirty = head_state.dirty and history_options.kind == 'repository'
      if not head_state.detached or not head_state.commit then
        if head_state.branch_name and head_state.branch_name ~= '' then
          local branch_ref = 'refs/heads/' .. head_state.branch_name
          resolved_options.anchor_plan = {
            branch_name = head_state.branch_name,
            branch_ref = branch_ref,
            branch_tip_commit = head_state.commit,
            source = 'LOCAL',
          }
          resolved_options.branch_name = head_state.branch_name
          resolved_options.branch_tip_commit = head_state.commit
          resolved_options.history_ref = branch_ref
          resolved_options.source = 'LOCAL'
        end
        finish_resolution()
        return
      end
      local detached_commit = head_state.commit
      resolved_options.detached_head_commit = detached_commit
      resolved_options.selected_commit = detached_commit
      report_progress('detached HEAD branch')
      local branch_cancel = repository.start(
        repository.commands.branches_pointing_at(detached_commit),
        history_location.root,
        function(branch_process)
          active_cancel = nil
          if resolution_cancelled then
            return
          end
          local matched_branch = branch_process.code == 0
              and repository.match_detached_tip_branch(
                repository.parse_branches(branch_process.stdout),
                detached_commit
              )
            or nil
          if matched_branch then
            local result_source = matched_branch.is_remote and 'REMOTE' or 'LOCAL'
            resolved_options.anchor_plan = {
              branch_name = matched_branch.short_name,
              branch_ref = matched_branch.refname,
              branch_tip_commit = detached_commit,
              source = result_source,
            }
            resolved_options.branch_name = matched_branch.short_name
            resolved_options.branch_tip_commit = detached_commit
            resolved_options.history_ref = matched_branch.refname
            resolved_options.review_only = true
            resolved_options.source = result_source
            if resolved_options.kind ~= 'repository' then
              resolved_options.selected_commit = nil
            end
          else
            if branch_process.code ~= 0 then
              vim.notify(repository.concise_error(branch_process), vim.log.levels.WARN)
            end
            resolved_options.revision = detached_commit
            resolved_options.unbounded = true
          end
          finish_resolution()
        end
      )
      if not resolution_finished and not resolution_cancelled then
        active_cancel = branch_cancel
      end
    end
  )
  if not resolution_finished and not resolution_cancelled then
    active_cancel = head_cancel
  end
  return function()
    if resolution_cancelled or resolution_finished then
      return
    end
    resolution_cancelled = true
    local cancel_process = active_cancel
    active_cancel = nil
    if type(cancel_process) == 'function' then
      cancel_process()
    end
  end
end

local function resolve_repository_history_options(location, callback)
  resolve_history_head_options({
    kind = 'repository',
    location = location,
  }, callback)
end

local function repository_search_options(history_options)
  local search_options = vim.deepcopy(history_options)
  search_options.anchor_plan = nil
  search_options.history_ref = nil
  search_options.parent_view = nil
  search_options.render_ready_callback = nil
  search_options.revision = nil
  search_options.selected_commit = nil
  search_options.source = nil
  search_options.unbounded = nil
  search_options.preview_commit = nil
  search_options.preloaded_history_count = nil
  search_options.preloaded_history_output = nil
  search_options.window_ref = nil
  search_options.window_start_offset = nil
  return search_options
end

function M.search_repository()
  local git_diffview = require('config.git.diffview')
  if git_diffview.defer_until_settled('repository_search', M.search_repository) then
    return true
  end
  if git_diffview.is_active() then
    return git_diffview.search()
  end
  local location, location_error = current_repository()
  if not location then
    vim.notify(location_error, vim.log.levels.INFO)
    return false
  end
  resolve_repository_history_options(location, function(history_options)
    require('config.git.search').open(
      location.root,
      repository_search_options(history_options),
      nil
    )
  end)
  return true
end

local function modified_repository_buffers(root)
  local modified_paths = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    local buffer_path = vim.api.nvim_buf_get_name(buffer)
    if vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].modified
        and buffer_path ~= ''
        and project.contains(root, buffer_path) then
      modified_paths[#modified_paths + 1] = vim.fs.relpath(root, buffer_path) or buffer_path
    end
  end
  table.sort(modified_paths)
  return modified_paths
end

local function notify_modified_buffers(modified_paths, action)
  vim.notify(
    ('Save or discard modified repository buffers before %s:\n'):format(action)
      .. table.concat(modified_paths, '\n'),
    vim.log.levels.WARN
  )
end

local function render_branch_review(root, prompt_buffer, branch, parent_view, head_state)
  if prompt_buffer then
    require('telescope.actions').close(prompt_buffer)
  end
  local git_diffview = require('config.git.diffview')
  local branch_name = branch.short_name or branch.refname
  local branch_ref = branch.refname or branch.short_name
  local result_source = branch.is_remote and 'REMOTE' or 'LOCAL'
  local history_options = {
    anchor_plan = {
      branch_name = branch_name,
      branch_ref = branch_ref,
      branch_tip_commit = branch.tip_commit,
      source = result_source,
    },
    branch_name = branch_name,
    branch_tip_commit = branch.tip_commit,
    checked_out_branch = head_state.branch_name,
    detached_head_commit = head_state.detached and head_state.commit or nil,
    history_ref = branch_ref,
    kind = 'repository',
    location = { root = root },
    review_only = true,
    source = result_source,
  }
  local function mount_review(selected_commit)
    history_options.selected_commit = selected_commit
    history_options.unbounded = nil
    if selected_commit then
      git_diffview.open_selected_history(parent_view, history_options)
      return
    end
    if parent_view then
      git_diffview.replace_file_history(parent_view, history_options)
    else
      git_diffview.open_file_history(history_options)
    end
  end

  local detached_commit = history_options.detached_head_commit
  if not detached_commit then
    mount_review(nil)
    return
  end
  repository.start(repository.commands.commit_is_ancestor(detached_commit, branch_ref), root,
    function(ancestor_process)
      if ancestor_process.code == 0 then
        mount_review(detached_commit)
        return
      end
      if ancestor_process.code ~= 1 then
        vim.notify(repository.concise_error(ancestor_process), vim.log.levels.WARN)
      end
      mount_review(nil)
    end)
end

function M.review_branch(root, branch, parent_view)
  local repository_root = vim.fs.normalize(root)
  repository.start(repository.commands.head_state(), repository_root, function(head_process)
    if head_process.code ~= 0 then
      vim.notify(repository.concise_error(head_process), vim.log.levels.ERROR)
      return
    end
    local head_state = repository.parse_head_state(head_process.stdout)
    render_branch_review(repository_root, nil, branch, parent_view, head_state)
  end)
  return true
end

local function render_commit_overview(
    repository_root,
    commit_hash,
    review_context,
    parent_view,
    render_ready_callback,
    force_rebuild
)
  local git_diffview = require('config.git.diffview')
  local selected_context = review_context or {}
  local reviewed_history_ref = selected_context.branch_ref or selected_context.branch_name
  local history_options = {
    anchor_plan = vim.deepcopy(selected_context.anchor_plan),
    branch_name = selected_context.branch_name,
    branch_tip_commit = selected_context.branch_tip_commit,
    checked_out_branch = selected_context.checked_out_branch,
    detached_head_commit = selected_context.detached_head_commit,
    history_ref = reviewed_history_ref,
    kind = 'repository',
    location = { root = repository_root },
    open_selected_file = false,
    render_ready_callback = render_ready_callback,
    review_only = selected_context.branch_name ~= nil,
    selected_commit = commit_hash,
    source = selected_context.source,
  }
  if not reviewed_history_ref then
    history_options.revision = commit_hash
  end
  if parent_view then
    parent_view.git_render_ready_callback = render_ready_callback
    if not force_rebuild
        and not selected_context.detached_head_commit
        and git_diffview.focus_history_commit(parent_view, commit_hash) then
      return true
    end
    parent_view.git_render_ready_callback = nil
    return git_diffview.open_selected_history(parent_view, history_options)
  end
  git_diffview.close()
  return git_diffview.open_selected_history(nil, history_options)
end

local function open_detached_overview(
    repository_root,
    commit_hash,
    already_at_commit,
    already_detached,
    parent_view,
    operation,
    attach_branch_name,
    review_context
)
  local render_finished = false
  local function finish_render(_, render_succeeded, detail)
    if render_finished then
      return
    end
    render_finished = true
    commit_transitioning = false
    set_anchor_footer(operation, nil)
    finish_anchor_lifecycle(
      operation.parent_view,
      render_succeeded,
      detail
    )
    local elapsed_milliseconds = anchor_elapsed_milliseconds(operation)
    if render_succeeded then
      log_anchor_operation(operation, 'review render ready: ' .. detail, 'info')
      local completion
      if operation.action == 'attach' then
        completion = ('attached %s and rendered'):format(attach_branch_name)
      elseif operation.action == 'detach' then
        completion = 'detached and rendered'
      else
        completion = 'already current; rendered'
      end
      vim.notify(
        ('Git anchor %s: %s in %.1f ms'):format(
          anchor_target(operation),
          completion,
          elapsed_milliseconds
        ),
        vim.log.levels.INFO
      )
      return
    end
    log_anchor_operation(operation, 'review render incomplete: ' .. detail, 'error')
    vim.notify(
      ('Git anchor %s: HEAD update %s, but review render was incomplete after %.1f ms; use :DiffviewLog'):format(
        anchor_target(operation),
        operation.action == 'none' and 'was unnecessary' or 'completed',
        elapsed_milliseconds
      ),
      vim.log.levels.WARN
    )
  end

  if already_at_commit and not (already_detached and attach_branch_name) then
    local detached_head_commit = already_detached and commit_hash or nil
    local rendered_context = vim.tbl_extend('force', review_context, {
      checked_out_branch = already_detached and nil or review_context.branch_name,
      detached_head_commit = detached_head_commit,
    })
    operation.action = 'none'
    log_anchor_operation(operation, 'HEAD already at target; rendering review', 'info')
    set_anchor_footer(operation, 'HEAD unchanged; rendering ' .. commit_hash:sub(1, 12))
    local render_started = render_commit_overview(
      repository_root,
      commit_hash,
      rendered_context,
      parent_view,
      finish_render,
      false
    )
    if not render_started then
      finish_render(nil, false, 'failed to mount replacement history')
    end
    return
  end

  local anchor_command
  local anchor_action
  if attach_branch_name then
    anchor_command = repository.commands.attach_branch(attach_branch_name)
    anchor_action = 'attach'
  else
    anchor_command = repository.commands.detach_commit(commit_hash)
    anchor_action = 'detach'
  end
  operation.action = anchor_action
  log_anchor_operation(operation, 'starting ' .. table.concat(anchor_command, ' '), 'info')
  local pending_status = anchor_action == 'attach'
      and ('attaching %s'):format(attach_branch_name)
    or ('moving HEAD to %s'):format(commit_hash:sub(1, 12))
  set_anchor_footer(operation, pending_status)
  repository.start(anchor_command, repository_root,
    function(completed_process)
      if completed_process.code ~= 0 then
        commit_transitioning = false
        set_anchor_footer(operation, nil)
        finish_anchor_lifecycle(
          operation.parent_view,
          false,
          'git switch failed'
        )
        log_anchor_operation(operation, 'git switch failed', 'error')
        vim.notify(repository.concise_error(completed_process), vim.log.levels.ERROR)
        return
      end
      vim.cmd('checktime')
      local detached_head_commit = anchor_action == 'detach' and commit_hash or nil
      local rendered_context = vim.tbl_extend('force', review_context, {
        checked_out_branch = anchor_action == 'attach' and attach_branch_name or nil,
        detached_head_commit = detached_head_commit,
      })
      log_anchor_operation(operation, 'HEAD state updated; rebuilding review', 'info')
      set_anchor_footer(operation, 'HEAD ready; rendering ' .. commit_hash:sub(1, 12))
      local render_started = render_commit_overview(
        repository_root,
        commit_hash,
        rendered_context,
        parent_view,
        finish_render,
        true
      )
      if not render_started then
        finish_render(nil, false, 'failed to mount replacement history')
      end
    end)
end

function M.detach_commit_overview(root, commit_id, parent_view, commit_context)
  if commit_transitioning then
    vim.notify('A commit overview transition is already running', vim.log.levels.INFO)
    return false
  end
  local repository_root = vim.fs.normalize(root)
  local selected_context = commit_context or {}
  local operation = {
    parent_view = parent_view,
    requested_commit = commit_id,
    resolved_commit = nil,
    started_at_ns = vim.uv.hrtime(),
  }
  commit_transitioning = true
  set_anchor_footer(operation, 'validating ' .. commit_id:sub(1, 12))
  log_anchor_operation(operation, 'requested', 'info')
  vim.notify(
    ('Git anchor %s: validating checkout; details in :DiffviewLog'):format(
      commit_id:sub(1, 12)
    ),
    vim.log.levels.INFO
  )
  repository.start(repository.commands.resolve_commit(commit_id), repository_root,
    function(resolve_process)
      if resolve_process.code ~= 0 then
        commit_transitioning = false
        set_anchor_footer(operation, nil)
        finish_anchor_lifecycle(
          parent_view,
          false,
          'commit resolution failed'
        )
        log_anchor_operation(operation, 'commit resolution failed', 'error')
        vim.notify(repository.concise_error(resolve_process), vim.log.levels.ERROR)
        return
      end
      local resolved_commit = repository.parse_resolved_commit(resolve_process.stdout)
      if not resolved_commit then
        commit_transitioning = false
        set_anchor_footer(operation, nil)
        finish_anchor_lifecycle(
          parent_view,
          false,
          'commit resolution returned no object'
        )
        log_anchor_operation(operation, 'commit resolution returned no object', 'error')
        vim.notify(('Commit not found: %s'):format(commit_id), vim.log.levels.ERROR)
        return
      end
      operation.resolved_commit = resolved_commit
      log_anchor_operation(operation, 'commit resolved; reading HEAD state', 'info')
      repository.start(repository.commands.head_state(), repository_root,
        function(head_process)
          if head_process.code ~= 0 then
            commit_transitioning = false
            set_anchor_footer(operation, nil)
            finish_anchor_lifecycle(
              parent_view,
              false,
              'HEAD state read failed'
            )
            log_anchor_operation(operation, 'HEAD state read failed', 'error')
            vim.notify(repository.concise_error(head_process), vim.log.levels.ERROR)
            return
          end
          local head_state = repository.parse_head_state(head_process.stdout)
          local already_at_commit = head_state.commit == resolved_commit
          if not already_at_commit then
            if head_state.dirty then
              commit_transitioning = false
              set_anchor_footer(operation, nil)
              finish_anchor_lifecycle(
                parent_view,
                false,
                'dirty worktree'
              )
              log_anchor_operation(operation, 'refused: dirty worktree', 'warn')
              vim.notify(
                'Commit overview refused because the Git workspace is dirty',
                vim.log.levels.WARN
              )
              return
            end
            local modified_paths = modified_repository_buffers(repository_root)
            if #modified_paths > 0 then
              commit_transitioning = false
              set_anchor_footer(operation, nil)
              finish_anchor_lifecycle(
                parent_view,
                false,
                'modified editor buffers'
              )
              log_anchor_operation(operation, 'refused: modified editor buffers', 'warn')
              notify_modified_buffers(modified_paths, 'detaching HEAD')
              return
            end
          end
          local function continue_with_location(
              result_source,
              result_branch_name,
              branch_ref,
              prepared_branch_tip
          )
            local function continue_anchor(attach_branch_name)
              local review_context = {
                anchor_plan = {
                  branch_name = result_branch_name,
                  branch_ref = branch_ref,
                  branch_tip_commit = prepared_branch_tip,
                  source = result_source,
                },
                branch_name = result_branch_name,
                branch_ref = branch_ref,
                branch_tip_commit = prepared_branch_tip,
                source = result_source,
              }
              if attach_branch_name then
                open_detached_overview(
                  repository_root,
                  resolved_commit,
                  already_at_commit,
                  head_state.detached,
                  parent_view,
                  operation,
                  attach_branch_name,
                  review_context
                )
                return
              end
              -- A detached commit hangs off the CURRENT branch: containment and
              -- rendering are measured against the checked-out branch whenever
              -- one exists (the reviewed ref only while already detached), and
              -- an uncontained target renders as an independent exact commit
              -- headed by the detached HEAD.
              local attached_branch_name = not head_state.detached
                  and head_state.branch_name
                or nil
              local match_branch_name = attached_branch_name or result_branch_name
              local match_branch_ref = attached_branch_name
                  and ('refs/heads/' .. attached_branch_name)
                or branch_ref
              if not match_branch_ref then
                open_detached_overview(
                  repository_root,
                  resolved_commit,
                  already_at_commit,
                  head_state.detached,
                  parent_view,
                  operation,
                  nil,
                  { source = result_source }
                )
                return
              end
              repository.start(
                repository.commands.commit_is_ancestor(resolved_commit, match_branch_ref),
                repository_root,
                function(ancestor_process)
                  local context_for_render
                  if ancestor_process.code == 0 then
                    context_for_render = {
                      anchor_plan = {
                        branch_name = match_branch_name,
                        branch_ref = match_branch_ref,
                        branch_tip_commit = attached_branch_name
                            and head_state.commit
                          or prepared_branch_tip,
                        source = attached_branch_name and 'LOCAL' or result_source,
                      },
                      branch_name = match_branch_name,
                      branch_ref = match_branch_ref,
                      branch_tip_commit = attached_branch_name
                          and head_state.commit
                        or prepared_branch_tip,
                      source = attached_branch_name and 'LOCAL' or result_source,
                    }
                  else
                    log_anchor_operation(
                      operation,
                      'current branch does not contain the target; rendering the commit independently',
                      'info'
                    )
                    context_for_render = { source = result_source }
                  end
                  open_detached_overview(
                    repository_root,
                    resolved_commit,
                    already_at_commit,
                    head_state.detached,
                    parent_view,
                    operation,
                    nil,
                    context_for_render
                  )
                end
              )
            end
            if result_source ~= 'LOCAL'
                or not result_branch_name
                or prepared_branch_tip ~= resolved_commit then
              continue_anchor(nil)
              return
            end
            local local_branch_name = result_branch_name:match('^refs/heads/(.+)$')
              or result_branch_name
            local local_branch_ref = branch_ref or ('refs/heads/' .. local_branch_name)
            repository.start(repository.commands.resolve_commit(local_branch_ref), repository_root,
              function(branch_tip_process)
                if branch_tip_process.code ~= 0 then
                  log_anchor_operation(
                    operation,
                    'prepared local branch tip could not be verified; retaining detached checkout',
                    'warn'
                  )
                  continue_anchor(nil)
                  return
                end
                local current_tip_lines = repository.output_lines(branch_tip_process.stdout)
                if current_tip_lines[1] == resolved_commit then
                  log_anchor_operation(
                    operation,
                    'prepared target is current local branch tip; attaching ' .. local_branch_name,
                    'info'
                  )
                  continue_anchor(local_branch_name)
                  return
                end
                log_anchor_operation(
                  operation,
                  'prepared local branch tip changed; retaining detached checkout',
                  'warn'
                )
                continue_anchor(nil)
              end)
          end

          local anchor_plan = selected_context.anchor_plan or {}
          local reviewed_branch_name = anchor_plan.branch_name or selected_context.branch_name
          if reviewed_branch_name then
            log_anchor_operation(operation, 'reusing current review branch anchor plan', 'info')
            continue_with_location(
              anchor_plan.source or selected_context.source,
              reviewed_branch_name,
              anchor_plan.branch_ref,
              anchor_plan.branch_tip_commit
            )
            return
          end
          log_anchor_operation(operation, 'no reviewed branch; using exact commit anchor', 'info')
          continue_with_location(selected_context.source or 'LOCAL', nil, nil, nil)
        end)
    end)
  return true
end

function M.branches(root)
  local selected_root = root or project.detect_repository(vim.uv.cwd())
  if not selected_root then
    vim.notify('No Git repository is available for branch selection', vim.log.levels.INFO)
    return
  end
  local repository_root = vim.fs.normalize(selected_root)
  local query_picker = require('config.search.query_picker')
  local session = query_picker.open({
    title = ('Git Branches · Enter: review · max %d'):format(repository.max_branch_entries),
    picker_options = ui.picker_options(repository_root),
    entry_maker = ui.entry,
    previewer = require('telescope.previewers').git_branch_log.new({ cwd = repository_root }),
    sorter = require('telescope.config').values.generic_sorter({}),
    attach_mappings = function(prompt_buffer, map)
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')
      local picker = action_state.get_current_picker(prompt_buffer)
      picker.close_preview_with_ctrl_q = true
      picker.focus_layout = ui.focus_layout
      local function close_branch_picker(active_prompt_buffer)
        actions.close(active_prompt_buffer)
      end
      picker.ctrl_q_action = function()
        close_branch_picker(prompt_buffer)
      end
      actions.select_default:replace(function(active_prompt_buffer)
        local selected_entry = action_state.get_selected_entry()
        if selected_entry then
          repository.start(repository.commands.head_state(), repository_root,
            function(head_process)
              if head_process.code ~= 0 then
                vim.notify(repository.concise_error(head_process), vim.log.levels.ERROR)
                return
              end
              local head_state = repository.parse_head_state(head_process.stdout)
              render_branch_review(
                repository_root,
                active_prompt_buffer,
                selected_entry.branch,
                nil,
                head_state
              )
            end)
        end
      end)
      map({ 'i', 'n' }, panel.close_key, close_branch_picker, { desc = 'Close branch picker' })
      map({ 'i', 'n' }, '<Tab>', function(active_prompt_buffer)
        require('config.search.telescope').focus_preview(active_prompt_buffer)
      end, { desc = 'Focus branch preview' })
      return true
    end,
  })

  local cancel_process = repository.start(repository.commands.branches(), repository_root,
    function(completed_process)
      if completed_process.code ~= 0 then
        session:fail(repository.concise_error(completed_process))
        return
      end
      local branch_records = {}
      for _, branch in ipairs(repository.parse_branches(completed_process.stdout)) do
        branch_records[#branch_records + 1] = ui.branch_record(branch)
      end
      session:finish(branch_records)
    end)
  session:add_cancel(cancel_process)
end

return M
