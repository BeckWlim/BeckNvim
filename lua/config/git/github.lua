local repository = require('config.git.repository')
local proxy = require('config.network.proxy')

local M = {}

local function parse_remote_url(remote_url)
  local host, owner, repository_name = remote_url:match('^git@([^:]+):([^/]+)/(.+)$')
  if not host then
    host, owner, repository_name = remote_url:match('^ssh://git@([^/]+)/([^/]+)/(.+)$')
  end
  if not host then
    host, owner, repository_name = remote_url:match('^https?://([^/]+)/([^/]+)/(.+)$')
  end
  if not host or not owner or not repository_name then
    return nil
  end
  local normalized_host = host:lower()
  if not normalized_host:find('github', 1, true) then
    return nil
  end
  local normalized_repository_name = repository_name:gsub('/+$', ''):gsub('%.git$', '')
  if normalized_repository_name == '' or normalized_repository_name:find('/', 1, true) then
    return nil
  end
  return {
    host = normalized_host,
    owner = owner,
    repository = normalized_repository_name,
  }
end

local function issue_url(remote, issue_number)
  local api_root = remote.host == 'github.com'
      and 'https://api.github.com'
    or ('https://%s/api/v3'):format(remote.host)
  return ('%s/repos/%s/%s/issues/%s'):format(
    api_root,
    remote.owner,
    remote.repository,
    issue_number
  )
end

local function web_issue_url(remote, issue_number)
  return ('https://%s/%s/%s/issues/%s'):format(
    remote.host,
    remote.owner,
    remote.repository,
    issue_number
  )
end

local function authentication_token(host)
  if host == 'github.com' then
    return vim.env.GH_TOKEN or vim.env.GITHUB_TOKEN
  end
  return vim.env.GH_ENTERPRISE_TOKEN or vim.env.GITHUB_ENTERPRISE_TOKEN
end

