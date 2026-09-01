local github = require('config.git.github')

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

local issue, issue_error = github.parse_issue(vim.json.encode({
  body = 'Related to #123',
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
    and issue.comments == 4,
  'GitHub issue response lost renderable metadata'
)
local invalid_issue, invalid_error = github.parse_issue('{broken')
assert(not invalid_issue and invalid_error, 'Invalid GitHub JSON did not return a concise error')

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
