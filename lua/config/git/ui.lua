local M = {}
local preview_namespace = vim.api.nvim_create_namespace('git_search_preview')

M.focus_layout = {
  preview_height = 0.68,
  preview_width = 0.72,
  results_height = 0.32,
  results_width = 0.42,
}

function M.entry(record)
  return record
end

function M.picker_options(root)
  local picker_options = {
    layout_config = {
      horizontal = { preview_width = M.focus_layout.results_width },
      vertical = { preview_height = M.focus_layout.results_height },
    },
  }
  if root then
    picker_options.cwd = root
  end
  return picker_options
end

local function fit_column(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  if display_width <= width then
    return text .. string.rep(' ', width - display_width)
  end
  local character_count = vim.fn.strchars(text)
  local fitted_text = ''
  for character_index = 0, character_count - 1 do
    local character = vim.fn.strcharpart(text, character_index, 1)
    if vim.fn.strdisplaywidth(fitted_text .. character .. '…') > width then
      break
    end
    fitted_text = fitted_text .. character
  end
  return fitted_text .. '…'
end

local function result_columns(prefix, source, kind, name, date, title)
  local columns = {
    { group = nil, text = prefix, width = 4 },
    {
      group = source == 'LOCAL' and 'DiffAdd' or 'DiagnosticInfo',
      text = source,
      width = 6,
    },
    { group = 'Type', text = kind, width = 7 },
    { group = 'Identifier', text = name, width = 30 },
    { group = 'Comment', text = date, width = 10 },
    { group = 'Title', text = title },
  }
  local display_parts = {}
  local highlights = {}
  local byte_offset = 0
  for column_index, column in ipairs(columns) do
    local fitted_text = column.width and fit_column(column.text, column.width) or column.text
    display_parts[#display_parts + 1] = fitted_text
    if column.group and column.text ~= '' then
      highlights[#highlights + 1] = {
        { byte_offset, byte_offset + #fitted_text },
        column.group,
      }
    end
    byte_offset = byte_offset + #fitted_text
    if column_index < #columns then
      display_parts[#display_parts + 1] = ' '
      byte_offset = byte_offset + 1
    end
  end
  local display_text = table.concat(display_parts)
  return display_text, function()
    return display_text, highlights
  end
end

local function add_preview_line(rendered, text, commit_hash, highlights)
  rendered.lines[#rendered.lines + 1] = text
  rendered.commit_by_line[#rendered.lines] = commit_hash or false
  for _, highlight in ipairs(highlights or {}) do
    rendered.highlights[#rendered.highlights + 1] = {
      column_end = highlight[2],
      column_start = highlight[1],
      group = highlight[3],
      line = #rendered.lines - 1,
    }
  end
end

local function status_highlight(status)
  local status_kind = status:sub(1, 1)
  if status_kind == 'A' then
    return 'DiffAdd'
  end
  if status_kind == 'D' then
    return 'DiffDelete'
  end
  if status_kind == 'R' or status_kind == 'C' then
    return 'DiagnosticInfo'
  end
  return 'DiagnosticWarn'
end

local function file_display_path(file)
  if file.original_path then
    return ('%s → %s'):format(file.original_path, file.path)
  end
  return file.path
end

function M.branch_preview(branch, commits)
  local source = branch.is_remote and 'REMOTE' or 'LOCAL'
  local branch_name = branch.short_name or branch.refname
  local rendered = { commit_by_line = {}, highlights = {}, lines = {} }
  local header = ('%-6s  BRANCH   %s'):format(source, branch_name)
  add_preview_line(rendered, header, nil, {
    { 0, #source, source == 'LOCAL' and 'DiffAdd' or 'DiagnosticInfo' },
    { 8, 14, 'Type' },
    { 17, #header, 'Identifier' },
  })
  local branch_context = branch.current and 'current branch' or 'known branch'
  if branch.upstream and branch.upstream ~= '' then
    branch_context = branch_context .. '  →  ' .. branch.upstream
  end
  add_preview_line(rendered, branch_context, nil, {
    { 0, #branch_context, 'Comment' },
  })
  add_preview_line(rendered, '', nil)
  add_preview_line(rendered, '  COMMIT      DATE        TITLE', nil, {
    { 2, 12, 'Type' },
    { 14, 24, 'Comment' },
    { 26, 31, 'Title' },
  })

  if #commits == 0 then
    add_preview_line(rendered, '  No commits found', nil, { { 2, 18, 'Comment' } })
    return rendered
  end

  for _, commit in ipairs(commits) do
    local commit_line = ('▾ %-10s  %-10s  %s'):format(
      commit.abbreviated_hash,
      commit.date,
      commit.subject
    )
    add_preview_line(rendered, commit_line, commit.hash, {
      { #'▾ ', #'▾ ' + #commit.abbreviated_hash, 'Identifier' },
      { #'▾ ' + 12, #'▾ ' + 12 + #commit.date, 'Comment' },
      { #'▾ ' + 24, #commit_line, 'Title' },
    })
    local author_line = ('  %-10s  %s'):format('AUTHOR', commit.author)
    add_preview_line(rendered, author_line, commit.hash, {
      { 2, 12, 'Type' },
      { 14, #author_line, 'Comment' },
    })
    for _, file in ipairs(commit.files) do
      local display_path = file_display_path(file)
      local file_line = ('    %-8s  %s'):format(file.status, display_path)
      add_preview_line(rendered, file_line, commit.hash, {
        { 4, 4 + #file.status, status_highlight(file.status) },
        { 14, #file_line, 'Directory' },
      })
    end
    add_preview_line(rendered, '', commit.hash)
  end
  return rendered
end

function M.commit_preview(entry, commit)
  local source = entry.commit.source or (entry.kind == 'commit_id' and 'LOOKUP' or 'LOCAL')
  local rendered = { commit_by_line = {}, highlights = {}, lines = {} }
  local header = ('%-6s  COMMIT   %s'):format(source, commit.abbreviated_hash)
  add_preview_line(rendered, header, commit.hash, {
    { 0, #source, source == 'LOCAL' and 'DiffAdd' or 'DiagnosticInfo' },
    { 8, 14, 'Type' },
    { 17, #header, 'Identifier' },
  })
  if entry.branch then
    local branch_line = ('BRANCH   %s'):format(entry.branch.short_name or entry.branch.refname)
    add_preview_line(rendered, branch_line, commit.hash, {
      { 0, 6, 'Type' },
      { 9, #branch_line, 'Identifier' },
    })
  end
  local date_line = ('DATE     %s'):format(commit.date)
  add_preview_line(rendered, date_line, commit.hash, {
    { 0, 4, 'Type' },
    { 9, #date_line, 'Comment' },
  })
  local author_line = ('AUTHOR   %s'):format(commit.author)
  add_preview_line(rendered, author_line, commit.hash, {
    { 0, 6, 'Type' },
    { 9, #author_line, 'Comment' },
  })
  add_preview_line(rendered, '', commit.hash)
  add_preview_line(rendered, commit.subject, commit.hash, {
    { 0, #commit.subject, 'Title' },
  })
  add_preview_line(rendered, '', commit.hash)
  local file_heading = ('CHANGED FILES  %d'):format(#commit.files)
  add_preview_line(rendered, file_heading, commit.hash, {
    { 0, 13, 'Type' },
    { 15, #file_heading, 'Number' },
  })
  for _, file in ipairs(commit.files) do
    local display_path = file_display_path(file)
    local file_line = ('  %-8s  %s'):format(file.status, display_path)
    add_preview_line(rendered, file_line, commit.hash, {
      { 2, 2 + #file.status, status_highlight(file.status) },
      { 12, #file_line, 'Directory' },
    })
  end
  return rendered
end

function M.render_preview_buffer(buffer, rendered)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return false
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, rendered.lines)
  vim.api.nvim_buf_clear_namespace(buffer, preview_namespace, 0, -1)
  for _, highlight in ipairs(rendered.highlights) do
    vim.api.nvim_buf_set_extmark(buffer, preview_namespace, highlight.line, highlight.column_start, {
      end_col = highlight.column_end,
      hl_group = highlight.group,
      priority = 150,
    })
  end
  vim.bo[buffer].filetype = 'git'
  vim.bo[buffer].modifiable = false
  vim.b[buffer].git_search_commit_by_line = rendered.commit_by_line
  return true
end

function M.branch_record(branch, matching_commit_count)
  local branch_kind = branch.is_remote and 'REMOTE' or 'LOCAL'
  local current_marker = branch.current and '*' or ' '
  local upstream_text = branch.upstream ~= '' and (' → ' .. branch.upstream) or ''
  local match_text = matching_commit_count
      and (' · %d matching commits'):format(matching_commit_count)
    or ''
  local display_text, display = result_columns(
    current_marker,
    branch_kind,
    'BRANCH',
    branch.short_name,
    branch.date,
    branch.subject .. upstream_text .. match_text
  )
  return {
    branch = branch,
    display = display,
    display_text = display_text,
    ordinal = table.concat({
      branch_kind,
      branch.short_name,
      branch.upstream,
      branch.subject,
    }, ' '),
    kind = 'branch',
    level = 0,
    value = branch.short_name,
  }
end

function M.commit_record(commit)
  local source = commit.source or 'LOCAL'
  local display_text, display = result_columns(
    '└─',
    source,
    'COMMIT',
    commit.abbreviated_hash,
    commit.date,
    commit.subject
  )
  return {
    commit = commit,
    display = display,
    display_text = display_text,
    kind = 'commit',
    level = 1,
    ordinal = table.concat({
      source,
      'COMMIT',
      commit.hash,
      commit.abbreviated_hash,
      commit.author,
      commit.subject,
    }, ' '),
    value = commit.hash,
  }
end

function M.commit_id_record(commit_id)
  local display_text, display = result_columns(
    '└─',
    'LOOKUP',
    'COMMIT',
    commit_id,
    '',
    'review commit'
  )
  return {
    commit = { hash = commit_id },
    display = display,
    display_text = display_text,
    kind = 'commit_id',
    level = 1,
    ordinal = commit_id,
    value = commit_id,
  }
end

function M.issue_record(issue)
  local issue_date = (issue.updated_at or issue.created_at or ''):match('^(%d%d%d%d%-%d%d%-%d%d)')
    or ''
  local display_text, display = result_columns(
    '',
    'REMOTE',
    issue.kind:upper(),
    '#' .. issue.number,
    issue_date,
    issue.title
  )
  return {
    display = display,
    display_text = display_text,
    issue = issue,
    kind = 'issue',
    level = 0,
    ordinal = table.concat({
      'REMOTE',
      issue.remote_host or '',
      issue.remote_repository or '',
      issue.kind,
      '#' .. issue.number,
      issue.author,
      issue.title,
      table.concat(issue.labels, ' '),
    }, ' '),
    value = issue.html_url,
  }
end

function M.remote_error_record(provider, message)
  local display_text, display = result_columns(
    '',
    'REMOTE',
    'ERROR',
    provider,
    '',
    message
  )
  return {
    display = display,
    display_text = display_text,
    error = message,
    kind = 'remote_error',
    level = 0,
    ordinal = table.concat({ 'REMOTE', 'ERROR', provider, message }, ' '),
    provider = provider,
    value = provider .. ':' .. message,
  }
end

function M.remote_error_preview(entry)
  local rendered = { commit_by_line = {}, highlights = {}, lines = {} }
  local header = ('REMOTE  %s unavailable'):format(entry.provider)
  add_preview_line(rendered, header, nil, {
    { 0, 6, 'DiagnosticInfo' },
    { 8, 8 + #entry.provider, 'Identifier' },
    { 9 + #entry.provider, #header, 'DiagnosticError' },
  })
  add_preview_line(rendered, '', nil)
  add_preview_line(rendered, entry.error, nil, {
    { 0, #entry.error, 'DiagnosticError' },
  })
  add_preview_line(rendered, '', nil)
  local recovery_hint = 'Configure :Proxy or GH_TOKEN/GITHUB_TOKEN, then search again.'
  add_preview_line(rendered, recovery_hint, nil, {
    { 0, #recovery_hint, 'Comment' },
  })
  return rendered
end

return M