local function request_headers(host)
  local headers = {
    'Accept: application/vnd.github+json',
    'X-GitHub-Api-Version: 2026-03-10',
    'User-Agent: nvim-git-inspector',
  }
  local token = authentication_token(host)
  if token and token ~= '' then
    headers[#headers + 1] = 'Authorization: Bearer ' .. token
  end
  return table.concat(headers, '\n') .. '\n'
end

local function start_request(remote, issue_number, callback)
  local command = {
    'curl',
    '--silent',
    '--show-error',
    '--fail-with-body',
    '--location',
    '--header',
    '@-',
    issue_url(remote, issue_number),
  }
  local process
  local proxy_environment = proxy.resolve()
  local process_started, start_error = pcall(function()
    process = vim.system(command, {
      env = proxy_environment,
      stdin = request_headers(remote.host),
      text = true,
    }, function(completed_process)
      vim.schedule(function()
        callback(completed_process)
      end)
    end)
  end)
  if not process_started then
    vim.schedule(function()
      callback({ code = -1, stderr = tostring(start_error), stdout = '' })
    end)
  end
  return function()
    if process then
      pcall(process.kill, process, 15)
    end
  end
end

local html_entities = {
  amp = '&',
  apos = "'",
  gt = '>',
  lt = '<',
  quot = '"',
}

local function decode_html(value)
  local decoded_named_entities = value:gsub('&([%a]+);', function(entity_name)
    return html_entities[entity_name] or ('&' .. entity_name .. ';')
  end)
  return decoded_named_entities:gsub('&#(%d+);', function(codepoint)
    return vim.fn.nr2char(tonumber(codepoint))
  end)
end

local function meta_content(document, attribute, value)
  for meta_tag in document:gmatch('<meta%s+[^>]*>') do
    local tag_attribute = meta_tag:match(attribute .. '=["\'](.-)["\']')
    if tag_attribute == value then
      local content = meta_tag:match('content=["\'](.-)["\']')
      if content then
        return decode_html(content)
      end
    end
  end
end

local function parse_issue_html(response_body, remote, issue_number)
  local raw_title = meta_content(response_body, 'property', 'og:title')
    or meta_content(response_body, 'name', 'twitter:title')
  if not raw_title then
    return nil, 'GitHub project page did not expose issue metadata'
  end
  local issue_suffix_pattern = '%s+·%s+Issue%s+#' .. issue_number .. '%s+·.*$'
  local pull_request_suffix_pattern = '%s+·%s+Pull Request%s+#'
    .. issue_number
    .. '%s+·.*$'
  local title_without_issue_suffix = raw_title:gsub(issue_suffix_pattern, '')
  local title = title_without_issue_suffix:gsub(pull_request_suffix_pattern, '')
  if title == '' or title == raw_title then
    title = raw_title:gsub('%s+·%s+#' .. issue_number .. '%s+·.*$', '')
  end
  local description = meta_content(response_body, 'property', 'og:description') or ''
  local issue_kind = raw_title:find('Pull Request', 1, true) and 'Pull request' or 'Issue'
  return {
    author = 'github.com',
    body = description,
    comments = 0,
    created_at = '',
    html_url = web_issue_url(remote, issue_number),
    kind = issue_kind,
    labels = {},
    number = tonumber(issue_number),
    state = 'remote',
    title = title,
    updated_at = '',
  }
end

local function start_web_request(remote, issue_number, callback)
  local command = {
    'curl',
    '--silent',
    '--show-error',
    '--fail-with-body',
    '--location',
    '--header',
    'User-Agent: nvim-git-inspector',
    web_issue_url(remote, issue_number),
  }
  local proxy_environment = proxy.resolve()
  local process
  local process_started, start_error = pcall(function()
    process = vim.system(command, {
      env = proxy_environment,
      text = true,
    }, function(completed_process)
      vim.schedule(function()
        callback(completed_process)
      end)
    end)
  end)
  if not process_started then
    vim.schedule(function()
      callback({ code = -1, stderr = tostring(start_error), stdout = '' })
    end)
  end
  return function()
    if process then
      pcall(process.kill, process, 15)
    end
  end
end

local function annotate_remote(issue, remote)
  issue.remote_host = remote.host
  issue.remote_repository = ('%s/%s'):format(remote.owner, remote.repository)
  return issue
end

local function parse_issue(response_body)
  local decoded_successfully, response_document = pcall(vim.json.decode, response_body)
  if not decoded_successfully or type(response_document) ~= 'table' then
    return nil, 'GitHub returned an invalid issue response'
  end
  if type(response_document.number) ~= 'number' or type(response_document.title) ~= 'string' then
    return nil, response_document.message or 'GitHub issue response is incomplete'
  end
  local labels = {}
  for _, raw_label in ipairs(response_document.labels or {}) do
    if type(raw_label) == 'table' and type(raw_label.name) == 'string' then
      labels[#labels + 1] = raw_label.name
    elseif type(raw_label) == 'string' then
      labels[#labels + 1] = raw_label
    end
  end
  return {
    author = response_document.user and response_document.user.login or 'unknown',
    body = response_document.body or '',
    comments = response_document.comments or 0,
    created_at = response_document.created_at or '',
    html_url = response_document.html_url or '',
    kind = response_document.pull_request and 'Pull request' or 'Issue',
    labels = labels,
    number = response_document.number,
    state = response_document.state or 'unknown',
    title = response_document.title,
    updated_at = response_document.updated_at or '',
  }
end

M.parse_remote_url = parse_remote_url
M.parse_issue = parse_issue
M.parse_issue_html = parse_issue_html

function M.fetch_issue(root, issue_number, callback)
  local cancelled = false
  local cancel_active_process = function() end
  cancel_active_process = repository.start(
    { 'git', 'remote', 'get-url', 'origin' },
    root,
    function(remote_process)
      if cancelled then
        return
      end
      if remote_process.code ~= 0 then
        callback(nil, repository.concise_error(remote_process))
        return
      end
      local remote_lines = repository.output_lines(remote_process.stdout)
      local remote = remote_lines[1] and parse_remote_url(remote_lines[1]) or nil
      if not remote then
        callback(nil, 'The origin remote is not a supported GitHub repository')
        return
      end
      cancel_active_process = start_request(remote, issue_number, function(issue_process)
        if cancelled then
          return
        end
        if issue_process.code ~= 0 then
          local decoded_successfully, error_document = pcall(
            vim.json.decode,
            issue_process.stdout or ''
          )
          local response_error = repository.concise_error(issue_process)
          if decoded_successfully
              and type(error_document) == 'table'
              and type(error_document.message) == 'string' then
            response_error = error_document.message
          end
          if remote.host ~= 'github.com' then
            callback(nil, response_error)
            return
          end
          cancel_active_process = start_web_request(remote, issue_number, function(web_process)
            if cancelled then
              return
            end
            if web_process.code ~= 0 then
              callback(nil, response_error)
              return
            end
            local web_issue, web_parse_error = parse_issue_html(
              web_process.stdout or '',
              remote,
              issue_number
            )
            callback(web_issue and annotate_remote(web_issue, remote), web_parse_error)
          end)
          return
        end
        local issue, parse_error = parse_issue(issue_process.stdout or '')
        if issue then
          annotate_remote(issue, remote)
        end
        callback(issue, parse_error)
      end)
    end
  )
  return function()
    cancelled = true
    cancel_active_process()
  end
end

return M
