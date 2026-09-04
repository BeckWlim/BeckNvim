local github = require('config.git.github')
local repository = require('config.git.repository')

local ssh_remote = github.parse_remote_url('git@github.com:moon-hotel/Mooncake.git')
assert(
  ssh_remote
    and ssh_remote.host == 'github.com'
    and ssh_remote.owner == 'moon-hotel'
    and ssh_remote.repository == 'Mooncake',
  'GitHub SSH origin was not resolved for issue lookup'
)
local enterprise_remote = github.parse_remote_url(
  'https://github.example.com/platform/service.git'
)
assert(
  enterprise_remote and enterprise_remote.host == 'github.example.com',
  'GitHub Enterprise HTTPS origin was not resolved'
)
assert(
  github.parse_remote_url('git@gitlab.com:platform/service.git') == nil,
  'Non-GitHub origin was accepted by the GitHub issue client'
)

local direct_issue_reference = github.parse_record_url(
  'https://github.com/moon-hotel/Mooncake/issues/3452#issuecomment-1'
)
local direct_pull_reference = github.parse_record_url(
  'https://github.com/moon-hotel/Mooncake/pull/77/files'
)
assert(
  direct_issue_reference
    and direct_issue_reference.kind == 'Issue'
    and direct_issue_reference.number == 3452
    and direct_issue_reference.remote.repository == 'Mooncake',
  'Direct GitHub issue URL did not resolve to a provider record'
)
assert(
  direct_pull_reference
    and direct_pull_reference.kind == 'Pull request'
    and direct_pull_reference.number == 77
    and direct_pull_reference.remote.owner == 'moon-hotel',
  'Direct GitHub pull-request URL did not resolve to the shared provider record'
)
assert(
  github.parse_record_url('https://github.com/moon-hotel/Mooncake/commit/77') == nil
    and github.parse_record_url('https://gitlab.com/moon-hotel/Mooncake/issues/77') == nil,
  'GitHub record URL parser accepted an unrelated resource or provider'
)

local remote_config_output = table.concat({
  'remote.upstream.url\ngit@github.com:kvcache-ai/Mooncake.git',
  'remote.internal.url\nssh://git@code.example.com/team/Mooncake.git',
  'remote.origin.url\ngit@github.com:BeckWlim/Mooncake.git',
  'remote.mirror.url\nhttps://github.com/kvcache-ai/Mooncake.git',
}, '\0') .. '\0'
local remote_candidates = github.parse_remote_candidates(remote_config_output)
assert(
  #remote_candidates == 2
    and remote_candidates[1].name == 'origin'
    and remote_candidates[1].owner == 'BeckWlim'
    and remote_candidates[2].name == 'upstream'
    and remote_candidates[2].owner == 'kvcache-ai',
  'GitHub remote discovery did not prioritize origin then upstream or deduplicate mirrors'
)
assert(
  vim.deep_equal(repository.commands.remote_urls(), {
    'git',
    'config',
    '--null',
    '--get-regexp',
    '^remote\\..*\\.url$',
  }),
  'GitHub remote discovery command lost its machine-readable Git config boundary'
)

local issue, issue_error = github.parse_issue(vim.json.encode({
  body = 'Related to #123\r\n\r\nSecond paragraph.',
  comments = 4,
  created_at = '2026-08-01T00:00:00Z',
  html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452',
  labels = { { name = 'performance' }, { name = 'store' } },
  number = 3452,
  state = 'open',
  title = 'Reduce RSS after eviction',
  updated_at = '2026-08-02T00:00:00Z',
  user = { login = 'maintainer' },
}))
assert(not issue_error and issue, 'Valid GitHub issue response was rejected')
assert(
  issue.kind == 'Issue'
    and issue.author == 'maintainer'
    and issue.labels[1] == 'performance'
    and issue.comments == 4
    and issue.body == 'Related to #123\n\nSecond paragraph.'
    and not issue.body:find('\r', 1, true),
  'GitHub issue response lost renderable metadata'
)
local invalid_issue, invalid_error = github.parse_issue('{broken')
assert(not invalid_issue and invalid_error, 'Invalid GitHub JSON did not return a concise error')

