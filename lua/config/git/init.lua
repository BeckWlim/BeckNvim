local project = require('config.project')
local panel = require('config.git.panel')
local repository = require('config.git.repository')
local ui = require('config.git.ui')

local M = {}
local commit_transitioning = false

local function current_location()
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

  local cursor = vim.api.nvim_win_get_cursor(0)
  local structure = require('config.syntax.treesitter_context').enclosing_structure(
    source_buffer,
    cursor[1] - 1,
    cursor[2]
  )
  return {
    relative_path = relative_path,
    root = repository_root,
    structure = structure,
  }
end

local function current_repository()
  local source_path = vim.api.nvim_buf_get_name(0)
  local source_repository = source_path ~= '' and project.detect_repository(source_path) or nil
  local working_repository = project.detect_repository(vim.uv.cwd())
  local repository_root = source_repository or working_repository
  if not repository_root then
    return nil, 'No Git repository is available for repository history'
  end
  return {
    root = repository_root,
  }
end

local function open_history(kind)
  local location, location_error
  if kind == 'repository' then
    location, location_error = current_repository()
  else
    location, location_error = current_location()
  end
  if not location then
    vim.notify(location_error, vim.log.levels.INFO)
    return
  end
  if kind == 'symbol' and not location.structure then
    vim.notify('Place the cursor inside a function or class for symbol history', vim.log.levels.INFO)
    return
  end

  local history_range = kind == 'symbol' and {
    location.structure.first_line,
    location.structure.last_line,
  } or nil
  require('config.git.diffview').open_file_history({
    kind = kind,
    location = location,
    range = history_range,
  })
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

function M.search_repository()
  local git_diffview = require('config.git.diffview')
  if git_diffview.is_active() then
    return git_diffview.search()
  end
  local location, location_error = current_repository()
  if not location then
    vim.notify(location_error, vim.log.levels.INFO)
    return false
  end
  local history_options = {
    kind = 'repository',
    location = location,
  }
  local view = git_diffview.open_file_history(history_options)
  if not view then
    return false
  end
  return require('config.git.search').open(location.root, history_options, view)
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

local function switch_branch(root, prompt_buffer, branch, parent_view)
  local modified_paths = modified_repository_buffers(root)
  if #modified_paths > 0 then
    notify_modified_buffers(modified_paths, 'switching branches')
    return
  end

  if prompt_buffer then
    require('telescope.actions').close(prompt_buffer)
  end
  local git_diffview = require('config.git.diffview')
  if not parent_view then
    git_diffview.close()
  end
  repository.start(repository.commands.switch_branch(branch), root, function(completed_process)
    if completed_process.code ~= 0 then
      vim.notify(repository.concise_error(completed_process), vim.log.levels.ERROR)
      return
    end
    vim.cmd('checktime')
    if parent_view then
      git_diffview.replace_file_history(parent_view, {
        branch_name = branch.local_name,
        kind = 'repository',
        location = { root = root },
        source = 'LOCAL',
      })
    end
    vim.notify(('Switched to branch %s'):format(branch.local_name), vim.log.levels.INFO)
  end)
end

function M.switch_to_branch(root, branch, parent_view)
  return switch_branch(vim.fs.normalize(root), nil, branch, parent_view)
end

local function render_commit_overview(
    repository_root,
    commit_hash,
    source,
    branch_name,
    parent_view
)
  local git_diffview = require('config.git.diffview')
  local history_options = {
    branch_name = branch_name,
    history_ref = branch_name or commit_hash,
    kind = 'repository',
    location = { root = repository_root },
    selected_commit = commit_hash,
    source = source,
    unbounded = true,
  }
  if parent_view then
    if git_diffview.focus_history_commit(parent_view, commit_hash) then
      return
    end
    git_diffview.replace_file_history(parent_view, history_options)
    return
  end
  git_diffview.close()
  git_diffview.open_file_history(history_options)
end

local function open_detached_overview(
    repository_root,
    commit_hash,
    already_at_commit,
    source,
    branch_name,
    parent_view
)
  if already_at_commit then
    commit_transitioning = false
    render_commit_overview(repository_root, commit_hash, source, branch_name, parent_view)
    vim.notify(
      ('Already at %s; kept the current HEAD'):format(commit_hash:sub(1, 12)),
      vim.log.levels.INFO
    )
    return
  end

  repository.start(repository.commands.detach_commit(commit_hash), repository_root,
    function(completed_process)
      commit_transitioning = false
      if completed_process.code ~= 0 then
        vim.notify(repository.concise_error(completed_process), vim.log.levels.ERROR)
        return
      end
      vim.cmd('checktime')
      render_commit_overview(repository_root, commit_hash, source, branch_name, parent_view)
      vim.notify(
        ('Detached at %s; opened commit overview'):format(commit_hash:sub(1, 12)),
        vim.log.levels.INFO
      )
    end)
end

function M.detach_commit_overview(root, commit_id, parent_view, commit_context)
  if commit_transitioning then
    vim.notify('A commit overview transition is already running', vim.log.levels.INFO)
    return false
  end
  local repository_root = vim.fs.normalize(root)
  commit_transitioning = true
  repository.start(repository.commands.resolve_commit(commit_id), repository_root,
    function(resolve_process)
      if resolve_process.code ~= 0 then
        commit_transitioning = false
        vim.notify(repository.concise_error(resolve_process), vim.log.levels.ERROR)
        return
      end
      local resolved_lines = repository.output_lines(resolve_process.stdout)
      local resolved_commit = resolved_lines[1]
      if not resolved_commit then
        commit_transitioning = false
        vim.notify(('Commit not found: %s'):format(commit_id), vim.log.levels.ERROR)
        return
      end
      repository.start(repository.commands.head_state(), repository_root,
        function(head_process)
          if head_process.code ~= 0 then
            commit_transitioning = false
            vim.notify(repository.concise_error(head_process), vim.log.levels.ERROR)
            return
          end
          local head_state = repository.parse_head_state(head_process.stdout)
          local already_at_commit = head_state.commit == resolved_commit
          if not already_at_commit then
            if head_state.dirty then
              commit_transitioning = false
              vim.notify(
                'Commit overview refused because the Git workspace is dirty',
                vim.log.levels.WARN
              )
              return
            end
            local modified_paths = modified_repository_buffers(repository_root)
            if #modified_paths > 0 then
              commit_transitioning = false
              notify_modified_buffers(modified_paths, 'detaching HEAD')
              return
            end
          end
          repository.start(repository.commands.commit_sources(resolved_commit), repository_root,
            function(source_process)
              if source_process.code ~= 0 then
                commit_transitioning = false
                vim.notify(repository.concise_error(source_process), vim.log.levels.ERROR)
                return
              end
              local commit_location = repository.parse_commit_location(source_process.stdout)
              local selected_context = commit_context or {}
              local result_source = selected_context.source or commit_location.source
              local result_branch_name = selected_context.branch_name
                or commit_location.branch_name
              open_detached_overview(
                repository_root,
                resolved_commit,
                already_at_commit,
                result_source,
                result_branch_name,
                parent_view
              )
            end)
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
    title = ('Git Branches · Enter: switch · max %d'):format(repository.max_branch_entries),
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
          switch_branch(repository_root, active_prompt_buffer, selected_entry.branch, nil)
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

function M.return_to_inspector()
  return require('config.git.diffview').return_to_inspector()
end

return M
