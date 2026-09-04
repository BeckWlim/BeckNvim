local original_github = package.loaded['config.git.github']
local original_issue = package.loaded['config.git.issue']
local original_ui_open = vim.ui.open
local original_nvim_echo = vim.api.nvim_echo
local original_treesitter = package.loaded['config.syntax.treesitter']
local issue_requests = {}
local direct_record_requests = {}
local opened_urls = {}
local opener_waited = false
local cleared_loading_messages = 0
local highlighted_buffers = {}

package.loaded['config.syntax.treesitter'] = {
  ensure_highlighting = function(buffer)
    highlighted_buffers[#highlighted_buffers + 1] = buffer
  end,
}

vim.api.nvim_echo = function(chunks, history, options)
  if #chunks == 0 then
    cleared_loading_messages = cleared_loading_messages + 1
    return
  end
  return original_nvim_echo(chunks, history, options)
end

vim.ui.open = function(url)
  opened_urls[#opened_urls + 1] = url
  return {
    wait = function()
      opener_waited = true
      return { code = 1 }
    end,
  }, nil
end

package.loaded['config.git.github'] = {
  fetch_issue = function(root, issue_number, callback)
    issue_requests[#issue_requests + 1] = {
      callback = callback,
      issue_number = issue_number,
      root = root,
    }
    return function() end
  end,
  fetch_record = function(record_reference, callback)
    direct_record_requests[#direct_record_requests + 1] = {
      callback = callback,
      record_reference = record_reference,
    }
    return function() end
  end,
  parse_record_url = function(target)
    local resource_segment, issue_number = target:match(
      '^https://github%.com/moon%-hotel/Mooncake/(issues)/(%d+)'
    )
    if not resource_segment then
      resource_segment, issue_number = target:match(
        '^https://github%.com/moon%-hotel/Mooncake/(pull)/(%d+)'
      )
    end
    if not resource_segment then
      return nil
    end
    return {
      kind = resource_segment == 'pull' and 'Pull request' or 'Issue',
      number = tonumber(issue_number),
      remote = {
        host = 'github.com',
        owner = 'moon-hotel',
        repository = 'Mooncake',
      },
    }
  end,
}
package.loaded['config.git.issue'] = nil
local issue_view = require('config.git.issue')

local issue = {
  author = 'maintainer',
  body = 'Tracks the memory work in #123.',
  comments = 2,
  created_at = '2026-08-01T00:00:00Z',
  discussion = {
    {
      author = 'reviewer-one',
      body = 'First complete discussion reply.\n\nStill visible after the blank line.',
      created_at = '2026-08-02T01:00:00Z',
      html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452#issuecomment-1',
      updated_at = '2026-08-02T01:10:00Z',
    },
    {
      author = 'reviewer-two',
      body = 'Second complete discussion reply.',
      created_at = '2026-08-03T01:00:00Z',
      html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452#issuecomment-2',
      updated_at = '2026-08-03T01:00:00Z',
    },
  },
  discussion_complete = true,
  html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452',
  kind = 'Issue',
  labels = { 'performance' },
  number = 3452,
  remote_host = 'github.com',
  remote_repository = 'moon-hotel/Mooncake',
  state = 'open',
  title = 'Reduce RSS after eviction',
  updated_at = '2026-08-02T00:00:00Z',
}

local parent_tabpage = vim.api.nvim_get_current_tabpage()
local parent_windows = vim.api.nvim_tabpage_list_wins(parent_tabpage)
local parent_commit_entries = {
  { hash = 'newer', subject = 'Newer branch commit' },
  { hash = 'older', subject = 'Older branch commit' },
}
local preserved_commit_entries = vim.deepcopy(parent_commit_entries)
local result_reopens = 0
assert(issue_view.open_file('/work/repository', issue, {
  parent_tabpage = parent_tabpage,
  return_to_results = function()
    result_reopens = result_reopens + 1
  end,
}), 'Issue detail did not open')
local issue_buffer = vim.api.nvim_get_current_buf()
local rendered_issue_lines = vim.api.nvim_buf_get_lines(issue_buffer, 0, -1, false)
local rendered_issue_text = table.concat(rendered_issue_lines, '\n')
assert(
  vim.api.nvim_get_current_tabpage() == parent_tabpage
    and vim.api.nvim_win_get_config(0).relative == 'editor'
    and #vim.api.nvim_tabpage_list_wins(parent_tabpage) == #parent_windows + 1,
  'Issue detail did not open as one float above the preserved Git panel'
)
assert(
  vim.bo[issue_buffer].filetype == 'markdown'
    and rendered_issue_text:match('Tracks the memory work in #123')
    and rendered_issue_text:match('## Discussion')
    and rendered_issue_text:match('Still visible after the blank line')
    and rendered_issue_text:match('Second complete discussion reply'),
  'Issue detail lost its complete Markdown body or discussion'
)
assert(
  highlighted_buffers[1] == issue_buffer,
  'Issue detail did not synchronize Markdown parsing for pinned section titles'
)
local remote_card = ('Remote: [github.com/moon-hotel/Mooncake#3452](%s)'):format(
  issue.html_url
)
assert(
  rendered_issue_lines[4] == remote_card
    and not rendered_issue_text:match('%[Open on GitHub%]'),
  'Issue canonical GitHub link is not contained in the top metadata card'
)
local pull_request = vim.deepcopy(issue)
pull_request.kind = 'Pull request'
pull_request.html_url = 'https://github.com/moon-hotel/Mooncake/pull/3452'
local rendered_pull_request_text = table.concat(issue_view.lines(pull_request), '\n')
assert(
  rendered_pull_request_text:match('%*%*Pull request · OPEN · REMOTE%*%*')
    and rendered_pull_request_text:match('Mooncake/pull/3452')
    and rendered_pull_request_text:match('## Discussion')
    and rendered_pull_request_text:match('Second complete discussion reply'),
  'Pull request detail did not reuse the issue body and discussion render pipeline'
)
assert(
  vim.wo[0].foldenable
    and vim.wo[0].foldmethod == 'expr'
    and vim.wo[0].foldexpr == 'v:lua.vim.treesitter.foldexpr()'
    and vim.wo[0].foldlevel == 99,
  'Issue float did not enable open-by-default Tree-sitter Markdown section folds'
)
local discussion_row
for row_index, line in ipairs(rendered_issue_lines) do
  if line == '## Discussion' then
    discussion_row = row_index
    break
  end
end
assert(discussion_row, 'Issue detail lacks a foldable Markdown discussion section')
vim.api.nvim_win_set_cursor(0, { discussion_row, 0 })
vim.cmd('normal! zc')
assert(
  vim.fn.foldclosed(discussion_row) == discussion_row,
  'Issue detail could not close its Markdown discussion fold'
)
vim.cmd('normal! zo')
assert(
  vim.fn.foldclosed(discussion_row) == -1,
  'Issue detail could not reopen its Markdown discussion fold'
)
local tab_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<Tab>' or keymap.lhs == '\t'
  end
)
assert(
  tab_mapping and tab_mapping.desc == 'Ignore Tab in GitHub detail' and tab_mapping.rhs == '',
  'Issue float did not reject Tab locally'
)
local visual_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == 'v' or keymap.lhs == 'y'
  end
)
assert(not visual_mapping, 'Issue float shadowed basic visual selection or yank operations')
local scroll_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == 'j'
      or keymap.lhs == 'k'
      or keymap.lhs == '<C-D>'
      or keymap.lhs == '<C-U>'
  end
)
assert(not scroll_mapping, 'Issue float shadowed normal line or page scrolling')
local external_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == 'gx'
  end
)
assert(external_mapping and external_mapping.callback, 'Issue buffer lacks its owned gx mapping')
external_mapping.callback()
assert(
  #opened_urls == 1 and opened_urls[1] == issue.html_url and not opener_waited,
  'Issue gx duplicated its URL or waited on the detached WSL opener'
)

