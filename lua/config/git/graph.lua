local panel = require('config.git.panel')
local repository = require('config.git.repository')
local project = require('config.project')
local subject = require('config.git.subject')
local session = require('config.git.session')

local M = {}
local active
local list_namespace = vim.api.nvim_create_namespace('config-git-graph-list')
local branch_namespace = vim.api.nvim_create_namespace('config-git-graph-branches')

local function clear_autocmds(view)
  for _, id in ipairs(view.autocmds or {}) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  view.autocmds = {}
end

local function set_lines(buffer, lines)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
end

local function fit_cells(value, width)
  if vim.fn.strdisplaywidth(value) <= width then
    return value
  end
  local count = vim.fn.strchars(value)
  while count > 0 do
    local head = vim.fn.strcharpart(value, 0, count)
    if vim.fn.strdisplaywidth(head) + 1 <= width then
      return head .. '…'
    end
    count = count - 1
  end
  return '…'
end

local function pad_cells(value, width)
  return value .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(value)))
end

local function primary_ref(refs)
  local ref = refs:match('HEAD %-> ([^,]+)') or refs:match('^([^,]+)')
  if not ref then
    return nil
  end
  if vim.startswith(ref, 'tag: ') then
    return 't:' .. ref:sub(6)
  end
  return ref
end

local function is_head_ref(refs)
  return vim.startswith(refs, 'HEAD') or refs:find(', HEAD', 1, true) ~= nil
end

local function add_highlight(highlights, row, start_col, value, group, priority)
  if value == '' then
    return
  end
  highlights[#highlights + 1] = {
    row = row,
    start_col = start_col,
    end_col = start_col + #value,
    group = group,
    priority = priority or 140,
  }
end

