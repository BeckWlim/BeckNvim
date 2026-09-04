local repository = require('config.git.repository')

local M = {}

local function is_github_host(host)
  return host:lower():find('github', 1, true) ~= nil
end

function M.parse_remote_url(remote_url)
  local host, owner, repository_name = remote_url:match('^git@([^:]+):([^/]+)/(.+)$')
  if not host then
    host, owner, repository_name = remote_url:match('^ssh://git@([^/]+)/([^/]+)/(.+)$')
  end
  if not host then
    host, owner, repository_name = remote_url:match('^https?://([^/]+)/([^/]+)/(.+)$')
  end
  if not host or not owner or not repository_name or not is_github_host(host) then
    return nil
  end
  local normalized_repository_name = repository_name:gsub('/+$', ''):gsub('%.git$', '')
  if normalized_repository_name == '' or normalized_repository_name:find('/', 1, true) then
    return nil
  end
  return {
    host = host:lower(),
    owner = owner,
    repository = normalized_repository_name,
  }
end

function M.parse_record_url(record_url)
  local host, owner, repository_name, resource_segment, issue_digits, suffix = record_url:match(
    '^https?://([^/]+)/([^/]+)/([^/]+)/([^/]+)/(%d+)(.*)$'
  )
  if not host
      or not owner
      or not repository_name
      or not resource_segment
      or not issue_digits
      or not is_github_host(host)
      or (resource_segment ~= 'issues' and resource_segment ~= 'pull')
      or (suffix ~= '' and not suffix:match('^[/?#]')) then
    return nil
  end
  return {
    kind = resource_segment == 'pull' and 'Pull request' or 'Issue',
    number = tonumber(issue_digits),
    remote = {
      host = host:lower(),
      owner = owner,
      repository = repository_name,
    },
  }
end

local function remote_priority(remote_name)
  if remote_name == 'origin' then
    return 1
  end
  if remote_name == 'upstream' then
    return 2
  end
  return 3
end

function M.parse_remote_config(output)
  local ranked_candidates = {}
  local seen_repositories = {}
  for record_index, config_record in ipairs(vim.split(output or '', '\0', { plain = true })) do
    local config_key, remote_url = config_record:match('^([^\n]+)\n(.+)$')
    local remote_name = config_key and config_key:match('^remote%.(.+)%.url$') or nil
    local remote = remote_url and M.parse_remote_url(remote_url) or nil
    if remote_name and remote then
      local repository_identity = ('%s/%s/%s'):format(
        remote.host,
        remote.owner,
        remote.repository
      ):lower()
      if not seen_repositories[repository_identity] then
        seen_repositories[repository_identity] = true
        remote.name = remote_name
        ranked_candidates[#ranked_candidates + 1] = {
          index = record_index,
          priority = remote_priority(remote_name),
          remote = remote,
        }
      end
    end
  end
  table.sort(ranked_candidates, function(left, right)
    if left.priority ~= right.priority then
      return left.priority < right.priority
    end
    return left.index < right.index
  end)
  local remote_candidates = {}
  for _, ranked_candidate in ipairs(ranked_candidates) do
    remote_candidates[#remote_candidates + 1] = ranked_candidate.remote
  end
  return remote_candidates
end

function M.parse_git_output(output, issue_number)
  local numeric_issue_number = tonumber(issue_number)
  if not numeric_issue_number then
    return {}
  end
  local record_references = {}
  for _, remote in ipairs(M.parse_remote_config(output)) do
    record_references[#record_references + 1] = {
      number = numeric_issue_number,
      remote = remote,
    }
  end
  return record_references
end

function M.resolve_local(root, issue_number, callback)
  local normalized_root = vim.fs.normalize(root)
  return repository.start(
    repository.commands.remote_urls(),
    normalized_root,
    function(remote_process)
      if remote_process.code ~= 0 then
        callback(nil, repository.concise_error(remote_process))
        return
      end
      callback(M.parse_git_output(remote_process.stdout, issue_number), nil)
    end
  )
end

return M
