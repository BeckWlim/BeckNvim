local original_github = package.loaded['config.git.github']
local original_issue = package.loaded['config.git.issue']
local issue_requests = {}

package.loaded['config.git.github'] = {
  fetch_issue = function(root, issue_number, callback)
    issue_requests[#issue_requests + 1] = {
      callback = callback,
      issue_number = issue_number,
      root = root,
    }
    return function() end
  end,
}
package.loaded['config.git.issue'] = nil
local issue_view = require('config.git.issue')

local issue = {
  author = 'maintainer',
  body = 'Tracks the memory work in #123.',
  comments = 2,
  created_at = '2026-08-01T00:00:00Z',
  html_url = 'https://github.com/moon-hotel/Mooncake/issues/3452',
  kind = 'Issue',
  labels = { 'performance' },
  number = 3452,
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
assert(
  vim.api.nvim_get_current_tabpage() == parent_tabpage
    and vim.api.nvim_win_get_config(0).relative == 'editor'
    and #vim.api.nvim_tabpage_list_wins(parent_tabpage) == #parent_windows + 1,
  'Issue detail did not open as one float above the preserved Git panel'
)
assert(
  vim.bo[issue_buffer].filetype == 'markdown'
    and table.concat(vim.api.nvim_buf_get_lines(issue_buffer, 0, -1, false), '\n')
      :match('Tracks the memory work in #123'),
  'Issue detail lost its Markdown content'
)
local visual_mapping = vim.iter(vim.api.nvim_buf_get_keymap(issue_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == 'v' or keymap.lhs == 'y'
  end
)
assert(not visual_mapping, 'Issue float shadowed basic visual selection or yank operations')

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
assert(close_mapping and close_mapping.callback, 'Issue detail lacks direct branch return')
close_mapping.callback()
assert(
  vim.api.nvim_get_current_tabpage() == parent_tabpage
    and not issue_view.is_active(),
  'Issue-detail Ctrl-Q did not close only search and preserve branch history'
)

package.loaded['config.git.github'] = original_github
package.loaded['config.git.issue'] = original_issue