local related_row
local related_column
for row_index, line in ipairs(vim.api.nvim_buf_get_lines(issue_buffer, 0, -1, false)) do
  local match_start = line:find('#123', 1, true)
  if match_start then
    related_row = row_index
    related_column = match_start - 1
    break
  end
end
assert(related_row and related_column, 'Issue fixture lost its related issue reference')
vim.api.nvim_win_set_cursor(0, { related_row, related_column })
local enter_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(function(keymap)
  return keymap.lhs == '<CR>'
end)
assert(enter_mapping and enter_mapping.callback, 'Issue file lacks related-issue navigation')
enter_mapping.callback()
assert(
  #issue_requests == 1 and issue_requests[1].issue_number == '123',
  'Issue detail did not navigate the related GitHub reference'
)
local search_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(function(keymap)
  return keymap.desc == 'Return to Git search'
end)
assert(
  search_mapping
    and search_mapping.callback
    and (search_mapping.lhs == '<Space>de' or search_mapping.lhs == ' de'),
  'Issue detail did not move Git search return to Space-de'
)
local unexpected_panel_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<Space>dp' or keymap.lhs == ' dp'
  end
)
assert(not unexpected_panel_mapping, 'Issue detail incorrectly treats Space-dp as search return')
search_mapping.callback()
assert(vim.wait(100, function()
  return result_reopens == 1
end, 10), 'Issue-detail Space-de did not reopen the cached result picker')
assert(
  vim.api.nvim_get_current_tabpage() == parent_tabpage
    and vim.deep_equal(vim.api.nvim_tabpage_list_wins(parent_tabpage), parent_windows)
    and vim.deep_equal(parent_commit_entries, preserved_commit_entries),
  'Returning from issue detail did not preserve the parent Diffview split and commit list'
)