local discussion_response = vim.json.encode({
  {
    body = 'First complete reply.\r\n\r\nWith a second paragraph.',
    created_at = '2026-08-02T01:00:00Z',
    html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452#issuecomment-1',
    updated_at = '2026-08-02T01:10:00Z',
    user = { login = 'reviewer-one' },
  },
  {
    body = 'Second complete reply.',
    created_at = '2026-08-03T01:00:00Z',
    html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452#issuecomment-2',
    updated_at = '2026-08-03T01:00:00Z',
    user = { login = 'reviewer-two' },
  },
})
local discussion, discussion_error = github.parse_comments(discussion_response)
assert(not discussion_error and discussion, 'Valid GitHub discussion response was rejected')
assert(
  #discussion == 2
    and discussion[1].author == 'reviewer-one'
    and discussion[1].body:match('second paragraph')
    and not discussion[1].body:find('\r', 1, true)
    and discussion[2].html_url:match('issuecomment%-2$'),
  'GitHub discussion parsing lost complete comment content or metadata'
)

local html_issue, html_issue_error = github.parse_issue_html(table.concat({
  '<html><head>',
  '<meta property="og:title" content="Memory leak &amp; restart · Issue #3452 · kvcache-ai/Mooncake">',
  '<meta property="og:description" content="Remote issue body">',
  '</head></html>',
}), ssh_remote, '3452')
assert(not html_issue_error and html_issue, 'GitHub public-page issue metadata was rejected')
assert(
  html_issue.title == 'Memory leak & restart'
    and html_issue.body == 'Remote issue body'
    and html_issue.html_url == 'https://github.com/moon-hotel/Mooncake/issues/3452',
  'GitHub public-page fallback lost the origin-derived issue metadata'
)

local complete_body = table.concat({
  '### Environment',
  '',
  'H100, RDMA enabled',
  '',
  '### Observed Phenomenon',
  '',
  'Memory keeps growing after eviction.',
  '',
  '- [x] Reproduction included',
}, '\n')
local crlf_body = complete_body:gsub('\n', '\r\n')
local embedded_document = vim.json.encode({
  payload = {
    preloadedQueries = {
      {
        result = {
          data = {
            repository = {
              issue = {
                __typename = 'Issue',
                author = { login = 'Lichunyan3' },
                body = crlf_body,
                createdAt = '2026-08-30T01:00:00Z',
                labels = { edges = { { node = { name = 'bug' } } } },
                number = 3452,
                state = 'CLOSED',
                title = 'Memory leak after eviction',
                updatedAt = '2026-09-02T02:00:00Z',
              },
            },
          },
        },
      },
    },
  },
})
local structured_document = vim.json.encode({
  ['@type'] = 'DiscussionForumPosting',
  articleBody = crlf_body,
  author = { name = 'Lichunyan3' },
  datePublished = '2026-08-30T01:00:00Z',
  headline = 'Memory leak after eviction',
  interactionStatistic = { userInteractionCount = 2 },
})
local structured_html_response = table.concat({
  '<html><head>',
  '<script type="application/ld+json">{"@type":"WebSite"}</script>',
  '<script type="application/ld+json">',
  structured_document,
  '</script>',
  '<script type="application/json" data-target="react-app.embeddedData">',
  embedded_document,
  '</script>',
  '<meta property="og:description" content="Truncated fallback…">',
  '</head></html>',
}, '\n')
local structured_html_issue, structured_html_error = github.parse_issue_html(
  structured_html_response,
  ssh_remote,
  '3452'
)
assert(not structured_html_error and structured_html_issue, 'Structured GitHub HTML was rejected')
assert(
  structured_html_issue.body == complete_body
    and structured_html_issue.author == 'Lichunyan3'
    and structured_html_issue.state == 'closed'
    and structured_html_issue.labels[1] == 'bug'
    and structured_html_issue.created_at == '2026-08-30T01:00:00Z'
    and structured_html_issue.updated_at == '2026-09-02T02:00:00Z'
    and structured_html_issue.comments == 2,
  'Structured GitHub HTML did not preserve the complete body and key metadata'
)

