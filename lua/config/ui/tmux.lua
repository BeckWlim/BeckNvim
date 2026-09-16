-- External palette publication. Tmux owns pane targeting and owner recovery;
-- config.ui.palette owns color resolution, including light/dark fallbacks.
local M = {}
local session

local function terminal_owner()
  local interfaces = vim.api.nvim_list_uis()
  if #interfaces == 0 then return end
  for _, interface in ipairs(interfaces) do
    local client = vim.api.nvim_get_chan_info(interface.chan).client
    if client and client.name == 'nvim-tui' then
      local raw_pid = client.attributes and client.attributes.pid
      local pid_text = tostring(raw_pid)
      if pid_text:match('^[1-9]%d*$') then return pid_text end
    end
  end
  return tostring(vim.fn.getpid())
end

local function palette_arguments()
  local colors = require('config.ui.palette').resolve()
  local roles = {
    { 'bg', colors.background }, { 'surface', colors.block },
    { 'cursor', colors.selection }, { 'border', colors.border },
    { 'fg', colors.foreground }, { 'muted', colors.muted },
    { 'green', colors.syntax.func }, { 'cyan', colors.syntax.type },
    { 'yellow', colors.syntax.string }, { 'purple', colors.syntax.constant },
    { 'red', colors.history.deleted },
  }
  local arguments = {}
  for _, role in ipairs(roles) do
    arguments[#arguments + 1] = string.format('%s=#%06x', role[1], role[2])
  end
  return arguments
end

function M.setup(options)
  if session then return end
  local settings = options or {}
  local server = vim.env.TMUX
  local pane = vim.env.TMUX_PANE
  local hook_path = settings.hook or vim.fn.expand('~/.config/tmux/scripts/theme.sh')
  if settings.enabled == false or vim.g.beck_tmux_theme == false
      or not server or not server:match('^.+,%d+,%d+$')
      or not pane or not pane:match('^%%%d+$')
      or vim.fn.executable(hook_path) ~= 1 or vim.fn.executable('tmux') ~= 1 then
    return
  end

  local state = {
    active = true, closing = false, scheduled = false, running = false,
  }
  session = state
  local group = vim.api.nvim_create_augroup('beck_tmux_theme', { clear = true })
  local pump

  pump = function()
    if state.running or not state.pending then return end
    local action = state.pending
    state.pending = nil
    -- Headless commands can inherit TMUX without owning its terminal.
    if action == 'set' then
      if not state.active then return end
      local resolved, owner_pid = pcall(terminal_owner)
      if not resolved or not owner_pid then return end
      state.owner_pid = owner_pid
    end
    if not state.owner_pid then return end
    local command = { hook_path, action, '--owner', state.owner_pid }
    if action == 'set' then
      local resolved, arguments = pcall(palette_arguments)
      if not resolved then return end
      vim.list_extend(command, arguments)
    end
    state.running = true
    local started = pcall(vim.system, command, {
      text = true, timeout = 1000,
      env = { TMUX = server, TMUX_PANE = pane },
    }, function()
      vim.schedule(function()
        state.running = false
        pump()
      end)
    end)
    if not started then state.running = false end
  end

  local function request(action)
    state.pending = action
    if state.scheduled then return end
    state.scheduled = true
    vim.schedule(function()
      state.scheduled = false
      pump()
    end)
  end

  local function publish()
    if state.active and not state.closing then request('set') end
  end

  vim.api.nvim_create_autocmd({ 'VimEnter', 'UIEnter', 'ColorScheme' }, {
    group = group, callback = publish,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group, pattern = 'LazyLoad', callback = publish,
  })
  vim.api.nvim_create_autocmd({ 'VimResume', 'ShellCmdPost' }, {
    group = group,
    callback = function()
      if state.closing then return end
      state.active = true
      publish()
    end,
  })
  vim.api.nvim_create_autocmd('VimSuspend', {
    group = group,
    callback = function()
      state.active = false
      request('reset')
      pump()
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      state.closing = true
      state.active = false
      request('reset')
      pump()
      -- Never delay exit for external styling. The tmux-owned watcher recovers
      -- if Neovim exits before the queued reset can start or finish.
    end,
  })
  publish()
end

return M