assert(issue_view.open_file('/work/repository', issue, {
  parent_tabpage = parent_tabpage,
}))
local second_issue_buffer = vim.api.nvim_get_current_buf()
local close_mapping = vim.iter(vim.api.nvim_buf_get_keymap(second_issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<C-Q>'
  end
)
assert(close_mapping and close_mapping.callback, 'Issue detail lacks direct parent return')
close_mapping.callback()
assert(
  vim.api.nvim_get_current_tabpage() == parent_tabpage
    and not issue_view.is_active(),
  'Issue-detail Ctrl-Q did not close only detail and preserve its parent surface'
)

local direct_pull_url = 'https://github.com/moon-hotel/Mooncake/pull/3452/files'
assert(issue_view.open_url(direct_pull_url), 'Direct pull-request URL was not accepted')
assert(
  #direct_record_requests == 1
    and direct_record_requests[1].record_reference.kind == 'Pull request'
    and not issue_view.is_active(),
  'Direct pull-request URL did not start one shared provider request before rendering'
)
local clears_before_pull_resolution = cleared_loading_messages
direct_record_requests[1].callback(pull_request, nil)
assert(vim.wait(100, function()
  return issue_view.is_active()
end, 10), 'Resolved direct pull request did not open the GitHub detail float')
assert(
  cleared_loading_messages == clears_before_pull_resolution + 1,
  'Successful direct pull-request rendering did not clear its loading message'
)
local direct_pull_buffer = vim.api.nvim_get_current_buf()
local direct_pull_text = table.concat(
  vim.api.nvim_buf_get_lines(direct_pull_buffer, 0, -1, false),
  '\n'
)
assert(
  vim.api.nvim_buf_get_name(direct_pull_buffer)
      == 'github://moon-hotel/Mooncake/pull/3452'
    and direct_pull_text:match('%*%*Pull request · OPEN · REMOTE%*%*')
    and direct_pull_text:match('Second complete discussion reply'),
  'Direct pull request did not reuse the issue detail buffer and discussion renderer'
)
assert(issue_view.close(), 'Direct pull-request detail did not close')

local direct_issue_url = 'https://github.com/moon-hotel/Mooncake/issues/999'
assert(issue_view.open_url(direct_issue_url), 'Direct issue URL was not accepted')
local clears_before_issue_fallback = cleared_loading_messages
direct_record_requests[2].callback(nil, 'network unavailable')
assert(
  opened_urls[#opened_urls] == direct_issue_url
    and not issue_view.is_active()
    and cleared_loading_messages == clears_before_issue_fallback + 1,
  'Failed direct issue rendering did not fall back to the external URL opener'
)

package.loaded['config.git.github'] = original_github
package.loaded['config.git.issue'] = original_issue
package.loaded['config.syntax.treesitter'] = original_treesitter
vim.ui.open = original_ui_open
vim.api.nvim_echo = original_nvim_echo
