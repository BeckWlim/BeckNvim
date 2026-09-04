local M = {}
local footer_settings = require('config.git.settings').footer()

M.max_history_entries = 50
M.footer_list_batch_entries = footer_settings.list_batch_entries
M.footer_list_max_entries = footer_settings.list_max_entries
M.footer_list_margin_entries = footer_settings.list_margin_entries
M.footer_preview_headroom_entries = footer_settings.preview_headroom_entries
M.footer_detail_batch_entries = footer_settings.detail_batch_entries
M.footer_detail_worker_count = footer_settings.detail_worker_count
M.footer_request_timeout_ms = footer_settings.request_timeout_ms
-- Diffview's own log defaults cap every file-history walk at 256 commits
-- (`-n256`); an "unbounded" mount must still pass an explicit ceiling or old
-- commits silently fall out of the list.
M.unbounded_history_entries = 100000
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

local history_row_format = table.concat({
  '%H',
  '%P',
  '%an',
  '%at',
  '%ai',
  '%ar',
  '%D',
  '%gd',
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

function M.commands.branches_pointing_at(commit_hash)
  return {
    'git',
    'for-each-ref',
    '--sort=refname',
    '--format=' .. branch_format,
    '--points-at=' .. commit_hash,
    'refs/heads',
    'refs/remotes',
  }
end

function M.commands.remote_urls()
  return {
    'git',
    'config',
    '--null',
    '--get-regexp',
    '^remote\\..*\\.url$',
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

function M.match_detached_tip_branch(branches, detached_commit)
  local remote_match
  for _, branch in ipairs(branches) do
    if branch.tip_commit == detached_commit then
      if not branch.is_remote then
        return branch
      end
      remote_match = remote_match or branch
    end
  end
  return remote_match
end

function M.commands.resolve_commit(commit_id)
  return { 'git', 'rev-parse', '--verify', '--end-of-options', commit_id .. '^{commit}' }
end

function M.parse_resolved_commit(output)
  local resolved_hash = M.output_lines(output)[1]
  if resolved_hash and resolved_hash:match('^[0-9a-fA-F]+$') then
    return resolved_hash
  end
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

function M.commands.commit_position(commit_hash, refname)
  return {
    'git',
    'rev-list',
    '--count',
    commit_hash .. '..' .. refname,
  }
end

function M.parse_count(output)
  return tonumber(M.output_lines(output)[1])
end

function M.commands.history_rows(history_options, skip_count, row_count)
  local selected_options = history_options or {}
  local history_location = selected_options.location or {}
  local command = {
    'git',
    '--no-pager',
    'log',
    '--topo-order',
    '--no-patch',
    '--max-count=' .. row_count,
    '--skip=' .. skip_count,
    '--format=%x1e' .. history_row_format,
  }
  local history_ref = selected_options.history_ref
  local revision = selected_options.revision
  command[#command + 1] = history_ref or (revision and (revision .. '^!')) or 'HEAD'
  if selected_options.kind == 'symbol'
      and selected_options.range
      and history_location.relative_path then
    command[#command + 1] = ('-L%d,%d:%s'):format(
      selected_options.range[1],
      selected_options.range[2],
      history_location.relative_path
    )
  elseif selected_options.kind == 'file' and history_location.relative_path then
    table.insert(command, 6, '--follow')
    command[#command + 1] = '--'
    command[#command + 1] = history_location.relative_path
  end
  return command
end

function M.commands.history_detail_rows(commit_hashes, output_kind)
  local command = {
    'git',
    '--no-pager',
    '-c',
    'core.quotePath=false',
    'show',
    '--format=%x1e%H',
    '--first-parent',
    '-m',
    '--root',
    output_kind == 'numstat' and '--numstat' or '--name-status',
  }
  for _, commit_hash in ipairs(commit_hashes or {}) do
    command[#command + 1] = commit_hash
  end
  return command
end

local function parse_detail_sections(output)
  local sections = {}
  for raw_section in (output or ''):gmatch(
      preview_record_separator .. '([^' .. preview_record_separator .. ']*)'
    ) do
    local section_lines = M.output_lines(raw_section)
    local commit_hash = vim.trim(section_lines[1] or '')
    if commit_hash:match('^[0-9a-fA-F]+$') then
      table.remove(section_lines, 1)
      while section_lines[1] == '' do
        table.remove(section_lines, 1)
      end
      sections[commit_hash] = section_lines
    end
  end
  return sections
end

function M.parse_history_details(name_status_output, numstat_output)
  local name_sections = parse_detail_sections(name_status_output)
  local numstat_sections = parse_detail_sections(numstat_output)
  local details_by_hash = {}
  for commit_hash, name_lines in pairs(name_sections) do
    local numstat_lines = numstat_sections[commit_hash]
    if numstat_lines then
      local detail_files = {}
      for line_index, name_line in ipairs(name_lines) do
        local name_fields = vim.split(name_line, '\t', { plain = true })
        local status = name_fields[1]
        local original_path = #name_fields >= 3 and name_fields[2] or nil
        local path = #name_fields >= 3 and name_fields[3] or name_fields[2]
        local stat_fields = vim.split(numstat_lines[line_index] or '', '\t', { plain = true })
        if status and status ~= '' and path and path ~= '' then
          local additions = tonumber(stat_fields[1])
          local deletions = tonumber(stat_fields[2])
          detail_files[#detail_files + 1] = {
            original_path = original_path,
            path = path,
            stats = additions and deletions and {
              additions = additions,
              deletions = deletions,
            } or nil,
            status = status:sub(1, 1),
          }
        end
      end
      details_by_hash[commit_hash] = detail_files
    end
  end
  return details_by_hash
end

function M.parse_history_rows(output)
  local rows = {}
  for raw_record in (output or ''):gmatch(preview_record_separator .. '([^' .. preview_record_separator .. ']*)') do
    local normalized_record = raw_record:gsub('\r?\n$', '')
    local fields = vim.split(normalized_record, preview_field_separator, { plain = true })
    local commit_time = tonumber(fields[4])
    local time_offset = (fields[5] or ''):match('([+-]%d%d%d%d)$')
    local commit_hash = fields[1]
    if commit_hash
        and commit_hash:match('^[0-9a-fA-F]+$')
        and commit_time then
      rows[#rows + 1] = {
        author = fields[3] or '',
        hash = commit_hash,
        parent_hashes = vim.split(fields[2] or '', ' ', { plain = true, trimempty = true }),
        ref_names = fields[7] or '',
        reflog_selector = fields[8] or '',
        rel_date = fields[6] or '',
        subject = table.concat(fields, preview_field_separator, 9),
        time = commit_time,
        time_offset = time_offset or '+0000',
      }
    end
  end
  return rows
end

function M.parse_containing_refs(output)
  local containing_refs = {}
  for _, output_line in ipairs(M.output_lines(output)) do
    local is_local_ref = vim.startswith(output_line, 'refs/heads/')
    local is_remote_ref = vim.startswith(output_line, 'refs/remotes/')
    local is_remote_head = is_remote_ref and output_line:match('/HEAD$') ~= nil
    if (is_local_ref or is_remote_ref) and not is_remote_head then
      containing_refs[output_line] = true
    end
  end
  return containing_refs
end

function M.prioritize_detached_branches(
    branches,
    detached_commit,
    containing_refs,
    preferred_branch_name
)
  local ranked_branches = {}
  for branch_index, branch in ipairs(branches) do
    local ranked_branch = vim.deepcopy(branch)
    local branch_ref = ranked_branch.refname or ''
    local branch_name = ranked_branch.short_name or branch_ref
    local contains_detached_head = containing_refs[branch_ref] == true
      or ranked_branch.tip_commit == detached_commit
    local relation_rank = ranked_branch.is_remote and 6 or 5
    if contains_detached_head then
      ranked_branch.detached_relation = ranked_branch.tip_commit == detached_commit
          and 'tip'
        or 'ancestor'
      if ranked_branch.is_remote then
        relation_rank = ranked_branch.detached_relation == 'tip' and 3 or 4
      else
        relation_rank = ranked_branch.detached_relation == 'tip' and 1 or 2
      end
    end
    ranked_branches[#ranked_branches + 1] = {
      branch = ranked_branch,
      original_index = branch_index,
      preferred = contains_detached_head
        and preferred_branch_name ~= nil
        and (branch_ref == preferred_branch_name or branch_name == preferred_branch_name),
      relation_rank = relation_rank,
    }
  end
  table.sort(ranked_branches, function(left, right)
    if left.relation_rank ~= right.relation_rank then
      return left.relation_rank < right.relation_rank
    end
    if left.preferred ~= right.preferred then
      return left.preferred
    end
    return left.original_index < right.original_index
  end)
  local prioritized_branches = {}
  for _, ranked_entry in ipairs(ranked_branches) do
    prioritized_branches[#prioritized_branches + 1] = ranked_entry.branch
  end
  return prioritized_branches
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