local pull_request_document = vim.json.encode({
  payload = {
    preloadedQueries = {
      {
        result = {
          data = {
            repository = {
              pullRequest = {
                __typename = 'PullRequest',
                author = { login = 'contributor' },
                body = 'Complete pull request body.',
                createdAt = '2026-08-30T01:00:00Z',
                labels = { edges = {} },
                number = 77,
                state = 'OPEN',
                title = 'Improve eviction',
                updatedAt = '2026-09-02T02:00:00Z',
              },
            },
          },
        },
      },
    },
  },
})
local pull_request_html = table.concat({
  '<html><head>',
  '<script type="application/json" data-target="react-app.embeddedData">',
  pull_request_document,
  '</script>',
  '</head></html>',
}, '\n')
local pull_request, pull_request_error = github.parse_issue_html(
  pull_request_html,
  ssh_remote,
  '77'
)
assert(not pull_request_error and pull_request, 'Structured GitHub pull request was rejected')
assert(
  pull_request.kind == 'Pull request'
    and pull_request.body == 'Complete pull request body.'
    and pull_request.html_url == 'https://github.com/moon-hotel/Mooncake/pull/77',
  'Pull request HTML did not reuse issue parsing with its canonical pull URL'
)

local modern_pull_request_document = vim.json.encode({
  props = {
    initialPayload = {
      nested = {
        record = {
          author = { login = 'Icedcoco' },
          body = complete_body,
          comments = { totalCount = 3 },
          createdAt = '2026-08-13T01:00:00Z',
          labels = { nodes = { { name = 'Store' }, { name = 'run-ci' } } },
          mergedAt = '2026-08-27T07:23:00Z',
          number = 3422,
          state = 'CLOSED',
          title = '[Bugfix][Store] Handle BatchEvict OpLog failures',
          updatedAt = '2026-08-27T07:23:00Z',
        },
      },
    },
  },
})
local modern_pull_request, modern_pull_request_error, modern_metadata_source = github.parse_issue_html(table.concat({
  '<html><head>',
  '<script type="application/json" data-target="react-partial.embeddedData">',
  modern_pull_request_document,
  '</script>',
  '<meta property="og:title" content="[Bugfix][Store] Handle BatchEvict OpLog failures by Icedcoco · Pull Request #3422 · kvcache-ai/Mooncake">',
  '<meta property="og:description" content="Description Part of #3139…">',
  '</head></html>',
}, '\n'), ssh_remote, '3422', 'Pull request')
assert(not modern_pull_request_error and modern_pull_request, 'Modern GitHub PR payload was rejected')
assert(
  modern_pull_request.title == '[Bugfix][Store] Handle BatchEvict OpLog failures'
    and modern_metadata_source == 'embedded'
    and modern_pull_request.author == 'Icedcoco'
    and modern_pull_request.body == complete_body
    and modern_pull_request.state == 'merged'
    and modern_pull_request.labels[1] == 'Store'
    and modern_pull_request.created_at == '2026-08-13T01:00:00Z'
    and modern_pull_request.comments == 3,
  'Modern GitHub PR payload fell back to truncated Open Graph metadata'
)
local open_graph_pull_request = github.parse_issue_html(table.concat({
  '<html><head>',
  '<meta property="og:title" content="[Bugfix][Store] Handle BatchEvict OpLog failures by Icedcoco · Pull Request #3422 · kvcache-ai/Mooncake">',
  '<meta property="og:description" content="Truncated description…">',
  '</head></html>',
}), ssh_remote, '3422', 'Pull request')
assert(
  open_graph_pull_request
    and open_graph_pull_request.title == '[Bugfix][Store] Handle BatchEvict OpLog failures',
  'Pull-request Open Graph fallback retained GitHub\'s author byline in the title'
)

local original_repository_start = repository.start
local original_system = vim.system
local original_executable = vim.fn.executable
local original_gh_token = vim.env.GH_TOKEN
local original_github_token = vim.env.GITHUB_TOKEN
local requested_urls = {}
local requested_commands = {}
local fallback_result = {}

vim.env.GH_TOKEN = nil
vim.env.GITHUB_TOKEN = nil

vim.fn.executable = function(executable_name)
  if executable_name == 'gh' then
    return 0
  end
  return original_executable(executable_name)
end

