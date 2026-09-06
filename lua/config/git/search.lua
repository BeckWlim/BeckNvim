local github = require('config.git.github')
local issue_view = require('config.git.issue')
local panel = require('config.git.panel')
local repository = require('config.git.repository')
local ui = require('config.git.ui')

local M = {}

local function is_commit_id(query)
  return #query >= 7 and #query <= 64 and query:match('^[0-9a-fA-F]+$') ~= nil
end

local function search_previewer(root)
  local previewers = require('telescope.previewers')
  return previewers.new_buffer_previewer({
    title = 'Git Result Preview',
    get_buffer_by_name = function(_, entry)
      return ('git-search://%s/%s'):format(entry.kind, entry.value)
    end,
    define_preview = function(previewer, entry)
      local preview_buffer = previewer.state.bufnr
      if entry.kind == 'issue' then
        issue_view.render_buffer(preview_buffer, entry.issue)
        return
      end
      if entry.kind == 'remote_error' then
        ui.render_preview_buffer(preview_buffer, ui.remote_error_preview(entry))
        return
      end
      if entry.kind == 'branch' then
        local branch_command = repository.commands.branch_preview(entry.branch, entry.commits)
        repository.start(branch_command, root, function(process)
            if vim.api.nvim_buf_is_valid(preview_buffer) and process.code == 0 then
              local commits = repository.parse_commit_preview(process.stdout or '')
              ui.render_preview_buffer(
                preview_buffer,
                ui.branch_preview(entry.branch, commits)
              )
            end
        end)
        return
      end
      local command = repository.commands.commit_preview(entry.commit.hash)
      repository.start(command, root, function(process)
          if vim.api.nvim_buf_is_valid(preview_buffer) and process.code == 0 then
            local commits = repository.parse_commit_preview(process.stdout or '')
            local commit = commits[1] or {
              abbreviated_hash = entry.commit.hash,
              author = '',
              date = '',
              files = {},
              hash = entry.commit.hash,
              subject = 'Commit details unavailable',
            }
            ui.render_preview_buffer(preview_buffer, ui.commit_preview(entry, commit))
          end
      end)
    end,
  })
end

local function emit_records(records, process_result)
  for record_index, record in ipairs(records) do
    record.index = record_index
    if process_result(record) then
      return false
    end
  end
  return true
end

local function commit_target(commit, branch)
  local history_ref = branch and (branch.refname or branch.short_name)
    or commit.source_ref
    or commit.branch_name
  return {
    anchor_plan = branch and {
      branch_name = branch.short_name or branch.refname,
      branch_ref = branch.refname or branch.short_name,
      branch_tip_commit = branch.tip_commit,
      source = branch.is_remote and 'REMOTE' or 'LOCAL',
    } or nil,
    branch_name = branch and (branch.short_name or branch.refname) or commit.branch_name,
    hash = commit.hash,
    history_ref = history_ref,
    source = commit.source,
  }
end

local function review_commit(context, commit, branch)
  local target_commit = commit_target(commit, branch)
  require('config.git.diffview').jump_to_search_commit(
    context.parent_view,
    context.history_options,
    target_commit
  )
end

local function review_commit_id(context, commit_id)
  local function resolve(fetch_attempted)
    repository.start(repository.commands.resolve_commit(commit_id), context.root, function(resolve_process)
      if resolve_process.code ~= 0 then
        if not fetch_attempted then
          vim.notify(('Fetching remotes to find commit %s…'):format(commit_id:sub(1, 12)), vim.log.levels.INFO)
          repository.start(repository.commands.remotes(), context.root, function(remote_process)
            local remote = (remote_process.stdout or ''):match('([^\n]+)')
            if not remote then
              vim.notify(('No Git remote is configured for commit %s'):format(commit_id), vim.log.levels.ERROR)
              return
            end
            repository.start({ 'git', 'fetch', remote, commit_id }, context.root, function(fetch_process)
            if fetch_process.code == 0 then
              resolve(true)
            else
              vim.notify(repository.concise_error(fetch_process), vim.log.levels.ERROR)
            end
            end)
          end)
          return
        end
        vim.notify(
          ('Commit %s is not present in the current repository'):format(commit_id),
          vim.log.levels.ERROR
        )
        return
      end
      local resolved_commit = repository.parse_resolved_commit(resolve_process.stdout)
      if not resolved_commit then
        vim.notify(('Commit not found: %s'):format(commit_id), vim.log.levels.ERROR)
        return
      end
      review_commit(context, {
        hash = resolved_commit,
        source = 'LOCAL',
      })
    end)
  end
  resolve(false)
