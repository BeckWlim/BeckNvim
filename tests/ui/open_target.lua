-- Focused tests for config.ui.open_target.
local original_open_target = package.loaded['config.ui.open_target']
local original_get_urls = require('vim.ui')._get_urls
local original_get_clients = vim.lsp.get_clients
local original_notify = vim.notify
local original_ui_open = vim.ui.open
local original_issue = package.loaded['config.git.issue']

package.loaded['config.ui.open_target'] = nil
local open_target = require('config.ui.open_target')

local opened_targets = {}
local opener_waited = false
rawset(vim.ui, 'open', function(target)
  opened_targets[#opened_targets + 1] = target
  return {
    wait = function()
      opener_waited = true
      return { code = 1 }
    end,
  }, nil
end)

assert(open_target.open('https://example.com/report'), 'Detached URL handoff failed')
assert(
  #opened_targets == 1
    and opened_targets[1] == 'https://example.com/report'
    and not opener_waited,
  'URL opener waited on a detached browser handoff'
)

local rendered_github_targets = {}
package.loaded['config.git.issue'] = {
  open_url = function(target)
    if not target:match('/issues/%d+') and not target:match('/pull/%d+') then
      return false
    end
    rendered_github_targets[#rendered_github_targets + 1] = target
    return true
  end,
}
assert(
  open_target.open('https://github.com/example/project/pull/42/files')
    and rendered_github_targets[1] == 'https://github.com/example/project/pull/42/files'
    and #opened_targets == 1,
  'Direct GitHub pull-request URL did not prefer the shared detail renderer'
)
assert(
  open_target.open('https://github.com/example/project')
    and opened_targets[2] == 'https://github.com/example/project',
  'Non-record GitHub URL did not retain external browser handoff'
)

local inline_pull_request = table.concat({
  'The most direct match for foreground lookup latency is ',
  '[PR #2405](https://github.com/kvcache-ai/Mooncake/pull/2405): large requests',
})
local inline_parent_buffer = vim.api.nvim_get_current_buf()
local inline_buffer = vim.api.nvim_create_buf(true, true)
vim.api.nvim_set_current_buf(inline_buffer)
vim.bo[inline_buffer].filetype = 'text'
vim.api.nvim_buf_set_lines(inline_buffer, 0, -1, false, { inline_pull_request })
local inline_label_column = assert(inline_pull_request:find('#2405', 1, true)) - 1
vim.api.nvim_win_set_cursor(0, { 1, inline_label_column })
local opened_target_count = #opened_targets
open_target.open_at_cursor()
assert(
  rendered_github_targets[#rendered_github_targets]
      == 'https://github.com/kvcache-ai/Mooncake/pull/2405'
    and #opened_targets == opened_target_count,
  'Inline Markdown PR outside a Markdown buffer bypassed the GitHub detail renderer'
)
vim.api.nvim_set_current_buf(inline_parent_buffer)
vim.api.nvim_buf_delete(inline_buffer, { force = true })

require('vim.ui')._get_urls = function()
  return {
    'https://example.com/first',
    'https://example.com/first',
    'https://example.com/second',
  }
end
open_target.open_at_cursor()
assert(
  #opened_targets == 4
    and opened_targets[3] == 'https://example.com/first'
    and opened_targets[4] == 'https://example.com/second'
    and not opener_waited,
  'Cursor URL opening duplicated a target or waited on the browser'
)

local notification
rawset(vim.ui, 'open', function()
  return nil, 'vim.ui.open: no handler found'
end)
rawset(vim, 'notify', function(message, level)
  notification = { level = level, message = message }
end)
assert(not open_target.open('https://example.com/missing'), 'Missing handler reported success')
assert(
  notification
    and notification.level == vim.log.levels.ERROR
    and notification.message == 'vim.ui.open: no handler found',
  'Synchronous URL opener error was not reported'
)

local failing_record_url = 'https://github.com/example/project/pull/404'
package.loaded['config.git.issue'].open_url = function()
  error('provider exploded')
end
local opened_before_provider_failure = #opened_targets
notification = nil
rawset(vim.ui, 'open', function(target)
  opened_targets[#opened_targets + 1] = target
  return { wait = function() opener_waited = true end }, nil
end)
assert(open_target.open(failing_record_url), 'Provider failure lost the browser fallback')
assert(
  #opened_targets == opened_before_provider_failure + 1
    and opened_targets[#opened_targets] == failing_record_url
    and notification
    and notification.level == vim.log.levels.WARN
    and notification.message:match('GitHub detail opener failed')
    and notification.message:match('opening in external browser'),
  'Provider failure did not explain its external-browser fallback'
)

local original_confirm = vim.fn.confirm
local navigation = require('config.navigation')
local original_navigation_open = navigation.open
local original_buffer = vim.api.nvim_get_current_buf()
local source_buffer = vim.api.nvim_create_buf(true, false)
local source_path = vim.fs.joinpath(
  vim.fn.getcwd(),
  'tests/fixtures/symbol_project/example.md'
)
local expected_target_path = vim.fs.joinpath(
  vim.fn.getcwd(),
  'tests/fixtures/symbol_project/example.lua'
)
vim.api.nvim_buf_set_name(source_buffer, source_path)
vim.api.nvim_set_current_buf(source_buffer)
vim.bo[source_buffer].filetype = 'markdown'
vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, {
  '[browser report](https://example.com/rendered) and [source](example.lua#L2)',
})

rawset(vim.fn, 'confirm', function() error('Local gx still uses the strategy question') end)

local invoked_commands = {}
notification = nil
rawset(navigation, 'open', function(path, options)
  invoked_commands[#invoked_commands + 1] = { name = options.command, path = path, options = options }
  return { succeeded = true }
end)

rawset(vim.ui, 'open', function(target)
  opened_targets[#opened_targets + 1] = target
  return { wait = function() opener_waited = true end }, nil
end)
vim.api.nvim_win_set_cursor(0, { 1, 2 })
open_target.open_at_cursor()
assert(opened_targets[#opened_targets] == 'https://example.com/rendered' and not opener_waited,
  'Rendered Markdown label did not resolve to its URL destination')
vim.api.nvim_win_set_cursor(0, { 1, 58 })
open_target.open_at_cursor()
assert(#invoked_commands == 1, 'Cursor local-file navigation bypassed the shared manager')
assert(open_target.open('example.lua#L2'), 'Local-file navigation request failed')
local invoked_command = invoked_commands[#invoked_commands]
assert(invoked_command.name == 'edit' and invoked_command.path == expected_target_path
  and invoked_command.options.select_destination and invoked_command.options.line == 2
  and invoked_command.options.push_cursor,
  'Local gx did not request an existing destination pane and native location history')
assert(not notification and vim.b[source_buffer].gx_lightweight_render ~= true,
  'Same-project navigation lost the ordinary FileType and LSP lifecycle')

notification = nil
rawset(navigation, 'open', original_navigation_open)
vim.bo[source_buffer].modified = false
assert(open_target.open('example.lua#L2'), 'Real current-window file jump failed')
local target_buffer = vim.api.nvim_get_current_buf()
assert(
  vim.api.nvim_buf_get_name(target_buffer) == expected_target_path
    and vim.api.nvim_win_get_cursor(0)[1] == 2,
  'Current-window file jump did not open the resolved path at its Markdown line anchor'
)

local external_file_path = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ 'local external_value = 1', 'return external_value' }, external_file_path)
local filetype_events = 0
local filetype_group = vim.api.nvim_create_augroup('test-gx-lightweight-filetype', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = filetype_group,
  callback = function()
    filetype_events = filetype_events + 1
  end,
})
assert(open_target.open(external_file_path .. '#L2'), 'External-project file jump failed')
local external_buffer = vim.api.nvim_get_current_buf()
assert(
  vim.api.nvim_buf_get_name(external_buffer) == external_file_path
    and vim.api.nvim_win_get_cursor(0)[1] == 2
    and vim.bo[external_buffer].filetype == 'lua'
    and vim.b[external_buffer].gx_lightweight_render == true
    and filetype_events == 0,
  'External-project jump did not preserve lightweight syntax-only rendering'
)
assert(not notification, 'External-project lightweight rendering emitted a needless notification')
vim.api.nvim_buf_delete(external_buffer, { force = true })
vim.api.nvim_del_augroup_by_id(filetype_group)
vim.fn.delete(external_file_path)

vim.fn.confirm = original_confirm
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(source_buffer, { force = true })
vim.api.nvim_buf_delete(target_buffer, { force = true })
package.loaded['config.ui.open_target'] = original_open_target
package.loaded['config.git.issue'] = original_issue
require('vim.ui')._get_urls = original_get_urls
rawset(vim.lsp, 'get_clients', original_get_clients)
vim.notify = original_notify
vim.ui.open = original_ui_open
