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
vim.ui.open = function(target)
  opened_targets[#opened_targets + 1] = target
  return {
    wait = function()
      opener_waited = true
      return { code = 1 }
    end,
  }, nil
end

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
vim.ui.open = function()
  return nil, 'vim.ui.open: no handler found'
end
vim.notify = function(message, level)
  notification = { level = level, message = message }
end
assert(not open_target.open('https://example.com/missing'), 'Missing handler reported success')
assert(
  notification
    and notification.level == vim.log.levels.ERROR
    and notification.message == 'vim.ui.open: no handler found',
  'Synchronous URL opener error was not reported'
)

local original_confirm = vim.fn.confirm
local original_edit = vim.cmd.edit
local original_split = vim.cmd.split
local original_vsplit = vim.cmd.vsplit
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

local confirmation_message
local confirmation_choices
local confirmation_default
local selected_confirmation = 2
vim.fn.confirm = function(message, choices, default_choice)
  confirmation_message = message
  confirmation_choices = choices
  confirmation_default = default_choice
  return selected_confirmation
end

local invoked_commands = {}
local function record_command(command_name)
  return function(command_options)
    invoked_commands[#invoked_commands + 1] = {
      name = command_name,
      options = command_options,
    }
  end
end
vim.cmd.edit = record_command('edit')
vim.cmd.split = record_command('split')
vim.cmd.vsplit = record_command('vsplit')

vim.ui.open = function(target)
  opened_targets[#opened_targets + 1] = target
  return {
    wait = function()
      opener_waited = true
      return { code = 1 }
    end,
  }, nil
end
vim.api.nvim_win_set_cursor(0, { 1, 2 })
open_target.open_at_cursor()
assert(
  opened_targets[#opened_targets] == 'https://example.com/rendered' and not opener_waited,
  'Rendered Markdown label did not resolve to its URL destination'
)

vim.api.nvim_win_set_cursor(0, { 1, 58 })

assert(
  not open_target.open_at_cursor() and #invoked_commands == 0,
  'No did not cancel a local-file jump'
)
assert(
  confirmation_message:match("replaces this window's render")
    and confirmation_choices == '&Yes (current window)\n&No\n&Vertical split\n&Horizontal split'
    and confirmation_default == 2,
  'Local-file confirmation omitted its render warning or y/n/v/h choices'
)

notification = nil
for _, confirmation_case in ipairs({
  { choice = 1, command = 'edit' },
  { choice = 3, command = 'vsplit' },
  { choice = 4, command = 'split' },
}) do
  selected_confirmation = confirmation_case.choice
  assert(open_target.open('example.lua#L2'), 'Confirmed local-file jump failed')
  local invoked_command = invoked_commands[#invoked_commands]
  assert(
    invoked_command.name == confirmation_case.command
      and invoked_command.options.args[1] == expected_target_path,
    'Local-file confirmation dispatched the wrong window action or path'
  )
end
assert(
  not notification and vim.b[source_buffer].gx_lightweight_render ~= true,
  'Same-project split did not retain the ordinary FileType and LSP lifecycle'
)

notification = nil
vim.cmd.edit = original_edit
vim.cmd.split = original_split
vim.cmd.vsplit = original_vsplit
selected_confirmation = 1
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
selected_confirmation = 3
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
vim.api.nvim_win_close(0, true)
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