end

local function search_finder(context, close_callback)
  local active_generation = 0
  local cancel_functions = {}

  local function cancel_active_requests()
    active_generation = active_generation + 1
    for _, cancel_function in ipairs(cancel_functions) do
      cancel_function()
    end
    cancel_functions = {}
  end

  local finder = {
    close = function()
      cancel_active_requests()
      close_callback()
    end,
  }
  return setmetatable(finder, {
    __call = function(_, prompt, process_result, process_complete)
      cancel_active_requests()
      local query = vim.trim(prompt)
      context.query = query
      local cached_records = context.cache[query]
      if cached_records then
        context.records = cached_records
        if emit_records(cached_records, process_result) then
          process_complete()
        end
        return
      end
      if query ~= '' and is_commit_id(query) then
        local commit_id_record = ui.commit_id_record(query)
        context.records = { commit_id_record }
        if emit_records(context.records, process_result) then
          process_complete()
        end
        return
      end

      local query_generation = active_generation
      vim.defer_fn(function()
        if query_generation ~= active_generation then
          return
        end
        local commit_number = query:match('^#(%d+)$')
        local branches = {}
        local containing_refs = context.detached_containing_refs or {}
        local matching_commits = {}
        local issue_record
        local remote_error_record
        local branches_ready = false
        local detached_commit = context.history_options.detached_head_commit
        local containing_refs_ready = detached_commit == nil
          or context.detached_containing_refs ~= nil
        local commits_ready = query == ''
        local issue_ready = commit_number == nil
        local local_records_emitted = false
        local request_completed = false

        local function issue_result_record()
          return issue_record or remote_error_record
        end

        local function finish_if_ready()
          if query_generation ~= active_generation
              or not branches_ready
              or not containing_refs_ready
              or not commits_ready
              or request_completed then
            return
          end
          local prioritized_branches = detached_commit
              and repository.prioritize_detached_branches(
                branches,
                detached_commit,
                containing_refs,
                context.history_options.branch_name
              )
            or branches
          local combined_records = {}
          local normalized_query = query:lower()
          local branch_records = {}
          local branch_record_by_source = {}
          local current_branch_record
          for _, branch in ipairs(prioritized_branches) do
            local branch_record = ui.branch_record(branch)
            branch_records[#branch_records + 1] = branch_record
            branch_record_by_source[branch.refname] = branch_record
            branch_record_by_source[branch.short_name] = branch_record
            if branch.current and not branch.is_remote then
              current_branch_record = branch_record
            end
          end

          local commits_by_branch = {}
          local fallback_branch_record
          for _, commit in ipairs(matching_commits) do
            local owning_branch_record = branch_record_by_source[commit.source_ref]
              or current_branch_record
            if not owning_branch_record then
              fallback_branch_record = fallback_branch_record or ui.branch_record({
                current = true,
                date = '',
                is_remote = false,
                refname = 'HEAD',
                short_name = 'DETACHED',
                subject = '',
                upstream = '',
              })
              owning_branch_record = fallback_branch_record
            end
            commit.source = owning_branch_record.branch.is_remote and 'REMOTE' or 'LOCAL'
            local branch_commits = commits_by_branch[owning_branch_record] or {}
            branch_commits[#branch_commits + 1] = commit
            commits_by_branch[owning_branch_record] = branch_commits
          end

          local function append_branch(branch_record, branch_commits)
            local rendered_branch_record = branch_record
            if branch_commits then
              rendered_branch_record = ui.branch_record(
                branch_record.branch,
                #branch_commits
              )
              rendered_branch_record.commits = branch_commits
            end
            combined_records[#combined_records + 1] = rendered_branch_record
            for _, commit in ipairs(branch_commits or {}) do
              local commit_record = ui.commit_record(commit)
              commit_record.branch = rendered_branch_record.branch
              combined_records[#combined_records + 1] = commit_record
            end
          end

          for _, branch_record in ipairs(branch_records) do
            local branch_commits = commits_by_branch[branch_record]
            if branch_commits
                or normalized_query == ''
                or branch_record.ordinal:lower():find(normalized_query, 1, true) then
              append_branch(branch_record, branch_commits)
            end
          end
          if fallback_branch_record and commits_by_branch[fallback_branch_record] then
            append_branch(fallback_branch_record, commits_by_branch[fallback_branch_record])
          end

          local resolved_issue_record = issue_result_record()
          if issue_ready and resolved_issue_record then
            combined_records[#combined_records + 1] = resolved_issue_record
          end
          context.query = query
          context.records = combined_records

          if not local_records_emitted then
            local_records_emitted = true
            if not emit_records(combined_records, process_result) then
              return
            end
          elseif issue_ready and resolved_issue_record then
            resolved_issue_record.index = #combined_records
            if process_result(resolved_issue_record) then
              return
            end
          end

          if not issue_ready then
            return
          end
          request_completed = true
          if not remote_error_record then
            context.cache[query] = combined_records
          end
          process_complete()
        end

        cancel_functions[#cancel_functions + 1] = repository.start(
          repository.commands.branches(),
          context.root,
          function(completed_process)
            if query_generation ~= active_generation then
              return
            end
            branches_ready = true
            if completed_process.code == 0 then
              branches = repository.parse_branches(completed_process.stdout)
            else
              vim.notify(repository.concise_error(completed_process), vim.log.levels.ERROR)
            end
            finish_if_ready()
          end
        )

        if detached_commit and not containing_refs_ready then
          cancel_functions[#cancel_functions + 1] = repository.start(
            repository.commands.commit_sources(detached_commit),
            context.root,
            function(completed_process)
              if query_generation ~= active_generation then
                return
              end
              containing_refs_ready = true
              if completed_process.code == 0 then
                containing_refs = repository.parse_containing_refs(completed_process.stdout)
                context.detached_containing_refs = containing_refs
              else
                vim.notify(repository.concise_error(completed_process), vim.log.levels.WARN)
              end
              finish_if_ready()
            end
          )
        end

        if query ~= '' then
          local commit_command = repository.commands.search_commits(query, context.history_options)
          cancel_functions[#cancel_functions + 1] = repository.start(
            commit_command,
            context.root,
            function(completed_process)
              if query_generation ~= active_generation then
                return
              end
              commits_ready = true
              if completed_process.code == 0 then
                local commits = repository.parse_commit_search(
                  completed_process.stdout,
                  commit_number
                )
                matching_commits = commits
              else
                vim.notify(repository.concise_error(completed_process), vim.log.levels.ERROR)
              end
              finish_if_ready()
            end
          )
        end

        if commit_number then
          cancel_functions[#cancel_functions + 1] = github.fetch_issue(
            context.root,
            commit_number,
            function(issue, issue_error)
              if query_generation ~= active_generation then
                return
              end
              issue_ready = true
              if issue then
                issue_record = ui.issue_record(issue)
              elseif issue_error then
                remote_error_record = ui.remote_error_record('GitHub', issue_error)
              end
              finish_if_ready()
            end
          )
        end
      end, 120)
    end,
  })
end

local function open_picker(context, restore_query)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local picker_options = ui.picker_options(context.root)
  picker_options.default_text = restore_query
  local picker_owner = {}
  local function leave_search_layer()
    panel.leave_search(picker_owner)
  end
  local picker = require('telescope.pickers').new(picker_options, {
    prompt_title = 'Git Search · Enter: open',
    finder = search_finder(context, leave_search_layer),
    previewer = search_previewer(context.root),
    sorter = require('telescope.sorters').empty(),
    attach_mappings = function(prompt_buffer, map)
      local active_picker = action_state.get_current_picker(prompt_buffer)
      active_picker.close_preview_with_ctrl_q = true
      active_picker.focus_layout = ui.focus_layout
      local function close_search_panel(active_prompt_buffer)
        leave_search_layer()
        actions.close(active_prompt_buffer)
      end
      panel.enter_search(picker_owner, function()
        actions.close(prompt_buffer)
      end)
      active_picker.ctrl_q_action = function()
        panel.pop()
      end
      local function notify_commit_cursor_required()
        vim.notify('Move the preview cursor onto a commit or file row', vim.log.levels.INFO)
      end
      active_picker.preview_enter_action = function(active_prompt_buffer)
        local selected_entry = action_state.get_selected_entry()
        if not selected_entry or selected_entry.kind ~= 'branch' then
          actions.select_default(active_prompt_buffer)
          return
        end
        local previewer = active_picker.previewer
        local preview_window = previewer and previewer.state and previewer.state.winid
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
          notify_commit_cursor_required()
          return
        end
        local preview_buffer = vim.api.nvim_win_get_buf(preview_window)
        local cursor_row = vim.api.nvim_win_get_cursor(preview_window)[1]
        local commit_by_line = vim.b[preview_buffer].git_search_commit_by_line or {}
        local commit_hash = commit_by_line[cursor_row]
        if not commit_hash or commit_hash == vim.NIL then
          notify_commit_cursor_required()
          return
        end
        close_search_panel(active_prompt_buffer)
        review_commit(
          context,
          {
            hash = commit_hash,
            source = selected_entry.branch.is_remote and 'REMOTE' or 'LOCAL',
          },
          selected_entry.branch
        )
      end
      actions.select_default:replace(function(active_prompt_buffer)
        local selected_entry = action_state.get_selected_entry()
        if not selected_entry then
          return
        end
        if selected_entry.kind == 'remote_error' then
          vim.notify(selected_entry.error, vim.log.levels.ERROR)
          return
        end
        local dispatched_query = context.query
        close_search_panel(active_prompt_buffer)
        if selected_entry.kind == 'issue' then
          issue_view.open_file(context.root, selected_entry.issue, {
            parent_tabpage = context.parent_tabpage,
            return_to_results = function()
              open_picker(context, dispatched_query)
            end,
          })
        elseif selected_entry.kind == 'branch' then
          require('config.git').review_branch(
            context.root,
            selected_entry.branch,
            context.parent_view
          )
        elseif selected_entry.kind == 'commit_id' then
          review_commit_id(context, selected_entry.commit.hash)
        else
          review_commit(context, selected_entry.commit, selected_entry.branch)
        end
      end)
      map({ 'i', 'n' }, panel.close_key, function()
        panel.pop()
      end, { desc = 'Close current Git panel layer' })
      map({ 'i', 'n' }, '<Tab>', function(active_prompt_buffer)
        require('config.search.telescope').focus_preview(active_prompt_buffer)
      end, { desc = 'Focus Git result preview' })
      return true
    end,
  })
  picker:find()
  return true
end

function M.open(root, history_options, parent_view)
  local context = {
    cache = {},
    history_options = vim.deepcopy(history_options or {}),
    parent_tabpage = parent_view and parent_view.tabpage or vim.api.nvim_get_current_tabpage(),
    parent_view = parent_view,
    query = '',
    records = {},
    root = vim.fs.normalize(root),
  }
  return open_picker(context)
end

return M