local function commit_badges(commit, head, fork_anchors)
  local chunks = {}
  if commit.kind == 'worktree' then
    chunks[#chunks + 1] = { '[WORKTREE]', 'DiagnosticWarn' }
  elseif head then
    chunks[#chunks + 1] = { '[HEAD]', 'DiagnosticOk' }
  else
    local ref = primary_ref(commit.refs or '')
    if ref then
      chunks[#chunks + 1] = { '[' .. ref .. ']', 'Directory' }
    end
  end
  local anchors = fork_anchors and fork_anchors[commit.hash]
  if anchors and #anchors > 0 then
    local name = anchors[1]
    local more = #anchors > 1 and ('+' .. (#anchors - 1)) or ''
    if #chunks > 0 then
      chunks[#chunks + 1] = { ' ', 'Comment' }
    end
    chunks[#chunks + 1] = { '[' .. name .. more .. '↗]', 'DiagnosticInfo' }
  end
  if #chunks > 0 then
    chunks[#chunks + 1] = { ' ', 'Comment' }
  end
  return chunks
end

function M.format_history(rows, head_hash, fork_anchors)
  local lines, commits, highlights, badges = {}, {}, {}, {}
  for row_index, row in ipairs(rows) do
    local graph = row.commit and row.graph:gsub('%s+$', '') or row.graph
    if row.commit then
      local commit = row.commit
      commits[row_index] = commit
      local head = commit.hash == head_hash or is_head_ref(commit.refs or '')
      local chunks = commit_badges(commit, head, fork_anchors)
      if #chunks > 0 then
        badges[#badges + 1] = { row = row_index - 1, chunks = chunks }
      end
      local short_hash = commit.kind == 'worktree' and '·' or commit.hash:sub(1, 8)
      local prefix = graph .. ' ' .. short_hash .. ' '
      add_highlight(highlights, row_index - 1, #graph + 1,
        short_hash, 'DiagnosticHint')
      for _, span in ipairs(subject.spans(commit.subject)) do
        add_highlight(highlights, row_index - 1, #prefix + span.start_col,
          commit.subject:sub(span.start_col + 1, span.end_col), span.group, 150)
      end
      lines[row_index] = prefix .. commit.subject
    else
      lines[row_index] = graph
    end
    add_highlight(highlights, row_index - 1, 0, graph, 'DiagnosticInfo', 120)
    local node = graph:find('◆', 1, true) and '◆' or graph:find('●', 1, true) and '●'
    if node then
      local node_start = assert(graph:find(node, 1, true))
      add_highlight(highlights, row_index - 1, node_start - 1, node,
        node == '◆' and 'DiagnosticWarn' or 'DiagnosticOk', 160)
    end
  end
  return { lines = lines, commits = commits, highlights = highlights, badges = badges }
end

function M.with_worktree(rows, state)
  if not state or not state.dirty or not state.commit then return rows end
  local result = {}
  for _, row in ipairs(rows) do
    if row.commit and row.commit.hash == state.commit then
      result[#result + 1] = {
        graph = row.graph:gsub('◆', '●'),
        commit = { kind = 'worktree', hash = repository.worktree_hash, subject = 'Working tree changes',
          refs = '', parents = { state.commit } },
      }
    end
    result[#result + 1] = row
  end
  return result
end

function M.format_branches(branches, pane_width)
  local name_width = math.max(10, math.min(16, math.floor(pane_width * 0.34)))
  local lines, highlights = {}, {}
  for row_index, branch in ipairs(branches) do
    local mark = branch.current and '●' or ' '
    local scope = branch.is_remote and 'REMOTE' or 'LOCAL '
    local display_name = branch.short_name
    if branch.is_remote then
      local remote, branch_path = display_name:match('^([^/]+)/(.+)$')
      if remote and branch_path then
        display_name = remote:sub(1, 1) .. '/' .. branch_path
      end
    end
    local name = fit_cells(display_name, name_width)
    local name_padded = pad_cells(name, name_width)
    local subject = branch.subject or ''
    lines[row_index] = mark .. ' ' .. scope .. ' ' .. name_padded .. '  ' .. subject
    if branch.current then
      add_highlight(highlights, row_index - 1, 0, mark, 'DiagnosticOk', 160)
    end
    add_highlight(highlights, row_index - 1, #mark + 1, scope,
      branch.is_remote and 'DiagnosticInfo' or 'DiagnosticOk')
    add_highlight(highlights, row_index - 1, #mark + 1 + #scope + 1,
      name, 'Directory')
  end
  return { lines = lines, highlights = highlights }
end

local function apply_highlights(buffer, namespace, highlights)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  for _, highlight in ipairs(highlights) do
    local line = lines[highlight.row + 1] or ''
    local end_col = math.min(highlight.end_col, #line)
    if highlight.start_col < end_col then
      vim.api.nvim_buf_set_extmark(buffer, namespace,
        highlight.row, highlight.start_col, {
          end_col = end_col,
          hl_group = highlight.group,
          priority = highlight.priority,
        })
    end
  end
end

local function render_history(view)
  local formatted = M.format_history(view.history_rows, view.head_commit, view.fork_anchors)
  view.commits = formatted.commits
  set_lines(view.list_buffer, #formatted.lines > 0 and formatted.lines or { 'No commits found.' })
  apply_highlights(view.list_buffer, list_namespace, formatted.highlights)
  for _, badge in ipairs(formatted.badges) do
    vim.api.nvim_buf_set_extmark(view.list_buffer, list_namespace, badge.row, 0, {
      virt_text = badge.chunks,
      virt_text_pos = 'right_align',
      hl_mode = 'combine',
      priority = 180,
    })
  end
end

local function cancel_fork_anchors(view)
  view.anchor_generation = (view.anchor_generation or 0) + 1
  if view.cancel_anchor_list then
    view.cancel_anchor_list()
    view.cancel_anchor_list = nil
  end
  for _, cancel_job in pairs(view.anchor_jobs or {}) do
    cancel_job()
  end
  view.anchor_jobs = {}
end

local function load_fork_anchors(view)
  cancel_fork_anchors(view)
  view.fork_anchors = {}
  local generation = view.anchor_generation
  local visible = {}
  for _, row in ipairs(view.history_rows or {}) do
    if row.commit then
      visible[row.commit.hash] = true
    end
  end
  local function current()
    return active == view and generation == view.anchor_generation
  end
  local function schedule_render()
    if view.anchor_render_scheduled then
      return
    end
    view.anchor_render_scheduled = true
    vim.schedule(function()
      view.anchor_render_scheduled = false
      if current() then
        render_history(view)
      end
    end)
  end
  view.cancel_anchor_list = repository.start(repository.commands.branches(), view.root,
    function(result)
      if not current() then
        return
      end
      view.cancel_anchor_list = nil
      if result.code ~= 0 then
        return
      end
      local by_tip = {}
      for _, branch in ipairs(repository.parse_branches(result.stdout)) do
        local tip = branch.tip_commit
        if tip ~= '' and not visible[tip] and branch.refname ~= view.history_ref then
          local group = by_tip[tip]
          if not group then
            group = { refname = branch.refname, names = {} }
            by_tip[tip] = group
          end
          local name = branch.is_remote
              and branch.short_name:match('^[^/]+/(.+)$') or branch.short_name
          group.names[name or branch.short_name] = true
        end
      end
      local groups = {}
      for _, group in pairs(by_tip) do
        groups[#groups + 1] = group
      end
      local next_group, active_jobs = 1, 0
      local function pump()
        while current() and active_jobs < 4 and next_group <= #groups do
          local job_index = next_group
          local group = groups[job_index]
          next_group = next_group + 1
          active_jobs = active_jobs + 1
          view.anchor_jobs[job_index] = repository.start(
            repository.commands.branch_fork_point(view.history_ref, group.refname),
            view.root, function(fork_result)
              if not current() then
                return
              end
              view.anchor_jobs[job_index] = nil
              active_jobs = active_jobs - 1
              local fork_hash = fork_result.code == 0
                  and repository.output_lines(fork_result.stdout)[1] or nil
              if fork_hash and visible[fork_hash] then
                local names = view.fork_anchors[fork_hash] or {}
                local existing = {}
                for _, name in ipairs(names) do existing[name] = true end
                for name in pairs(group.names) do
                  if not existing[name] then
                    names[#names + 1] = name
                  end
                end
                table.sort(names)
                view.fork_anchors[fork_hash] = names
                schedule_render()
              end
              pump()
            end)
        end
      end
      pump()
    end)
end

local function render_branches(view)
  local formatted = M.format_branches(view.branches,
    vim.api.nvim_win_get_width(view.branch_window))
  set_lines(view.branch_buffer, #formatted.lines > 0 and formatted.lines or { 'No branches found.' })
  apply_highlights(view.branch_buffer, branch_namespace, formatted.highlights)
end

local function update_history_winbar(view)
  if not vim.api.nvim_win_is_valid(view.list_window) then
    return
  end
  local branch = view.current_branch or 'HEAD'
  local branch_width = math.max(8, math.floor(
    vim.api.nvim_win_get_width(view.list_window) * 0.42))
  local display_branch = fit_cells(branch, branch_width):gsub('%%', '%%%%')
  local scope = view.history_ref ~= 'HEAD'
      and (' · view ' .. fit_cells(view.history_ref:gsub('^refs/heads/', '')
        :gsub('^refs/remotes/', ''), branch_width):gsub('%%', '%%%%'))
    or ''
  vim.wo[view.list_window].winbar =
    (' Git %s%s · <Space>db branches '):format(display_branch, scope)
end

local function cancel_preview(view)
  view.preview_generation = view.preview_generation + 1
  if view.cancel_message then
    view.cancel_message()
    view.cancel_message = nil
  end
  if view.cancel_files then
    view.cancel_files()
    view.cancel_files = nil
  end
end

local function render_preview(view, commit)
  local previous = view.rendered_preview_hash == commit.hash
    and session.capture_window(view.preview_window) or nil
  local detail = view.cache[commit.hash] or {}
  local lines = vim.split(detail.message or commit.subject, '\n', { plain = true })
  while lines[#lines] == '' do
    table.remove(lines)
  end
  if #lines == 0 then
    lines = { '[empty commit message]' }
  end
  vim.list_extend(lines, {
    '',
    '# Commit:    ' .. commit.hash,
    '# Author:    ' .. (detail.author or 'loading…'),
    '# Date:      ' .. (detail.date or 'loading…'),
    '# Parents:   ' .. (commit.parents == nil and '(open commit in graph)'
      or #commit.parents > 0 and table.concat(commit.parents, ' ') or '(root)'),
  })
  if commit.refs ~= '' then
    lines[#lines + 1] = '# References: ' .. commit.refs
  end
  lines[#lines + 1] = '#'
  lines[#lines + 1] = '# Files changed in this commit:'
  if detail.files then
    if #detail.files == 0 then
      lines[#lines + 1] = '#   (no file changes)'
    else
      for _, file in ipairs(detail.files) do
        lines[#lines + 1] = '#   ' .. file
      end
    end
  else
    lines[#lines + 1] = '#   loading…'
  end
  set_lines(view.preview_buffer, lines)
  if vim.api.nvim_win_is_valid(view.preview_window) then
    if previous then
      session.restore_window(view.preview_window, previous)
    else
      vim.api.nvim_win_set_cursor(view.preview_window, { 1, 0 })
    end
    local saved = view.restore_preview
    if saved and detail.message and detail.files then
      if saved.hash == commit.hash then
        session.restore_window(view.preview_window, saved.window)
      end
      view.restore_preview = nil
    end
  end
  view.rendered_preview_hash = commit.hash
end

local function load_preview(view, commit, history_ref)
  cancel_preview(view)
  view.preview_commit = commit
  view.preview_history_ref = history_ref or view.history_ref
  if commit.kind == 'worktree' then
    local lines = { 'Working tree changes', '', '# Based on HEAD: ' .. (view.head_commit or ''),
      '# Status: index / working tree; ?? = untracked', '#' }
    for _, file in ipairs(view.worktree_state and view.worktree_state.files or {}) do
      local path = vim.fn.strtrans(file.path)
      if file.original_path then path = vim.fn.strtrans(file.original_path) .. ' -> ' .. path end
      lines[#lines + 1] = '# ' .. file.status .. ' ' .. path
    end
    set_lines(view.preview_buffer, lines)
    vim.api.nvim_win_set_cursor(view.preview_window, { 1, 0 })
    if view.restore_preview and view.restore_preview.hash == commit.hash then
      session.restore_window(view.preview_window, view.restore_preview.window)
      view.restore_preview = nil
    end
    view.rendered_preview_hash = commit.hash
    return
  end
  local generation = view.preview_generation
  render_preview(view, commit)
  local cached = view.cache[commit.hash]
  if cached and cached.message and cached.files then
    return
  end
  local function current()
    return active == view and generation == view.preview_generation
  end
  view.cancel_message = repository.start(repository.commands.commit_message(commit.hash), view.root,
    function(result)
      if not current() then
        return
      end
      view.cancel_message = nil
      if result.code ~= 0 then
        set_lines(view.preview_buffer, { 'Could not load commit: ' .. repository.concise_error(result) })
        return
      end
      local message, metadata = (result.stdout or ''):match('^(.-)' .. string.char(30) .. '(.*)$')
      local author, date = (metadata or ''):match('^(.-)' .. string.char(31) .. '([^\r\n]*)')
      local detail = view.cache[commit.hash] or {}
      detail.message = message or commit.subject
      detail.author = author or ''
      detail.date = date or ''
      view.cache[commit.hash] = detail
      render_preview(view, commit)
    end)
  view.cancel_files = repository.start(repository.commands.commit_files(commit.hash), view.root,
    function(result)
      if not current() then
        return
      end
      view.cancel_files = nil
      local detail = view.cache[commit.hash] or {}
      if result.code == 0 then
        detail.files = repository.output_lines(result.stdout)
      else
        detail.files = { 'error: ' .. repository.concise_error(result) }
      end
      view.cache[commit.hash] = detail
      render_preview(view, commit)
    end)
end

local function commit_row_at_cursor(view)
  local row = vim.api.nvim_win_get_cursor(view.list_window)[1]
  if view.commits[row] then
    view.last_list_row = row
    return row
  end
  local step = row < (view.last_list_row or row) and -1 or 1
  for _, direction in ipairs({ step, -step }) do
    for candidate = row + direction,
        row + direction * vim.api.nvim_buf_line_count(view.list_buffer), direction do
      if view.commits[candidate] then
        vim.api.nvim_win_set_cursor(view.list_window, { candidate, 0 })
        view.last_list_row = candidate
        return candidate
      end
    end
  end
  return view.last_list_row
end

local function select_cursor(view)
  if active ~= view or not vim.api.nvim_win_is_valid(view.list_window) then
    return
  end
  local row = commit_row_at_cursor(view)
  local commit = view.commits[row]
  if not commit or commit.hash == view.selected_hash then
    return
  end
  view.selected_hash = commit.hash
  if vim.api.nvim_get_current_win() == view.branch_window then return end
  view.preview_generation = view.preview_generation + 1
  local generation = view.preview_generation
  vim.defer_fn(function()
    if active == view and generation == view.preview_generation
        and vim.api.nvim_get_current_win() ~= view.branch_window then
      load_preview(view, commit)
    end
  end, 65)
end

local function finish_history(view, succeeded, detail)
  local completion = view.history_completion
  view.history_completion = nil
  if completion then completion(succeeded, detail) end
end

local function load_history(view, selected_hash, completion)
  finish_history(view, false, 'graph history superseded')
  view.history_completion = completion
  if view.cancel_list then view.cancel_list() end
  if view.cancel_head then view.cancel_head() end
  cancel_fork_anchors(view)
  cancel_preview(view)
  view.history_generation = (view.history_generation or 0) + 1
  local generation = view.history_generation
  view.history_rows = nil
  view.commits = {}
  view.fork_anchors = {}
  view.selected_hash = nil
  view.last_list_row = nil
  set_lines(view.list_buffer, { 'Loading commit history…' })
  vim.api.nvim_buf_clear_namespace(view.list_buffer, list_namespace, 0, -1)
  update_history_winbar(view)
  local history_result, status_result
  local function finish()
    if active ~= view or view.history_generation ~= generation
        or not history_result or not status_result then return end
    local result = history_result
    view.worktree_state = status_result.code == 0
      and repository.parse_worktree_state(status_result.stdout) or nil
    if view.worktree_state then
      view.head_commit = view.worktree_state.commit
      view.current_branch = view.worktree_state.branch_name or 'detached HEAD'
    end
    update_history_winbar(view)
    if result.code ~= 0 then
      if view.restore_graph and view.history_ref ~= 'HEAD' then
        view.restore_graph = nil
        view.history_ref = 'HEAD'
        local retry_completion = view.history_completion
        view.history_completion = nil
        load_history(view, nil, retry_completion)
        return
      end
      set_lines(view.list_buffer, { 'Could not load commit history: ' .. repository.concise_error(result) })
      finish_history(view, false, 'graph history failed to load')
      return
    end
    view.history_rows = M.with_worktree(repository.parse_graph_history(result.stdout), view.worktree_state)
    if not view.current_branch then
      for _, row in ipairs(view.history_rows) do
        local commit = row.commit
        if commit and is_head_ref(commit.refs) then
          view.current_branch = commit.refs:match('HEAD %-> ([^,]+)')
            or 'detached HEAD'
          view.head_commit = commit.hash
          break
        end
      end
      update_history_winbar(view)
    end
    render_history(view)
    load_fork_anchors(view)
    local target_row, head_row
    for row, commit in pairs(view.commits) do
      if selected_hash and commit.hash == selected_hash then
        target_row = row
        break
      end
      if is_head_ref(commit.refs) then
        head_row = row
        if not selected_hash then target_row = row; break end
      end
    end
    target_row = target_row or head_row
    vim.api.nvim_win_set_cursor(view.list_window, { target_row or 1, 0 })
    vim.api.nvim_win_call(view.list_window, function()
      vim.cmd('normal! zt')
      if target_row and view.commits[target_row - 1]
          and view.commits[target_row - 1].kind == 'worktree' then
        vim.fn.winrestview({ topline = target_row - 1 })
      end
    end)
    local saved = view.restore_graph
    view.restore_graph = nil
    if saved and target_row then
      session.restore_window(view.list_window, saved.list_view, target_row)
    end
    select_cursor(view)
    if saved and saved.focus == 'preview' and saved.preview_commit
        and (saved.preview_commit.kind ~= 'worktree'
          or target_row and view.commits[target_row].kind == 'worktree') then
      load_preview(view, saved.preview_commit, saved.preview_history_ref)
    end
    finish_history(view, true, 'graph history refreshed')
  end
  view.cancel_list = repository.start(repository.commands.graph_history(
    repository.footer_list_max_entries, view.history_ref), view.root, function(result)
      if active ~= view or view.history_generation ~= generation then return end
      view.cancel_list = nil
      history_result = result
      finish()
    end)
  view.cancel_head = repository.start(repository.commands.worktree_state(), view.root, function(result)
    if active ~= view or view.history_generation ~= generation then return end
    view.cancel_head = nil
    status_result = result
    finish()
  end)
end

local function selected_branch(view)
  if not view.branch_window or not vim.api.nvim_win_is_valid(view.branch_window) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(view.branch_window)[1]
  return view.branches and view.branches[row]
end

local function preview_branch(view)
  local branch = selected_branch(view)
  if not branch then
    return
  end
  local upstream = branch.upstream ~= '' and (' · upstream ' .. branch.upstream) or ''
  vim.wo[view.branch_window].winbar = (' Branches · %s%s · o/<CR> review · <Space>dm switch/track · f fetch '):format(
    branch.short_name, upstream)
  if branch.tip_commit and branch.tip_commit ~= '' then
    load_preview(view, {
      hash = branch.tip_commit,
      parents = nil,
      refs = branch.short_name,
      subject = branch.subject,
    }, branch.refname)
  end
end

local function load_branches(view)
  if view.cancel_branches then
    view.cancel_branches()
  end
  view.cancel_branches = repository.start(repository.commands.branches(), view.root,
    function(result)
      if active ~= view or not view.branch_window
          or not vim.api.nvim_win_is_valid(view.branch_window) then
        return
      end
      view.cancel_branches = nil
      if result.code ~= 0 then
        set_lines(view.branch_buffer, {
          'Could not load branches: ' .. repository.concise_error(result),
        })
        return
      end
      view.branches = repository.parse_branches(result.stdout)
      render_branches(view)
      local saved = view.restore_branches
      view.restore_branches = nil
      for index, branch in ipairs(view.branches) do
        if branch.refname == (saved and saved.branch_ref or view.history_ref)
            or not saved and view.history_ref == 'HEAD' and branch.current then
          vim.api.nvim_win_set_cursor(view.branch_window, { index, 0 })
          if saved then session.restore_window(view.branch_window, saved.branch_view, index) end
          break
        end
      end
      if not saved or saved.focus == 'branches' then preview_branch(view) end
    end)
end

local function review_branch(view)
  local branch = selected_branch(view)
  if not branch or view.switching or view.fetching or view.checking_out
      or not branch.tip_commit or branch.tip_commit == '' then
    return false
  end
  view.history_ref = branch.refname
  load_history(view, branch.tip_commit)
  preview_branch(view)
  return true
end

local function modified_buffers(root)
  local paths = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(buffer)
    if path ~= '' and vim.api.nvim_buf_is_loaded(buffer)
        and vim.bo[buffer].modified and project.contains(root, path) then
      paths[#paths + 1] = vim.fs.relpath(root, path) or path
    end
  end
  return paths
end

local function switch_branch(view)
  local branch = selected_branch(view)
  if not branch or view.switching or view.fetching or view.checking_out then
    return false
  end
  if branch.current then
    vim.notify('Already on ' .. branch.short_name, vim.log.levels.INFO)
    return true
  end
  view.switching = true
  repository.start(repository.commands.head_state(), view.root, function(result)
    if active ~= view then return end
    if result.code ~= 0 then
      view.switching = false
      vim.notify(repository.concise_error(result), vim.log.levels.ERROR)
      return
    end
    if repository.parse_head_state(result.stdout).dirty or #modified_buffers(view.root) > 0 then
      view.switching = false
      vim.notify('Save or discard workspace changes before switching branches', vim.log.levels.WARN)
      return
    end
    local command = branch.is_remote
        and { 'git', 'switch', '--track', branch.short_name }
      or repository.commands.attach_branch(branch.short_name)
    repository.start(command, view.root, function(switch_result)
      if active ~= view then return end
      view.switching = false
      if switch_result.code ~= 0 then
        vim.notify(repository.concise_error(switch_result), vim.log.levels.ERROR)
        return
      end
      vim.cmd('checktime')
      local root = view.root
      local tip = branch.tip_commit
      M.close()
      M.open(root, tip, true)
      vim.notify('Switched to ' .. branch.short_name, vim.log.levels.INFO)
    end)
  end)
  return true
end

local function fetch_branches(view)
  if view.fetching or view.switching or view.checking_out then
    return
  end
  view.fetching = true
  vim.notify('Fetching Git remotes…', vim.log.levels.INFO)
  repository.start(repository.commands.fetch_all(), view.root, function(result)
    if active ~= view then return end
    view.fetching = false
    if result.code ~= 0 then
      vim.notify(repository.concise_error(result), vim.log.levels.ERROR)
      return
    end
    local root, selected_hash, history_ref = view.root, view.selected_hash, view.history_ref
    M.close()
    M.open(root, selected_hash, true, history_ref)
    vim.notify('Git remotes updated', vim.log.levels.INFO)
  end)
end

function M.toggle_branches()
  local view = active
  if not view then
    return false
  end
  if view.branch_window and vim.api.nvim_win_is_valid(view.branch_window) then
    if view.cancel_branches then
      view.cancel_branches()
      view.cancel_branches = nil
    end
    view.branch_window = nil
    if view.branch_buffer and vim.api.nvim_buf_is_valid(view.branch_buffer) then
      local window = vim.fn.bufwinid(view.branch_buffer)
      if window ~= -1 then vim.api.nvim_win_close(window, true) end
    end
    vim.api.nvim_set_current_win(view.list_window)
    return true
  end
  vim.api.nvim_set_current_win(view.list_window)
  vim.cmd('belowright split')
  view.branch_window = vim.api.nvim_get_current_win()
  view.branch_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(view.branch_window, view.branch_buffer)
  vim.api.nvim_win_set_height(view.branch_window, math.min(12, math.max(5,
    math.floor(vim.o.lines * 0.28))))
  vim.bo[view.branch_buffer].buftype = 'nofile'
  vim.bo[view.branch_buffer].bufhidden = 'wipe'
  vim.bo[view.branch_buffer].swapfile = false
  vim.bo[view.branch_buffer].modifiable = false
  vim.bo[view.branch_buffer].filetype = 'gitbranch'
  vim.wo[view.branch_window].wrap = false
  vim.wo[view.branch_window].cursorline = true
  vim.wo[view.branch_window].number = false
  vim.wo[view.branch_window].winbar = ' Branches · o/<CR> review · <Space>dm switch/track · f fetch '
  set_lines(view.branch_buffer, { 'Loading branches…' })
  local buffer = view.branch_buffer
  for _, key in ipairs({ 'o', '<CR>' }) do
    vim.keymap.set('n', key, function() review_branch(view) end,
      { buffer = buffer, silent = true, desc = 'Review selected branch history' })
  end
  vim.keymap.set('n', '<Space>dm', function() switch_branch(view) end,
    { buffer = buffer, silent = true, desc = 'Switch to selected branch' })
  vim.keymap.set('n', 'f', function() fetch_branches(view) end,
    { buffer = buffer, silent = true, desc = 'Fetch Git remotes' })
  vim.keymap.set('n', '<Space>db', M.toggle_branches,
    { buffer = buffer, silent = true, desc = 'Hide Git branches' })
  vim.keymap.set('n', '<Space>de', M.search,
    { buffer = buffer, silent = true, desc = 'Search Git history' })
  vim.keymap.set('n', '<Tab>', function() vim.api.nvim_set_current_win(view.list_window) end,
    { buffer = buffer, silent = true, desc = 'Focus commit history' })
  view.autocmds[#view.autocmds + 1] = vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buffer,
    callback = function()
      if active == view then preview_branch(view) end
    end,
  })
  load_branches(view)
  return true
end

function M.is_active()
  return active ~= nil
end

function M.is_current()
  return active ~= nil and active.tab == vim.api.nvim_get_current_tabpage()
end

local function capture_graph(view)
  local branch = selected_branch(view)
  local current_window = vim.api.nvim_get_current_win()
  local row = vim.api.nvim_win_get_cursor(view.list_window)[1]
  local commit = view.commits[row]
  return {
    history_ref = view.history_ref,
    selected_hash = commit and commit.hash or view.selected_hash,
    branches_open = view.branch_window ~= nil and vim.api.nvim_win_is_valid(view.branch_window),
    branch_ref = branch and branch.refname,
    branch_height = view.branch_window and vim.api.nvim_win_is_valid(view.branch_window)
      and vim.api.nvim_win_get_height(view.branch_window) or nil,
    width_ratio = vim.api.nvim_win_get_width(view.list_window) / vim.o.columns,
    list_view = session.capture_window(view.list_window),
    preview_view = session.capture_window(view.preview_window),
    branch_view = session.capture_window(view.branch_window),
    preview_commit = view.preview_commit,
    preview_history_ref = view.preview_history_ref,
    focus = current_window == view.preview_window and 'preview'
      or current_window == view.branch_window and 'branches' or 'list',
  }
end

function M.close()
  local view = active
  if not view then
    return false
  end
  session.update(view.root, { layout = 'graph', graph = capture_graph(view) })
  active = nil
  finish_history(view, false, 'graph closed')
  panel.leave_git(view)
  clear_autocmds(view)
  cancel_preview(view)
  cancel_fork_anchors(view)
  if view.cancel_head then view.cancel_head() end
  if view.cancel_branches then view.cancel_branches() end
  if view.cancel_list then
    view.cancel_list()
  end
  if view.tab and vim.api.nvim_tabpage_is_valid(view.tab) then
    local current_tab = vim.api.nvim_get_current_tabpage()
    if current_tab ~= view.tab then
      vim.api.nvim_set_current_tabpage(view.tab)
    end
    local closed = pcall(vim.cmd, 'tabclose')
    if not closed then
      pcall(vim.cmd, 'only')
      pcall(vim.cmd, 'enew')
    end
  end
  return true
end

function M.checkout_selected_commit()
  local view = active
  if not view or view.switching or view.fetching or view.checking_out then return false end
  local from_preview = vim.api.nvim_get_current_win() == view.preview_window
  local commit = from_preview and view.preview_commit
    or not from_preview and view.commits[commit_row_at_cursor(view)]
  if not commit or commit.kind == 'worktree' then return false end
  local retained_ref = view.history_ref == 'HEAD' and view.worktree_state
    and view.worktree_state.branch_name and ('refs/heads/' .. view.worktree_state.branch_name)
    or view.history_ref
  view.checking_out = true
  local started = require('config.git').detach_commit_overview(view.root, commit.hash, nil, {
    source = 'LOCAL',
    is_current = function() return active == view end,
    on_finished = function() view.checking_out = false end,
    render_review = function(_commit_hash, _review_context, finished)
      if active ~= view then return false end
      view.restore_graph = capture_graph(view)
      view.history_ref = retained_ref
      load_history(view, view.selected_hash, function(succeeded, detail)
        finished(nil, succeeded, detail)
      end)
      return true
    end,
  })
  if not started then view.checking_out = false end
  return started
end

function M.search()
  local view = active
  if not view then return false end
  return require('config.git.search').open(view.root, {
    kind = 'repository',
    location = { root = view.root },
    checked_out_branch = view.worktree_state and view.worktree_state.branch_name,
    detached_head_commit = view.worktree_state and view.worktree_state.branch_name == nil
      and view.head_commit or nil,
  }, nil, {
    is_current = function() return active == view end,
    branch = function(branch)
      if active ~= view or view.checking_out then return false end
      view.history_ref = branch.refname or branch.short_name
      vim.api.nvim_set_current_win(view.list_window)
      load_history(view, branch.tip_commit)
      return true
    end,
    commit = function(commit)
      if active ~= view then return false end
      for row, candidate in pairs(view.commits) do
        if candidate.hash == commit.hash then
          vim.api.nvim_set_current_win(view.list_window)
          vim.api.nvim_win_set_cursor(view.list_window, { row, 0 })
          view.selected_hash = candidate.hash
          load_preview(view, candidate)
          return true
        end
      end
      -- A result outside the retained graph is still readable without replacing
      -- its branch or list. The explicit detail key uses this preview's target.
      load_preview(view, {
        hash = commit.hash,
        refs = commit.branch_name or '',
        subject = commit.subject or ('Commit ' .. commit.hash:sub(1, 12)),
      }, commit.history_ref or view.history_ref)
      vim.api.nvim_set_current_win(view.preview_window)
      return true
    end,
  })
end

function M.open_detail()
  local view = active
  if not view then
    return false
  end
  local from_preview = vim.api.nvim_get_current_win() == view.preview_window
  local commit = from_preview and view.preview_commit
    or not from_preview and view.commits[commit_row_at_cursor(view)]
  if not commit then
    return false
  end
  local root, selected_hash = view.root, commit.hash
  local history_ref = from_preview and view.preview_history_ref or view.history_ref
  M.close()
  local git_diffview = require('config.git.diffview')
  local detail_view = git_diffview.open_commit_detail({
    kind = 'repository',
    location = { root = root },
    commit = commit,
    graph_return = {
      root = root,
      history_ref = history_ref,
    },
    layout_mode = 'detail',
    source = vim.startswith(history_ref, 'refs/remotes/') and 'REMOTE' or 'LOCAL',
  })
  if not detail_view then
    M.open(root, selected_hash, nil, history_ref)
    return false
  end
  return true
end

function M.focus_preview()
  local view = active
  if not view then
    return false
  end
  local row = commit_row_at_cursor(view)
  local commit = view.commits[row]
  if commit then
    view.selected_hash = commit.hash
    load_preview(view, commit)
  end
  vim.api.nvim_set_current_win(view.preview_window)
  return true
end

function M.open(root, selected_hash, open_branches, history_ref, saved)
  if active then
    return false
  end
  require('config.git.diffview').install_quit_command()
  local view = {
    root = root,
    history_ref = history_ref or 'HEAD',
    cache = {},
    commits = {},
    preview_generation = 0,
    autocmds = {},
    restore_graph = saved,
    restore_branches = saved,
    restore_preview = saved and saved.preview_commit and {
      hash = saved.preview_commit.hash, window = saved.preview_view,
    } or nil,
  }
  vim.cmd('tabnew')
  view.tab = vim.api.nvim_get_current_tabpage()
  view.list_window = vim.api.nvim_get_current_win()
  view.list_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(view.list_window, view.list_buffer)
  vim.cmd('rightbelow vsplit')
  view.preview_window = vim.api.nvim_get_current_win()
  view.preview_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(view.preview_window, view.preview_buffer)
  vim.api.nvim_win_set_width(view.list_window, math.max(1, math.floor(vim.o.columns * 0.40)))
  for _, buffer in ipairs({ view.list_buffer, view.preview_buffer }) do
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'wipe'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].modifiable = false
  end
  vim.bo[view.list_buffer].filetype = 'gitgraph'
  vim.bo[view.preview_buffer].filetype = 'gitcommit'
  vim.api.nvim_buf_call(view.preview_buffer, function()
    -- Historical subjects are read-only: the native 50-column composition
    -- guideline should not split their summary color in the middle of a word.
    vim.cmd([[syntax match gitcommitSummary "^.*$" contained containedin=gitcommitFirstLine contains=@Spell]])
  end)
  vim.wo[view.list_window].wrap = false
  vim.wo[view.list_window].cursorline = true
  vim.wo[view.list_window].number = false
  vim.wo[view.preview_window].wrap = true
  vim.wo[view.preview_window].number = false
  update_history_winbar(view)
  vim.wo[view.preview_window].winbar = ' Commit message · <Space>dv details · <Tab> switch pane '
  set_lines(view.list_buffer, { 'Loading commit history…' })
  set_lines(view.preview_buffer, { 'Select a commit to preview its message and files.' })
  active = view
  panel.enter_git(view, M.close)
  vim.api.nvim_set_current_win(view.list_window)

  local function map(buffer, key, callback, description)
    vim.keymap.set('n', key, callback, { buffer = buffer, silent = true, desc = description })
  end
  for _, buffer in ipairs({ view.list_buffer, view.preview_buffer }) do
    map(buffer, '<Space>dv', M.open_detail, 'Open Diffview commit details')
    map(buffer, '<Space>de', M.search, 'Search Git history')
    map(buffer, '<Space>dm', M.checkout_selected_commit, 'Checkout selected Git history commit')
    map(buffer, '<Space>db', M.toggle_branches, 'Toggle Git branch pane')
    map(buffer, '<Tab>', function()
      local current_window = vim.api.nvim_get_current_win()
      local target_window = current_window == view.list_window and view.preview_window
        or view.branch_window and vim.api.nvim_win_is_valid(view.branch_window)
          and view.branch_window or view.list_window
      vim.api.nvim_set_current_win(target_window)
    end, 'Switch Git panes')
  end
  map(view.list_buffer, 'o', M.focus_preview, 'Preview selected commit')
  map(view.list_buffer, '<CR>', M.focus_preview, 'Preview selected commit')
  view.autocmds[#view.autocmds + 1] = vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = view.list_buffer,
    callback = function() select_cursor(view) end,
  })
  view.autocmds[#view.autocmds + 1] = vim.api.nvim_create_autocmd('WinEnter', {
    callback = function()
      if active == view and vim.api.nvim_get_current_win() == view.list_window then
        local row = vim.api.nvim_win_get_cursor(view.list_window)[1]
        local commit = view.commits[row]
        if commit then load_preview(view, commit) end
      end
    end,
  })
  view.autocmds[#view.autocmds + 1] = vim.api.nvim_create_autocmd(
    { 'WinResized', 'VimResized' }, {
      callback = function(event)
        if active == view and view.history_rows
            and vim.api.nvim_win_is_valid(view.list_window) then
          if event.event == 'VimResized' then
            vim.api.nvim_win_set_width(view.list_window,
              math.max(1, math.floor(vim.o.columns * 0.40)))
          end
          render_history(view)
          update_history_winbar(view)
        end
        if active == view and view.branches and view.branch_window
            and vim.api.nvim_win_is_valid(view.branch_window) then
          render_branches(view)
        end
      end,
    })
  view.autocmds[#view.autocmds + 1] = vim.api.nvim_create_autocmd('TabClosed', {
    callback = function()
      if active == view and not vim.api.nvim_tabpage_is_valid(view.tab) then
        active = nil
        finish_history(view, false, 'graph tab closed')
        panel.leave_git(view)
        clear_autocmds(view)
        cancel_preview(view)
        cancel_fork_anchors(view)
        if view.cancel_head then view.cancel_head() end
        if view.cancel_list then view.cancel_list() end
      end
    end,
  })
  load_history(view, selected_hash)
  if open_branches then
    M.toggle_branches()
  end
  if saved then
    vim.api.nvim_win_set_width(view.list_window,
      math.max(1, math.floor(vim.o.columns * (saved.width_ratio or 0.40) + 0.5)))
    if view.branch_window and saved.branch_height then
      vim.api.nvim_win_set_height(view.branch_window, saved.branch_height)
    end
    local target = saved.focus == 'preview' and view.preview_window
      or saved.focus == 'branches' and view.branch_window or view.list_window
    vim.api.nvim_set_current_win(target or view.list_window)
  end
  return true
end

function M.resume(root)
  local git_diffview = require('config.git.diffview')
  if active or git_diffview.is_active() then return false end
  if git_diffview.defer_until_settled('resume-git-view', function() M.resume(root) end) then
    return true
  end
  local saved = session.read(root)
  local detail = saved.detail
  if saved.layout == 'detail' and detail and detail.commit then
    local view = git_diffview.open_commit_detail({
      location = { root = root }, commit = detail.commit,
      graph_return = detail.graph_return, source = detail.source,
      session_restore = detail,
    })
    if view then return true end
  end
  local graph = saved.graph or {}
  return M.open(root, graph.selected_hash, graph.branches_open, graph.history_ref, saved.graph)
end

return M
