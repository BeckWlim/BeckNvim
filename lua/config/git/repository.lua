local M = {}

M.max_history_entries = 50
M.max_branch_entries = 100

local commit_search_format = table.concat({
  '%H',
  '%h',
  '%ad',
  '%an',
  '%S',
  '%s',
}, '%x09')

local branch_format = table.concat({
  '%(HEAD)',
  '%(refname)',
  '%(refname:short)',
  '%(objectname)',
  '%(upstream:short)',
  '%(committerdate:short)',
  '%(subject)',
}, '%09')

local preview_record_separator = string.char(30)
local preview_field_separator = string.char(31)
local preview_format = table.concat({
  '%H',
  '%h',
  '%ad',
  '%an',
  '%s',
}, '%x1f')

M.commands = {}

function M.output_lines(output)
  local normalized_output = (output or ''):gsub('\r\n', '\n')
  if normalized_output == '' then
    return {}
  end
  local lines = vim.split(normalized_output, '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  return lines
end

function M.concise_error(completed_process)
  local raw_error = vim.trim(completed_process.stderr or '')
  if raw_error == '' then
    raw_error = ('git exited with code %d'):format(completed_process.code)
  end
  return raw_error:gsub('[\r\n]+', ' ')
end

function M.commands.branches()
  return {
    'git',
    'for-each-ref',
    '--sort=-committerdate',
    '--sort=-HEAD',
    '--count=' .. M.max_branch_entries,
    '--format=' .. branch_format,
    'refs/heads',
    'refs/remotes',
  }
end

function M.parse_branches(output)
  local branches = {}
  for _, output_line in ipairs(M.output_lines(output)) do
    if #branches >= M.max_branch_entries then
      break
    end
    local fields = vim.split(output_line, '\t', { plain = true })
    local refname = fields[2] or ''
    local short_name = fields[3] or ''
    local is_remote = vim.startswith(refname, 'refs/remotes/')
    local is_remote_head = is_remote and refname:match('/HEAD$') ~= nil
    if short_name ~= '' and not is_remote_head then
      branches[#branches + 1] = {
        current = fields[1] == '*',
        is_remote = is_remote,
        refname = refname,
        short_name = short_name,
        tip_commit = fields[4] or '',
        upstream = fields[5] or '',
        date = fields[6] or '',
        subject = table.concat(fields, '\t', 7),
      }
    end
  end
  return branches
end

function M.commands.resolve_commit(commit_id)
  return { 'git', 'rev-parse', '--verify', '--end-of-options', commit_id .. '^{commit}' }
end

function M.commands.head_state()
  return { 'git', 'status', '--porcelain=v2', '--branch' }
end

function M.parse_head_state(output)
  local head_state = {
    branch_name = nil,
    commit = nil,
    detached = false,
    dirty = false,
  }
  for _, output_line in ipairs(M.output_lines(output)) do
    local commit_hash = output_line:match('^# branch%.oid (.+)$')
    local head_name = output_line:match('^# branch%.head (.+)$')
    if commit_hash then
      head_state.commit = commit_hash
    elseif head_name then
      head_state.detached = head_name == '(detached)'
      if not head_state.detached then
        head_state.branch_name = head_name
      end
    elseif not vim.startswith(output_line, '# ') then
      head_state.dirty = true
    end
  end
  return head_state
end

function M.commands.detach_commit(commit_hash)
  return { 'git', 'switch', '--detach', commit_hash }
end

function M.commands.attach_branch(branch_name)
  return { 'git', 'switch', branch_name }
end

function M.commands.commit_sources(commit_hash)
  return {
    'git',
    'for-each-ref',
    '--format=%(refname)',
    '--contains=' .. commit_hash,
    'refs/heads',
    'refs/remotes',
  }
end

function M.commands.commit_is_ancestor(commit_hash, refname)
  return { 'git', 'merge-base', '--is-ancestor', commit_hash, refname }
end

function M.commands.search_commits(query, history_options)
  local search_options = history_options or {}
  local commit_number = query:match('^#(%d+)$')
  local grep_pattern = commit_number
      and ('#%s([^[:digit:]]|$)'):format(commit_number)
    or query
  local command = {
    'git',
    '--no-pager',
    'log',
    '--date=short',
    '--format=' .. commit_search_format,
    '--max-count=' .. M.max_history_entries,
    '--extended-regexp',
    '--grep=' .. grep_pattern,
  }
  if not search_options.revision and search_options.kind ~= 'symbol' then
    command[#command + 1] = '--branches'
    command[#command + 1] = '--remotes'
    command[#command + 1] = '--source'
  end
  if search_options.revision then
    command[#command + 1] = search_options.revision .. '^!'
  end
  local location = search_options.location or {}
  if search_options.kind == 'symbol' and search_options.range and location.relative_path then
    command[#command + 1] = ('-L%d,%d:%s'):format(
      search_options.range[1],
      search_options.range[2],
      location.relative_path
    )
  elseif search_options.kind == 'file' and location.relative_path then
    command[#command + 1] = '--follow'
    command[#command + 1] = '--'
    command[#command + 1] = location.relative_path
  end
  return command
end

function M.commands.branch_preview(branch, commits)
  local selected_commits = commits or {}
  local command = {
    'git',
    '--no-pager',
    #selected_commits > 0 and 'show' or 'log',
    '--date=short',
    '--format=%x1e' .. preview_format,
    '--name-status',
  }
  if #selected_commits > 0 then
    for _, commit in ipairs(selected_commits) do
      command[#command + 1] = commit.hash
    end
  else
    command[#command + 1] = '--max-count=' .. M.max_history_entries
    command[#command + 1] = branch.refname
  end
  return command
end

function M.commands.commit_preview(commit_hash)
  return {
    'git',
    '--no-pager',
    'show',
    '--date=short',
    '--format=%x1e' .. preview_format,
    '--name-status',
    commit_hash,
  }
end

function M.parse_commit_preview(output)
  local commits = {}
  local current_commit
  for _, output_line in ipairs(M.output_lines(output)) do
    if vim.startswith(output_line, preview_record_separator) then
      local fields = vim.split(output_line:sub(2), preview_field_separator, { plain = true })
      current_commit = {
        abbreviated_hash = fields[2] or '',
        author = fields[4] or '',
        date = fields[3] or '',
        files = {},
        hash = fields[1] or '',
        subject = table.concat(fields, preview_field_separator, 5),
      }
      commits[#commits + 1] = current_commit
    elseif current_commit and output_line:find('\t', 1, true) then
      local fields = vim.split(output_line, '\t', { plain = true })
      local status = fields[1] or ''
      local original_path = #fields >= 3 and fields[2] or nil
      local path = #fields >= 3 and fields[3] or fields[2]
      if status ~= '' and path and path ~= '' then
        current_commit.files[#current_commit.files + 1] = {
          original_path = original_path,
          path = path,
          status = status,
        }
      end
    end
  end
  return commits
end

local function subject_has_commit_number(subject, commit_number)
  local reference = '#' .. commit_number
  local search_start = 1
  while search_start <= #subject do
    local match_start, match_end = subject:find(reference, search_start, true)
    if not match_start or not match_end then
      return false
    end
    local following_character = subject:sub(match_end + 1, match_end + 1)
    if following_character == '' or not following_character:match('%d') then
      return true
    end
    search_start = match_end + 1
  end
  return false
end

function M.parse_commit_search(output, commit_number)
  local commits = {}
  for _, output_line in ipairs(M.output_lines(output)) do
    local fields = vim.split(output_line, '\t', { plain = true })
    local source_ref = fields[5] or ''
    local subject = table.concat(fields, '\t', 6)
    local full_hash = fields[1]
    if full_hash
        and #fields >= 6
        and full_hash:match('^[0-9a-fA-F]+$')
        and #full_hash >= 40
        and #full_hash <= 64
        and (not commit_number or subject_has_commit_number(subject, commit_number)) then
      commits[#commits + 1] = {
        abbreviated_hash = fields[2] or full_hash:sub(1, 8),
        author = fields[4] or '',
        date = fields[3] or '',
        hash = full_hash,
        source = 'LOCAL',
        source_ref = source_ref,
        subject = subject ~= '' and subject or '[empty message]',
      }
    end
  end
  return commits
end

function M.parse_commit_source(output)
  return M.parse_commit_location(output).source
end

function M.parse_commit_location(output)
  local remote_branch_name
  for _, output_line in ipairs(M.output_lines(output)) do
    local local_branch_name = output_line:match('^refs/heads/(.+)$')
    if local_branch_name then
      return { branch_name = local_branch_name, source = 'LOCAL' }
    end
    local remote_candidate = output_line:match('^refs/remotes/(.+)$')
    if not remote_branch_name and remote_candidate and not remote_candidate:match('/HEAD$') then
      remote_branch_name = remote_candidate
    end
  end
  if remote_branch_name then
    return { branch_name = remote_branch_name, source = 'REMOTE' }
  end
  return { branch_name = nil, source = 'LOCAL' }
end

function M.start(command, root, callback)
  local process
  local process_started, start_error = pcall(function()
    process = vim.system(command, { cwd = root, text = true }, function(completed_process)
      vim.schedule(function()
        callback(completed_process)
      end)
    end)
  end)
  if not process_started then
    vim.schedule(function()
      callback({
        code = -1,
        stderr = tostring(start_error),
        stdout = '',
      })
    end)
  end

  return function()
    if process then
      pcall(process.kill, process, 15)
    end
  end
end

return M
