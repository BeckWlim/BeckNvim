local repository = require('config.git.repository')
local reference = require('config.git.reference')
local proxy = require('config.network.proxy')

local M = {}

local function normalize_newlines(value)
  if type(value) ~= 'string' then
    return ''
  end
  local lf_text = value:gsub('\r\n', '\n')
  return lf_text:gsub('\r', '\n')
end

local function issue_endpoint(remote, issue_number)
  return ('repos/%s/%s/issues/%s'):format(
    remote.owner,
    remote.repository,
    issue_number
  )
end

local function pull_request_endpoint(remote, issue_number)
  return ('repos/%s/%s/pulls/%s'):format(
    remote.owner,
    remote.repository,
    issue_number
  )
end

local function record_endpoint(remote, issue_number, expected_kind)
  if expected_kind == 'Pull request' then
    return pull_request_endpoint(remote, issue_number)
  end
  return issue_endpoint(remote, issue_number)
end

local function comments_endpoint(remote, issue_number)
  return issue_endpoint(remote, issue_number) .. '/comments?per_page=100'
end

local function api_url(remote, endpoint)
  local api_root = remote.host == 'github.com'
      and 'https://api.github.com'
    or ('https://%s/api/v3'):format(remote.host)
  return ('%s/%s'):format(api_root, endpoint)
end

local function record_url(remote, issue_number, expected_kind)
  return api_url(remote, record_endpoint(remote, issue_number, expected_kind))
end

local function comments_url(remote, issue_number)
  return api_url(remote, comments_endpoint(remote, issue_number))
end