repository.start = function(command, root, callback)
  assert(
    vim.deep_equal(command, repository.commands.remote_urls())
      and root == '/work/Mooncake',
    'Issue fallback did not query configured repository remotes'
  )
  callback({ code = 0, stderr = '', stdout = remote_config_output })
  return function() end
end

vim.system = function(command, _, callback)
  local request_url = command[#command]
  requested_urls[#requested_urls + 1] = request_url
  requested_commands[#requested_commands + 1] = command
  local upstream_web_url = 'https://github.com/kvcache-ai/Mooncake/issues/3452'
  local upstream_comments_url = 'https://api.github.com/repos/kvcache-ai/Mooncake/issues/3452/comments?per_page=100'
  local completed_process = request_url == upstream_web_url
      and {
        code = 0,
        stderr = '',
        stdout = structured_html_response,
      }
    or request_url == upstream_comments_url
        and { code = 0, stderr = '', stdout = discussion_response }
    or { code = 22, stderr = 'not found', stdout = '' }
  callback(completed_process)
  return { kill = function() end }
end

github.fetch_issue('/work/Mooncake', '3452', function(resolved_issue, issue_fetch_error)
  fallback_result.issue = resolved_issue
  fallback_result.error = issue_fetch_error
  fallback_result.complete = true
end)
assert(vim.wait(200, function()
  return fallback_result.complete == true
end, 10), 'GitHub issue fallback did not complete')
assert(
  not fallback_result.error
    and fallback_result.issue
    and fallback_result.issue.remote_repository == 'kvcache-ai/Mooncake'
    and fallback_result.issue.html_url == 'https://github.com/kvcache-ai/Mooncake/issues/3452'
    and fallback_result.issue.discussion_complete
    and #fallback_result.issue.discussion == 2
    and vim.deep_equal(requested_urls, {
      'https://api.github.com/repos/BeckWlim/Mooncake/issues/3452',
      'https://github.com/BeckWlim/Mooncake/issues/3452',
      'https://api.github.com/repos/kvcache-ai/Mooncake/issues/3452',
      'https://github.com/kvcache-ai/Mooncake/issues/3452',
      'https://api.github.com/repos/kvcache-ai/Mooncake/issues/3452/comments?per_page=100',
    }),
  'Issue lookup did not try REST before public-page fallback and upstream discussion enrichment'
)
for _, requested_command in ipairs(requested_commands) do
  if requested_command[#requested_command]:match('^https://github%.com/') then
    assert(
      vim.list_contains(requested_command, '--connect-timeout')
        and not vim.list_contains(requested_command, '--retry')
        and not vim.list_contains(requested_command, '--retry-connrefused'),
      'Public GitHub lookup lost its bounded single-attempt abort policy'
    )
  end
end

local missing_result = {}
vim.system = function(_, _, callback)
  callback({
    code = 22,
    stderr = 'curl: (22) The requested URL returned error: 404',
    stdout = '',
  })
  return { kill = function() end }
end
github.fetch_issue('/work/Mooncake', '5432', function(resolved_issue, issue_fetch_error)
  missing_result.issue = resolved_issue
  missing_result.error = issue_fetch_error
  missing_result.complete = true
end)
assert(vim.wait(200, function()
  return missing_result.complete == true
end, 10), 'Missing GitHub issue lookup did not complete')
assert(
  missing_result.issue == nil and missing_result.error == nil,
  'Confirmed GitHub 404 was reported as a transport failure instead of an absent issue'
)

repository.start = original_repository_start
vim.system = original_system
vim.fn.executable = original_executable
vim.env.GH_TOKEN = original_gh_token
vim.env.GITHUB_TOKEN = original_github_token

local cli_repository_start = repository.start
local cli_system = vim.system
local cli_executable = vim.fn.executable
local cli_commands = {}
local cli_result = {}

repository.start = function(_, _, callback)
  callback({
    code = 0,
    stderr = '',
    stdout = 'remote.origin.url\ngit@github.com:kvcache-ai/Mooncake.git\0',
  })
  return function() end
end
vim.fn.executable = function(executable_name)
  if executable_name == 'gh' then
    return 1
  end
  return cli_executable(executable_name)
end
vim.system = function(command, _, callback)
  cli_commands[#cli_commands + 1] = command
  local endpoint = command[#command]
  local response_body = endpoint:match('/comments%?per_page=100$')
      and discussion_response
    or vim.json.encode({
      body = complete_body,
      comments = 2,
      created_at = '2026-08-30T01:00:00Z',
      html_url = 'https://github.com/kvcache-ai/Mooncake/issues/3452',
      labels = { { name = 'bug' } },
      number = 3452,
      state = 'closed',
      title = 'Memory leak after eviction',
      updated_at = '2026-09-02T02:00:00Z',
      user = { login = 'Lichunyan3' },
    })
  callback({
    code = 0,
    stderr = '',
    stdout = response_body,
  })
  return { kill = function() end }
end

github.fetch_issue('/work/Mooncake', '3452', function(resolved_issue, issue_fetch_error)
  cli_result.issue = resolved_issue
  cli_result.error = issue_fetch_error
  cli_result.complete = true
end)
assert(vim.wait(200, function()
  return cli_result.complete == true
end, 10), 'Authenticated GitHub CLI issue lookup did not complete')
assert(
  not cli_result.error
    and cli_result.issue
    and cli_result.issue.discussion_complete
    and #cli_result.issue.discussion == 2
    and #cli_commands == 2
    and vim.deep_equal(cli_commands[1], {
      'gh',
      'api',
      '--method',
      'GET',
      'repos/kvcache-ai/Mooncake/issues/3452',
    })
    and vim.deep_equal(cli_commands[2], {
      'gh',
      'api',
      '--method',
      'GET',
      'repos/kvcache-ai/Mooncake/issues/3452/comments?per_page=100',
    }),
  'Issue and discussion lookup did not reuse the authenticated GitHub CLI'
)

repository.start = cli_repository_start
vim.system = cli_system
vim.fn.executable = cli_executable

local direct_system = vim.system
local direct_executable = vim.fn.executable
local direct_gh_token = vim.env.GH_TOKEN
local direct_github_token = vim.env.GITHUB_TOKEN
local direct_requested_url
local direct_result = {}
vim.env.GH_TOKEN = nil
vim.env.GITHUB_TOKEN = nil
vim.fn.executable = function(executable_name)
  if executable_name == 'gh' then
    return 0
  end
  return direct_executable(executable_name)
end
vim.system = function(command, _, callback)
  direct_requested_url = command[#command]
  callback({
    code = 0,
    stderr = '',
    stdout = vim.json.encode({
      body = complete_body,
      comments = 0,
      created_at = '2026-08-13T01:00:00Z',
      html_url = 'https://github.com/moon-hotel/Mooncake/pull/77',
      labels = { { name = 'Store' } },
      merged_at = '2026-08-27T07:23:00Z',
      number = 77,
      state = 'closed',
      title = 'Improve eviction',
      updated_at = '2026-08-27T07:23:00Z',
      user = { login = 'contributor' },
    }),
  })
  return { kill = function() end }
end
github.fetch_record(direct_pull_reference, function(resolved_record, record_error)
  direct_result.record = resolved_record
  direct_result.error = record_error
  direct_result.complete = true
end)
assert(vim.wait(200, function()
  return direct_result.complete == true
end, 10), 'Direct pull-request lookup did not complete')
assert(
  not direct_result.error
    and direct_result.record
    and direct_result.record.kind == 'Pull request'
    and direct_result.record.state == 'merged'
    and direct_result.record.author == 'contributor'
    and direct_result.record.body == complete_body
    and direct_result.record.html_url == 'https://github.com/moon-hotel/Mooncake/pull/77'
    and direct_requested_url == 'https://api.github.com/repos/moon-hotel/Mooncake/pulls/77',
  'Direct pull-request lookup did not use the complete PR endpoint and shared issue parser'
)

local incomplete_result = {}
local incomplete_requested_urls = {}
vim.system = function(command, _, callback)
  local request_url = command[#command]
  incomplete_requested_urls[#incomplete_requested_urls + 1] = request_url
  local completed_process = request_url:match('^https://api%.github%.com/')
      and {
        code = 22,
        stderr = 'curl: (22) HTTP 403',
        stdout = '{"message":"API rate limit exceeded"}',
      }
    or {
      code = 0,
      stderr = '',
      stdout = table.concat({
        '<html><head>',
        '<meta property="og:title" content="Improve eviction by contributor · Pull Request #77 · moon-hotel/Mooncake">',
        '<meta property="og:description" content="Truncated description…">',
        '</head></html>',
      }),
    }
  callback(completed_process)
  return { kill = function() end }
end
github.fetch_record(direct_pull_reference, function(resolved_record, record_error)
  incomplete_result.record = resolved_record
  incomplete_result.error = record_error
  incomplete_result.complete = true
end)
assert(vim.wait(200, function()
  return incomplete_result.complete == true
end, 10), 'Incomplete direct pull-request fallback did not complete')
assert(
  not incomplete_result.record
    and incomplete_result.error:match('truncated preview metadata')
    and vim.deep_equal(incomplete_requested_urls, {
      'https://api.github.com/repos/moon-hotel/Mooncake/pulls/77',
      'https://github.com/moon-hotel/Mooncake/pull/77',
    }),
  'Direct pull-request lookup rendered misleading Open Graph preview metadata'
)
vim.system = direct_system
vim.fn.executable = direct_executable
vim.env.GH_TOKEN = direct_gh_token
vim.env.GITHUB_TOKEN = direct_github_token

assert(
  github.is_unreachable_process_error({
    code = 7,
    stderr = 'curl: (7) Failed to connect to 172.18.0.1 port 7890: Connection refused',
  })
    and github.is_unreachable_process_error({
      code = 28,
      stderr = 'curl: (28) Connection timed out after 5000 milliseconds',
    })
    and github.is_unreachable_process_error({
      code = 6,
      stderr = 'curl: (6) Could not resolve host: api.github.com',
    })
    and github.is_unreachable_process_error({
      code = 1,
      stderr = 'dial tcp 172.18.0.1:7890: connect: connection refused',
    })
    and github.is_unreachable_process_error({
      code = -2,
      stderr = 'github request watchdog timeout',
    }),
  'Network-class GitHub failures were not classified as unreachable'
)
assert(
  not github.is_unreachable_process_error({
    code = 22,
    stderr = 'curl: (22) The requested URL returned error: 404',
  })
    and not github.is_unreachable_process_error({
      code = 22,
      stderr = 'curl: (22) HTTP 403',
      stdout = '{"message":"API rate limit exceeded"}',
    })
    and not github.is_unreachable_process_error({ code = 0, stderr = '' })
    and not github.is_unreachable_process_error(nil),
  'HTTP-level GitHub failures were misclassified as unreachable'
)

local gate_repository_start = repository.start
local gate_system = vim.system
local gate_executable = vim.fn.executable
local gate_gh_token = vim.env.GH_TOKEN
vim.env.GH_TOKEN = nil
vim.fn.executable = function(executable_name)
  if executable_name == 'gh' then
    return 0
  end
  return gate_executable(executable_name)
end

local unreachable_curl_urls = {}
local unreachable_curl_result = {}
vim.system = function(command, _, callback)
  unreachable_curl_urls[#unreachable_curl_urls + 1] = command[#command]
  callback({
    code = 7,
    stderr = 'curl: (7) Failed to connect to 172.18.0.1 port 7890: Connection refused',
    stdout = '',
  })
  return { kill = function() end }
end
github.fetch_record(direct_pull_reference, function(resolved_record, record_error)
  unreachable_curl_result.record = resolved_record
  unreachable_curl_result.error = record_error
  unreachable_curl_result.complete = true
end)
assert(vim.wait(200, function()
  return unreachable_curl_result.complete == true
end, 10), 'Unreachable direct lookup did not complete')
assert(
  not unreachable_curl_result.record
    and unreachable_curl_result.error
    and unreachable_curl_result.error:match('unreachable')
    and vim.deep_equal(unreachable_curl_urls, {
      'https://api.github.com/repos/moon-hotel/Mooncake/pulls/77',
    }),
  'Unreachable remote did not abort before the public-page fallback'
)

local unreachable_loop_urls = {}
local unreachable_loop_result = {}
repository.start = function(_, _, callback)
  callback({
    code = 0,
    stderr = '',
    stdout = 'remote.origin.url\ngit@github.com:BeckWlim/Mooncake.git\0'
      .. 'remote.upstream.url\ngit@github.com:kvcache-ai/Mooncake.git\0',
  })
  return function() end
end
vim.system = function(command, _, callback)
  unreachable_loop_urls[#unreachable_loop_urls + 1] = command[#command]
  callback({
    code = 7,
    stderr = 'curl: (7) Failed to connect to 172.18.0.1 port 7890: Connection refused',
    stdout = '',
  })
  return { kill = function() end }
end
github.fetch_issue('/work/Mooncake', '3452', function(resolved_issue, issue_fetch_error)
  unreachable_loop_result.issue = resolved_issue
  unreachable_loop_result.error = issue_fetch_error
  unreachable_loop_result.complete = true
end)
assert(vim.wait(200, function()
  return unreachable_loop_result.complete == true
end, 10), 'Unreachable issue lookup did not complete')
assert(
  not unreachable_loop_result.issue
    and unreachable_loop_result.error
    and unreachable_loop_result.error:match('unreachable')
    and #unreachable_loop_urls == 1,
  'Unreachable remote did not abort the remaining configured remotes'
)

local unreachable_cli_commands = {}
local unreachable_cli_result = {}
vim.fn.executable = function(executable_name)
  if executable_name == 'gh' then
    return 1
  end
  return gate_executable(executable_name)
end
vim.system = function(command, _, callback)
  unreachable_cli_commands[#unreachable_cli_commands + 1] = command
  callback({
    code = 1,
    stderr = 'dial tcp 172.18.0.1:7890: connect: connection refused',
    stdout = '',
  })
  return { kill = function() end }
end
github.fetch_record(direct_pull_reference, function(resolved_record, record_error)
  unreachable_cli_result.record = resolved_record
  unreachable_cli_result.error = record_error
  unreachable_cli_result.complete = true
end)
assert(vim.wait(200, function()
  return unreachable_cli_result.complete == true
end, 10), 'Unreachable GitHub CLI lookup did not complete')
assert(
  not unreachable_cli_result.record
    and unreachable_cli_result.error
    and unreachable_cli_result.error:match('unreachable')
    and #unreachable_cli_commands == 1
    and unreachable_cli_commands[1][1] == 'gh',
  'Unreachable GitHub CLI result did not abort before the curl fallback'
)

local original_new_timer = vim.uv.new_timer
local watchdog_fire
local watchdog_process_killed = false
local watchdog_completion
local watchdog_result = {}
vim.uv.new_timer = function()
  return {
    close = function() end,
    is_closing = function()
      return false
    end,
    start = function(_, _, _, fire_callback)
      watchdog_fire = fire_callback
    end,
    stop = function() end,
  }
end
vim.system = function(_, _, callback)
  watchdog_completion = callback
  return {
    kill = function()
      watchdog_process_killed = true
    end,
  }
end
github.fetch_record(direct_pull_reference, function(resolved_record, record_error)
  watchdog_result.record = resolved_record
  watchdog_result.error = record_error
  watchdog_result.complete = true
end)
assert(
  type(watchdog_fire) == 'function' and type(watchdog_completion) == 'function',
  'GitHub CLI request did not arm its watchdog timer'
)
watchdog_fire()
assert(vim.wait(200, function()
  return watchdog_result.complete == true
end, 10), 'Watchdog timeout did not complete the GitHub CLI lookup')
assert(
  watchdog_process_killed
    and not watchdog_result.record
    and watchdog_result.error
    and watchdog_result.error:match('unreachable'),
  'Watchdog timeout did not kill the parked GitHub CLI request and abort'
)
watchdog_completion({
  code = 0,
  stderr = '',
  stdout = vim.json.encode({ number = 77, title = 'Late response' }),
})
vim.wait(50)
assert(
  not watchdog_result.record,
  'A late GitHub CLI completion overwrote the watchdog timeout result'
)

repository.start = gate_repository_start
vim.system = gate_system
vim.fn.executable = gate_executable
vim.env.GH_TOKEN = gate_gh_token
vim.uv.new_timer = original_new_timer
