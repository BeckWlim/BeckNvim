-- Serialized hook calls, deferred palette reads, and terminal-owner lifecycle.
local original = {
  system = vim.system, list_uis = vim.api.nvim_list_uis, notify = vim.notify,
  chan_info = vim.api.nvim_get_chan_info,
  server = vim.env.TMUX, pane = vim.env.TMUX_PANE, enabled = vim.g.beck_tmux_theme,
}
local hook_path = vim.fn.tempname() .. ' palette hook'
vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, hook_path)
vim.fn.setfperm(hook_path, 'rwx------')
local calls, warnings = {}, {}
local attached = false
local spawn_failure = false
local auto_finish = false
local function fake_system(command, options, callback)
  if spawn_failure then error('fixture spawn failure') end
  calls[#calls + 1] = { command = command, options = options, callback = callback }
  if auto_finish then callback({ code = 0, stderr = '' }) end
  return { kill = function() error('Must not interrupt a mutating hook') end }
end
local function capture_notification(message) warnings[#warnings + 1] = message end
vim.system = fake_system
vim.api.nvim_list_uis = function() return attached and { { chan = 1, width = 80, height = 24 } } or {} end
vim.api.nvim_get_chan_info = function(_channel)
  return { client = { name = 'nvim-tui', attributes = { pid = 4242 } } }
end
vim.notify = capture_notification
local function settle() vim.wait(20, function() return false end, 1) end
local function event(name)
  vim.api.nvim_exec_autocmds(name, { group = 'beck_tmux_theme' })
  settle()
end
local function complete(index, code)
  calls[index].callback({ code = code or 0, stderr = '' })
  settle()
end
local function contains(index, argument)
  return vim.tbl_contains(calls[index].command, argument)
end
package.loaded['config.ui.tmux'] = nil
local adapter = require('config.ui.tmux')
vim.g.beck_tmux_theme = false
adapter.setup({ hook = hook_path })
assert(vim.fn.exists('#beck_tmux_theme') == 0, 'Opt-out installed tmux listeners')
vim.g.beck_tmux_theme = nil
vim.env.TMUX, vim.env.TMUX_PANE = nil, nil
adapter.setup({ hook = hook_path })
assert(vim.fn.exists('#beck_tmux_theme') == 0, 'Missing tmux context installed listeners')
vim.env.TMUX, vim.env.TMUX_PANE = '/tmp/fixture.sock,123,0', '%7'
adapter.setup({ hook = hook_path .. '.missing' })
assert(vim.fn.exists('#beck_tmux_theme') == 0, 'Missing hook installed listeners')
adapter.setup({ hook = hook_path })
settle()
assert(#calls == 0, 'Headless startup published a palette')
attached = true
event('UIEnter')
assert(#calls == 1 and contains(1, '--owner') and contains(1, '4242'),
  'UI startup did not publish with the terminal UI owner PID')
assert(calls[1].command[1] == hook_path and calls[1].options.timeout == 1000,
  'Hook argv/path or timeout changed')
assert(calls[1].options.env.TMUX_PANE == '%7', 'Pane target was not captured')
assert(#calls[1].command == 15, 'Not all eleven palette roles were published')
-- Palette switches coalesce while the previous publication is running. The
-- deferred read sees the final highlights, including custom-preset rollback.
vim.api.nvim_set_hl(0, 'Normal', { bg = 0x123456, fg = 0xFFFFFF })
event('ColorScheme')
vim.api.nvim_set_hl(0, 'Normal', { bg = 0xFAFAF7, fg = 0x242424 })
event('ColorScheme')
assert(#calls == 1, 'Hook publications ran concurrently')
complete(1)
assert(#calls == 2 and contains(2, 'bg=#fafaf7') and contains(2, 'fg=#242424'),
  'Queued update used an older palette')
event('VimSuspend')
event('ColorScheme')
complete(2)
assert(#calls == 3 and calls[3].command[2] == 'reset', 'Suspend lost its ordered reset')
complete(3)
event('VimResume')
assert(#calls == 4 and calls[4].command[2] == 'set', 'Resume did not republish')
complete(4)
event('ShellCmdPost')
assert(#calls == 5, 'Returning from a shell did not reclaim the palette')
-- Failures remain silent, release the queue, and allow later events to retry.
event('ColorScheme')
complete(5, 124)
assert(#warnings == 0 and #calls == 6, 'Stale completion warned or stalled the queue')
complete(6, 124)
assert(#warnings == 0, 'External timeout affected the editor')
spawn_failure = true
event('ColorScheme')
assert(#warnings == 0, 'External spawn failure affected the editor')
spawn_failure = false
event('ColorScheme')
complete(7)
local palette = require('config.ui.palette')
local original_resolve = palette.resolve
local function fail_resolution() error('fixture palette failure') end
palette.resolve = fail_resolution
event('ColorScheme')
palette.resolve = original_resolve
assert(#calls == 7 and #warnings == 0, 'Palette resolution failure affected the editor')
adapter.setup({ hook = hook_path })
settle()
assert(#calls == 7, 'Repeated setup duplicated the publisher')
-- Shutdown retires a queued set and attempts a reset without waiting for it.
auto_finish = true
vim.api.nvim_exec_autocmds('ColorScheme', { group = 'beck_tmux_theme' })
local original_wait = vim.wait
vim.wait = function(_timeout, _callback, _interval, _fast_only)
  error('External styling must not delay editor exit')
end
vim.api.nvim_exec_autocmds('VimLeavePre', { group = 'beck_tmux_theme' })
vim.wait = original_wait
settle()
assert(#calls == 8 and calls[8].command[2] == 'reset' and not contains(8, '--force'),
  'Shutdown published stale colors or reset another owner')
event('VimResume')
assert(#calls == 8, 'Closing publisher was revived')
vim.api.nvim_del_augroup_by_name('beck_tmux_theme')
package.loaded['config.ui.tmux'] = nil
vim.system, vim.api.nvim_list_uis, vim.notify = original.system, original.list_uis, original.notify
vim.api.nvim_get_chan_info = original.chan_info
vim.env.TMUX, vim.env.TMUX_PANE = original.server, original.pane
vim.g.beck_tmux_theme = original.enabled
vim.fn.delete(hook_path)
