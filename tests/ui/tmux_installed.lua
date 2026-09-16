-- Real foreground Neovim, installed themes, and the local tmux hook.
-- nvim --headless -u NONE -i NONE -l tests/ui/tmux_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local socket_path = directory .. '/tmux.sock'
local editor_socket = directory .. '/nvim.sock'
local config_path = vim.fn.expand('~/.config/tmux/tmux.conf')
local channel
local function tmux(arguments)
  local command = { 'tmux', '-N', '-S', socket_path }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function evaluate(source)
  return vim.rpcrequest(channel, 'nvim_exec_lua', source, {})
end
local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 30), message)
end
local function format(expression, pane)
  return tmux({ 'display-message', '-p', '-t', pane or '%0', expression })
end
local function expected_background()
  return evaluate([[return string.format('#%06x', require('config.ui.palette').resolve().background)]])
end
local function matches_editor()
  local background = expected_background()
  wait_for(function()
    return format('#{@beck_palette_bg}|#{E:@beck_pane_bg}') == background .. '|' .. background
  end, 'Tmux did not store and resolve the editor palette')
  local expected_window_colors = evaluate([[local colors = require('config.ui.palette').resolve()
    return string.format('#%06x|#%06x|#%06x|#%06x',
      colors.syntax.func, colors.selection, colors.muted, colors.background)]])
  assert(format('#{E:@beck_ui_window_active_fg}|#{E:@beck_ui_window_active_bg}|'
    .. '#{E:@beck_ui_window_inactive_fg}|#{E:@beck_ui_window_inactive_bg}') == expected_window_colors,
    'Optional window roles did not fall back to the application base palette')
  assert(format('#{@beck_palette_window_active_fg}#{@beck_palette_window_active_bg}'
    .. '#{@beck_palette_window_inactive_fg}#{@beck_palette_window_inactive_bg}') == '',
    'Adapter unexpectedly published optional window roles')
end
local function check()
  -- Only this disposable server is created or mutated.
  local result = vim.system({ 'tmux', '-S', socket_path, '-f', config_path,
    'new-session', '-d', '-s', 'adapter', '-x', '100', '-y', '32', '/bin/bash', '--noprofile', '--norc', '-i',
  }, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
  local shell_command = 'env XDG_STATE_HOME=' .. vim.fn.shellescape(directory)
    .. ' XDG_CACHE_HOME=/tmp/nvim-test-cache ' .. vim.fn.shellescape(vim.v.progpath)
    .. ' -u ' .. vim.fn.shellescape(vim.fn.getcwd() .. '/init.lua')
    .. ' -i NONE --listen ' .. vim.fn.shellescape(editor_socket)
  tmux({ 'send-keys', '-t', '%0', '-l', shell_command })
  tmux({ 'send-keys', '-t', '%0', 'Enter' })
  wait_for(function() return vim.uv.fs_stat(editor_socket) ~= nil end, 'Editor socket was not created')
  channel = vim.fn.sockconnect('pipe', editor_socket, { rpc = true })
  assert(channel > 0, 'Could not connect to foreground editor')
  wait_for(function() return evaluate('return vim.v.vim_did_enter == 1') end, 'Editor did not start')
  matches_editor()
  local owner_pid = evaluate([[local interface = vim.api.nvim_list_uis()[1]
    return vim.api.nvim_get_chan_info(interface.chan).client.attributes.pid or vim.fn.getpid()]])
  wait_for(function()
    return format('#{@beck_theme_owner}'):find(tostring(owner_pid) .. ':', 1, true) == 1
  end, 'Tmux did not record Neovim as the owner')
  for _, name in ipairs({ 'paper-light', 'catppuccin-latte', 'monokai' }) do
    assert(evaluate("return require('config.ui.theme').select('" .. name .. "')"))
    matches_editor()
  end
  -- A second shell pane has defaults; moving focus leaves Neovim's ownership intact.
  local shell_pane = tmux({ 'split-window', '-d', '-P', '-F', '#{pane_id}', '/bin/bash', '--noprofile', '--norc', '-i' })
  tmux({ 'select-pane', '-t', shell_pane })
  assert(format('#{E:@beck_pane_bg}', shell_pane) == '#272822', 'Shell inherited the application palette')
  assert(format('#{@beck_theme_owner}') ~= '', 'Pane focus revoked editor ownership')
  tmux({ 'select-pane', '-t', '%0' })
  -- Real Telescope preview and cancel use the same ColorScheme publication path.
  evaluate([[require('config.ui.theme').pick()
    require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf()):set_prompt('paper-light')]])
  wait_for(function()
    return evaluate([[return require('config.ui.theme').current().name == 'paper-light']])
  end, 'Theme picker did not preview Paper Light')
  matches_editor()
  evaluate([[require('telescope.actions').close(vim.api.nvim_get_current_buf())]])
  wait_for(function()
    return evaluate([[return require('config.ui.theme').current().name == 'monokai']])
  end, 'Theme picker did not roll back')
  matches_editor()
  tmux({ 'send-keys', '-t', '%0', 'C-z' })
  wait_for(function() return format('#{@beck_theme_owner}') == '' end, 'Suspend did not release the palette')
  tmux({ 'send-keys', '-t', '%0', '-l', 'fg' })
  tmux({ 'send-keys', '-t', '%0', 'Enter' })
  wait_for(function() return format('#{@beck_theme_owner}') ~= '' end, 'Resume did not reclaim the palette')
  matches_editor()
  -- Shell foreground handoffs can expire the watcher; ShellCmdPost reclaims it.
  evaluate([[vim.cmd('silent !sleep 2')]])
  wait_for(function() return format('#{@beck_theme_owner}') ~= '' end, 'Shell return lost palette ownership')
  assert(evaluate([[return require('config.ui.theme').select('paper-light')]]))
  matches_editor()
  vim.rpcnotify(channel, 'nvim_command', 'qa!')
  wait_for(function() return format('#{@beck_theme_owner}') == '' end, 'Exit did not release the palette')
  assert(format('#{E:@beck_pane_bg}') == '#272822', 'Exit did not restore tmux defaults')
end
local succeeded, failure = xpcall(check, debug.traceback)
if channel then pcall(vim.fn.chanclose, channel) end
pcall(tmux, { 'kill-server' })
vim.fn.delete(directory, 'rf')
assert(succeeded, failure)
print('Tmux installed integration passed')