local function web_record_url(remote, issue_number, record_kind)
  local resource_segment = record_kind == 'Pull request' and 'pull' or 'issues'
  return ('https://%s/%s/%s/%s/%s'):format(
    remote.host,
    remote.owner,
    remote.repository,
    resource_segment,
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

local WATCHDOG_TIMEOUT_MS = 8000
local WATCHDOG_TIMEOUT_MARKER = 'github request watchdog timeout'

-- Network-class failures mean the remote (or the configured proxy) cannot be
-- reached at all. Retrying or falling back to another transport just multiplies
-- the wait, so the fetch aborts immediately instead.
local function is_unreachable_process_error(completed_process)
  if not completed_process or completed_process.code == 0 then
    return false
  end
  local detail = ((completed_process.stderr or '') .. '\n' .. (completed_process.stdout or ''))
    :lower()
  return detail:find(WATCHDOG_TIMEOUT_MARKER, 1, true) ~= nil
    or detail:find('failed to connect', 1, true) ~= nil
    or detail:find('could not resolve', 1, true) ~= nil
    or detail:find('couldn\'t connect', 1, true) ~= nil
    or detail:find('connection refused', 1, true) ~= nil
    or detail:find('connection timed out', 1, true) ~= nil
    or detail:find('no such host', 1, true) ~= nil
    or detail:find('dial tcp', 1, true) ~= nil
    or detail:find('i/o timeout', 1, true) ~= nil
    or detail:find('context deadline exceeded', 1, true) ~= nil
end

local function unreachable_error(completed_process)
  return ('GitHub remote is unreachable: %s'):format(
    repository.concise_error(completed_process)
  )
end

local function start_api_request(remote, request_url, max_time_seconds, callback)
  local command = {
    'curl',
    '--silent',
    '--show-error',
    '--fail-with-body',
    '--location',
    '--connect-timeout',
    '5',
    '--max-time',
    tostring(max_time_seconds),
    '--header',
    '@-',
    request_url,
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

local function github_cli_available()
  return vim.fn.executable('gh') == 1
end

local function start_github_cli_request(remote, endpoint, callback)
  local command = { 'gh', 'api', '--method', 'GET' }
  if remote.host ~= 'github.com' then
    vim.list_extend(command, { '--hostname', remote.host })
  end
  command[#command + 1] = endpoint
  local proxy_environment = proxy.resolve()
  local process
  local finished = false
  local function finish_once(completed_process)
    if finished then
      return
    end
    finished = true
    vim.schedule(function()
      callback(completed_process)
    end)
  end
  -- `gh` has no request timeout of its own; a dead proxy or blackholed host can
  -- park it for minutes, so a watchdog bounds the wait.
  local watchdog = vim.uv.new_timer()
  if watchdog then
    watchdog:start(WATCHDOG_TIMEOUT_MS, 0, function()
      if finished then
        return
      end
      if process then
        pcall(process.kill, process, 15)
      end
      finish_once({ code = -2, stderr = WATCHDOG_TIMEOUT_MARKER, stdout = '' })
    end)
  end
  local function stop_watchdog()
    if watchdog and not watchdog:is_closing() then
      watchdog:stop()
      watchdog:close()
    end
  end
  local process_started, start_error = pcall(function()
    process = vim.system(command, {
      env = proxy_environment,
      text = true,
    }, function(completed_process)
      stop_watchdog()
      finish_once(completed_process)
    end)
  end)
  if not process_started then
    stop_watchdog()
    finish_once({ code = -1, stderr = tostring(start_error), stdout = '' })
  end
  return function()
    stop_watchdog()
    finished = true
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

local function is_embedded_data_script(attributes)
  return attributes:find('data-target="react-app.embeddedData"', 1, true) ~= nil
    or attributes:find("data-target='react-app.embeddedData'", 1, true) ~= nil
    or attributes:find('data-target="react-partial.embeddedData"', 1, true) ~= nil
    or attributes:find("data-target='react-partial.embeddedData'", 1, true) ~= nil
end

local function embedded_record_score(value, numeric_issue_number)
  if tonumber(value.number) ~= numeric_issue_number or type(value.title) ~= 'string' then
    return 0
  end
  local score = 1
  if type(value.body) == 'string' then
    score = score + 4
  end
  if type(value.createdAt) == 'string' or type(value.created_at) == 'string' then
    score = score + 2
  end
  if type(value.author) == 'table' or type(value.user) == 'table' then
    score = score + 2
  end
  if value.__typename == 'Issue' or value.__typename == 'PullRequest' then
    score = score + 4
  end
  return score
end

local function find_embedded_record(value, numeric_issue_number, current_record, current_score)
  if type(value) ~= 'table' then
    return current_record, current_score
  end
  local candidate_score = embedded_record_score(value, numeric_issue_number)
  local best_record = current_record
  local best_score = current_score
  if candidate_score > best_score then
    best_record = value
    best_score = candidate_score
  end
  for _, child_value in pairs(value) do
    if type(child_value) == 'table' then
      best_record, best_score = find_embedded_record(
        child_value,
        numeric_issue_number,
        best_record,
        best_score
      )
    end
  end
  return best_record, best_score
end

local function embedded_issue_record(document, issue_number)
  local numeric_issue_number = tonumber(issue_number)
  local best_record
  local best_score = 0
  for attributes, script_content in document:gmatch('<script%s+([^>]*)>(.-)</script>') do
    if is_embedded_data_script(attributes) then
      local decoded_successfully, embedded_document = pcall(vim.json.decode, script_content)
      if decoded_successfully and type(embedded_document) == 'table' then
        best_record, best_score = find_embedded_record(
          embedded_document,
          numeric_issue_number,
          best_record,
          best_score
        )
      end
    end
  end
  return best_record
end

local function structured_issue_record(document)
  local function find_discussion_record(value)
    if type(value) ~= 'table' then
      return nil
    end
    if value['@type'] == 'DiscussionForumPosting' then
      return value
    end
    for _, child_value in pairs(value) do
      local discussion_record = find_discussion_record(child_value)
      if discussion_record then
        return discussion_record
      end
    end
  end
  for attributes, script_content in document:gmatch('<script%s+([^>]*)>(.-)</script>') do
    if attributes:match('type=["\']application/ld%+json["\']') then
      local decoded_successfully, structured_document = pcall(vim.json.decode, script_content)
      if decoded_successfully then
        local discussion_record = find_discussion_record(structured_document)
        if discussion_record then
          return discussion_record
        end
      end
    end
  end
end

local function embedded_labels(issue_record)
  local labels = {}
  local label_collection = issue_record and issue_record.labels
  local label_values = label_collection and (label_collection.edges or label_collection.nodes)
    or label_collection
    or {}
  for _, label_value in ipairs(label_values) do
    local label_node = type(label_value) == 'table' and (label_value.node or label_value)
      or label_value
    local label_name = type(label_node) == 'table' and label_node.name or label_node
    if type(label_name) == 'string' then
      labels[#labels + 1] = label_name
    end
  end
  return labels
end

local function embedded_comment_count(embedded_record)
  if not embedded_record then
    return 0
  end
  if type(embedded_record.comments) == 'number' then
    return embedded_record.comments
  end
  if type(embedded_record.comments) == 'table'
      and type(embedded_record.comments.totalCount) == 'number' then
    return embedded_record.comments.totalCount
  end
  return embedded_record.totalCommentsCount
    or embedded_record.commentCount
    or 0
end

local function structured_comment_count(structured_record)
  local interaction_statistics = structured_record and structured_record.interactionStatistic
  if type(interaction_statistics) ~= 'table' then
    return 0
  end
  if type(interaction_statistics.userInteractionCount) == 'number' then
    return interaction_statistics.userInteractionCount
  end
  for _, statistic in ipairs(interaction_statistics) do
    if type(statistic) == 'table'
        and type(statistic.userInteractionCount) == 'number' then
      return statistic.userInteractionCount
    end
  end
  return 0
end

local function parse_issue_html(response_body, remote, issue_number, expected_kind)
  local embedded_record = embedded_issue_record(response_body, issue_number)
  local structured_record = structured_issue_record(response_body)
  local raw_title = embedded_record and embedded_record.title
    or structured_record and structured_record.headline
    or meta_content(response_body, 'property', 'og:title')
    or meta_content(response_body, 'name', 'twitter:title')
  if not raw_title then
    return nil, 'GitHub project page did not expose issue metadata'
  end
  local issue_suffix_pattern = '%s+·%s+Issue%s+#' .. issue_number .. '%s+·.*$'
  local pull_request_byline_suffix_pattern = '%s+by%s+[^·]+%s+·%s+Pull Request%s+#'
    .. issue_number
    .. '%s+·.*$'
  local pull_request_suffix_pattern = '%s+·%s+Pull Request%s+#'
    .. issue_number
    .. '%s+·.*$'
  local title_without_issue_suffix = raw_title:gsub(issue_suffix_pattern, '')
  local title_without_pull_request_byline = title_without_issue_suffix:gsub(
    pull_request_byline_suffix_pattern,
    ''
  )
  local primary_stripped_title = title_without_pull_request_byline:gsub(
    pull_request_suffix_pattern,
    ''
  )
  local fallback_stripped_title = raw_title:gsub(
    '%s+·%s+#' .. issue_number .. '%s+·.*$',
    ''
  )
  local resolved_title = primary_stripped_title == '' or primary_stripped_title == raw_title
      and fallback_stripped_title
    or primary_stripped_title
  local title = normalize_newlines(resolved_title)
  local description = embedded_record and (embedded_record.body or embedded_record.bodyText)
    or structured_record and structured_record.articleBody
    or meta_content(response_body, 'property', 'og:description')
    or ''
  local embedded_author = embedded_record and embedded_record.author
  local embedded_user = embedded_record and embedded_record.user
  local structured_author = structured_record and structured_record.author
  local embedded_kind = embedded_record and (embedded_record.__typename or embedded_record.type)
  local embedded_comments = embedded_comment_count(embedded_record)
  local metadata_source = embedded_record and 'embedded'
    or structured_record and 'structured'
    or 'open_graph'
  local issue_kind = embedded_kind == 'PullRequest'
      and 'Pull request'
    or expected_kind == 'Pull request' and 'Pull request'
    or raw_title:find('Pull Request', 1, true) and 'Pull request'
    or 'Issue'
  return {
    author = embedded_author and (embedded_author.login or embedded_author.name)
      or embedded_user and (embedded_user.login or embedded_user.name)
      or structured_author and structured_author.name
      or 'github.com',
    body = normalize_newlines(description),
    comments = embedded_comments > 0
        and embedded_comments
      or structured_comment_count(structured_record),
    created_at = embedded_record and (embedded_record.createdAt or embedded_record.created_at)
      or structured_record and structured_record.datePublished
      or '',
    html_url = web_record_url(remote, issue_number, issue_kind),
    kind = issue_kind,
    labels = embedded_labels(embedded_record),
    number = tonumber(issue_number),
    state = embedded_record and embedded_record.mergedAt
        and 'merged'
      or embedded_record and type(embedded_record.state) == 'string'
        and embedded_record.state:lower()
      or 'remote',
    title = title,
    updated_at = embedded_record
        and (embedded_record.updatedAt or embedded_record.updated_at)
      or '',
  }, nil, metadata_source
end

local function start_web_request(remote, issue_number, record_kind, callback)
  local command = {
    'curl',
    '--silent',
    '--show-error',
    '--fail-with-body',
    '--location',
    '--connect-timeout',
    '5',
    '--max-time',
    '20',
    '--header',
    'Accept: text/html,application/xhtml+xml',
    '--header',
    'User-Agent: Mozilla/5.0 (X11; Linux x86_64) nvim-git-inspector',
    web_record_url(remote, issue_number, record_kind),
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

local function parse_issue(response_body, expected_kind)
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
  local record_kind = expected_kind == 'Pull request'
      and 'Pull request'
    or response_document.pull_request and 'Pull request'
    or 'Issue'
  local record_state = record_kind == 'Pull request' and response_document.merged_at
      and 'merged'
    or response_document.state
    or 'unknown'
  local commit_sha = record_kind == 'Pull request'
      and response_document.head
      and response_document.head.sha
    or nil
  local commit_shas = {}
  if type(response_document.commits) == 'table' then
    for _, commit in ipairs(response_document.commits) do
      if type(commit) == 'table' and type(commit.sha) == 'string' then
        commit_shas[#commit_shas + 1] = commit.sha
      end
    end
  end
  if #commit_shas == 0 and type(commit_sha) == 'string' then
    commit_shas[1] = commit_sha
  end
  return {
    author = response_document.user and response_document.user.login or 'unknown',
    body = normalize_newlines(response_document.body),
    comments = response_document.comments or 0,
    commit_sha = type(commit_sha) == 'string' and commit_sha or nil,
    commit_shas = commit_shas,
    created_at = response_document.created_at or '',
    html_url = response_document.html_url or '',
    kind = record_kind,
    labels = labels,
    number = response_document.number,
    state = record_state,
    title = normalize_newlines(response_document.title),
    updated_at = response_document.updated_at or '',
  }
end

local function parse_comments(response_body)
  local decoded_successfully, response_document = pcall(vim.json.decode, response_body)
  if not decoded_successfully or type(response_document) ~= 'table' then
    return nil, 'GitHub returned an invalid discussion response'
  end
  if not vim.islist(response_document) then
    return nil, response_document.message or 'GitHub discussion response is incomplete'
  end
  local discussion = {}
  for _, comment_document in ipairs(response_document) do
    if type(comment_document) == 'table' and type(comment_document.body) == 'string' then
      discussion[#discussion + 1] = {
        author = comment_document.user and comment_document.user.login or 'unknown',
        body = normalize_newlines(comment_document.body),
        created_at = comment_document.created_at or '',
        html_url = comment_document.html_url or '',
        updated_at = comment_document.updated_at or '',
      }
    end
  end
  return discussion, nil
end

local function issue_process_error(issue_process)
  local decoded_successfully, error_document = pcall(
    vim.json.decode,
    issue_process.stdout or ''
  )
  if decoded_successfully
      and type(error_document) == 'table'
      and type(error_document.message) == 'string' then
    return error_document.message
  end
  return repository.concise_error(issue_process)
end

local function process_reports_not_found(issue_process)
  local process_error = (issue_process.stderr or ''):lower()
  if process_error:match('http[^%d]*404')
      or process_error:match('error:%s*404') then
    return true
  end
  local decoded_successfully, response_document = pcall(
    vim.json.decode,
    issue_process.stdout or ''
  )
  return decoded_successfully
    and type(response_document) == 'table'
    and type(response_document.message) == 'string'
    and response_document.message:lower() == 'not found'
end

local function fetch_remote_issue(remote, issue_number, callback, expected_kind)
  local cancelled = false
  local process_cancellations = {}
  local function track_process(cancel_process)
    process_cancellations[#process_cancellations + 1] = cancel_process
  end

  local function finish(issue, issue_error, issue_not_found, issue_unreachable)
    if not cancelled then
      callback(issue, issue_error, issue_not_found, issue_unreachable)
    end
  end

  local function finish_with_discussion(issue)
    if issue.comments == 0 then
      issue.discussion = {}
      issue.discussion_complete = true
      finish(issue, nil, nil)
      return
    end
    local function finish_comments_request(comments_process)
      if cancelled then
        return
      end
      if comments_process.code ~= 0 then
        issue.discussion = {}
        issue.discussion_complete = false
        issue.discussion_error = issue_process_error(comments_process)
        finish(issue, nil, nil)
        return
      end
      local discussion, discussion_error = parse_comments(comments_process.stdout or '')
      issue.discussion = discussion or {}
      issue.discussion_complete = discussion ~= nil and #discussion >= issue.comments
      issue.discussion_error = discussion_error
      finish(issue, nil, nil)
    end
    local function request_comments_with_curl()
      track_process(start_api_request(
        remote,
        comments_url(remote, issue_number),
        10,
        finish_comments_request
      ))
    end
    if github_cli_available() then
      track_process(start_github_cli_request(
        remote,
        comments_endpoint(remote, issue_number),
        function(comments_process)
          if cancelled then
            return
          end
          if comments_process.code == 0 then
            finish_comments_request(comments_process)
            return
          end
          request_comments_with_curl()
        end
      ))
    else
      request_comments_with_curl()
    end
  end

  local function request_public_page(response_error)
    if remote.host ~= 'github.com' then
      finish(nil, response_error)
      return
    end
    local web_record_kind = expected_kind or 'Issue'
    track_process(start_web_request(remote, issue_number, web_record_kind, function(web_process)
      if cancelled then
        return
      end
      if web_process.code ~= 0 then
        if process_reports_not_found(web_process) then
          finish(nil, nil, true)
          return
        end
        finish(
          nil,
          ('%s; public page: %s'):format(
            response_error,
            repository.concise_error(web_process)
          )
        )
        return
      end
      local web_issue, web_parse_error, metadata_source = parse_issue_html(
        web_process.stdout or '',
        remote,
        issue_number,
        expected_kind
      )
      if web_issue then
        if expected_kind and metadata_source == 'open_graph' then
          finish(nil, 'GitHub public page exposed only truncated preview metadata')
          return
        end
        finish_with_discussion(annotate_remote(web_issue, remote))
        return
      end
      finish(nil, web_parse_error)
    end))
  end

  local function request_with_curl()
    local request_url = record_url(remote, issue_number, expected_kind)
    track_process(start_api_request(remote, request_url, 20, function(issue_process)
      if cancelled then
        return
      end
      if issue_process.code == 0 then
        local issue, parse_error = parse_issue(issue_process.stdout or '', expected_kind)
        if issue then
          finish_with_discussion(annotate_remote(issue, remote))
          return
        end
        request_public_page(parse_error)
        return
      end
      if process_reports_not_found(issue_process) then
        finish(nil, nil, true)
        return
      end
      if is_unreachable_process_error(issue_process) then
        finish(nil, unreachable_error(issue_process), nil, true)
        return
      end
      request_public_page(issue_process_error(issue_process))
    end))
  end

  if github_cli_available() then
    local request_endpoint = record_endpoint(remote, issue_number, expected_kind)
    track_process(start_github_cli_request(
      remote,
      request_endpoint,
      function(issue_process)
        if cancelled then
          return
        end
        if issue_process.code == 0 then
          local issue = parse_issue(issue_process.stdout or '', expected_kind)
          if issue then
            finish_with_discussion(annotate_remote(issue, remote))
            return
          end
        end
        if process_reports_not_found(issue_process) then
          finish(nil, nil, true)
          return
        end
        if is_unreachable_process_error(issue_process) then
          finish(nil, unreachable_error(issue_process), nil, true)
          return
        end
        if authentication_token(remote.host) then
          request_with_curl()
        else
          request_public_page(issue_process_error(issue_process))
        end
      end
    ))
  else
    request_with_curl()
  end

  return function()
    cancelled = true
    for _, cancel_process in ipairs(process_cancellations) do
      cancel_process()
    end
  end
end

M.parse_remote_url = reference.parse_remote_url
M.parse_remote_candidates = reference.parse_remote_config
M.parse_record_url = reference.parse_record_url
M.parse_issue = parse_issue
M.parse_issue_html = parse_issue_html
M.parse_comments = parse_comments
M.is_unreachable_process_error = is_unreachable_process_error

function M.fetch_record(record_reference, callback)
  local remote = record_reference.remote
  local issue_number = tostring(record_reference.number)
  return fetch_remote_issue(remote, issue_number, function(issue, issue_error, issue_not_found)
    if issue_not_found then
      local record_label = record_reference.kind and record_reference.kind:lower() or 'record'
      callback(nil, ('GitHub %s #%s was not found'):format(
        record_label,
        issue_number
      ))
      return
    end
    callback(issue, issue_error)
  end, record_reference.kind)
end

function M.fetch_issue(root, issue_number, callback)
  local cancelled = false
  local completed = false
  local process_cancellations = {}
  local remote_errors = {}
  local missing_remote_count = 0
  local function track_process(cancel_process)
    process_cancellations[#process_cancellations + 1] = cancel_process
  end
  local function finish(issue, issue_error)
    if cancelled or completed then
      return
    end
    completed = true
    callback(issue, issue_error)
  end
  local function try_record(record_references, record_index)
    if cancelled or completed then
      return
    end
    local record_reference = record_references[record_index]
    if not record_reference then
      if missing_remote_count > 0 and #remote_errors == 0 then
        finish(nil, nil)
        return
      end
      local error_detail = #remote_errors > 0
          and table.concat(remote_errors, '; ')
        or 'no supported GitHub remote is configured'
      finish(
        nil,
        ('GitHub issue #%s unavailable from configured remotes: %s')
          :format(issue_number, error_detail)
      )
      return
    end
    local remote = record_reference.remote
    local resolved_issue_number = tostring(record_reference.number)
    track_process(fetch_remote_issue(remote, resolved_issue_number, function(
      issue,
      issue_error,
      issue_not_found,
      issue_unreachable
    )
      if cancelled or completed then
        return
      end
      if issue then
        finish(issue, nil)
        return
      end
      if issue_unreachable then
        -- Every remaining remote crosses the same dead network/proxy; stop here.
        finish(nil, issue_error)
        return
      end
      if issue_not_found then
        missing_remote_count = missing_remote_count + 1
        try_record(record_references, record_index + 1)
        return
      end
      remote_errors[#remote_errors + 1] = ('%s/%s: %s'):format(
        remote.owner,
        remote.repository,
        issue_error or 'unknown GitHub response'
      )
      try_record(record_references, record_index + 1)
    end))
  end

  track_process(reference.resolve_local(
    root,
    issue_number,
    function(record_references, resolution_error)
      if cancelled then
        return
      end
      if resolution_error then
        finish(nil, resolution_error)
        return
      end
      try_record(record_references or {}, 1)
    end
  ))
  return function()
    cancelled = true
    for _, cancel_process in ipairs(process_cancellations) do
      cancel_process()
    end
  end
end

return M
