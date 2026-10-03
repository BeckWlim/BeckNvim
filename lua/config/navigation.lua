local M = {}
local window_state = require('config.ui.window_state')
local pending_by_tabpage = {}
local closers_by_buffer = {}
local dismiss_active_picker

---@class NavigationTransition
---@field action 'open'|'jump'
---@field window integer Pane whose file view would be replaced
---@field buffer integer Underlying file buffer, including rendered sources
---@field target_buffer integer

local boundaries = {}
local boundary_order = {}

-- Optional policies register at the transition boundary. The manager owns
-- targeting and history; extensions decide whether a file transition may run.
---@param name string
---@param callback fun(transition: NavigationTransition): boolean
---@return fun()
function M.register_boundary(name, callback)
  if not boundaries[name] then boundary_order[#boundary_order + 1] = name end
  boundaries[name] = callback
  return function()
    if boundaries[name] == callback then
      boundaries[name] = nil
      for index, candidate in ipairs(boundary_order) do
        if candidate == name then table.remove(boundary_order, index); break end
      end
    end
  end
end

local function allow_transition(transition)
  for _, name in ipairs(boundary_order) do
    local succeeded, allowed = xpcall(function() return boundaries[name](transition) end, debug.traceback)
    if not succeeded then vim.notify(allowed, vim.log.levels.ERROR); return false end
    if not allowed then return false end
  end
  return true
end

---@class NavigationContext
---@field source_window integer
---@field source_buffer integer
---@field tabpage integer
---@field restore_layout fun()

-- Capture before a temporary UI takes focus. Adapters carry this context to
-- selection; the manager validates it before applying any file operation.
---@param window? integer
---@return NavigationContext
function M.capture(window)
  local source_window = window or vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_win_get_tabpage(source_window)
  return {
    source_window = source_window,
    source_buffer = vim.api.nvim_win_get_buf(source_window),
    tabpage = tabpage,
    restore_layout = window_state.capture_layout(tabpage),
  }
end

local function context_current(context)
  return vim.api.nvim_tabpage_is_valid(context.tabpage)
    and vim.api.nvim_get_current_tabpage() == context.tabpage
    and vim.api.nvim_win_is_valid(context.source_window)
    and vim.api.nvim_win_get_tabpage(context.source_window) == context.tabpage
    and vim.api.nvim_win_get_buf(context.source_window) == context.source_buffer
end

-- Native window-local jumps also record / searches and plugin navigation.
-- Keep their buffer identities and ordering instead of maintaining a second
-- history. The caller's pane is the target even if another pane shows the file.
---@param direction 'back'|'forward'
---@param options? { window?: integer, count?: integer }
function M.jump(direction, options)
  local settings = options or {}
  local window = settings.window or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(window) then return false end
  local key = assert(({ back = '<C-o>', forward = '<C-i>' })[direction], 'Invalid jump direction')
  local count = math.max(1, settings.count or vim.v.count1)
  local view_buffer = vim.api.nvim_win_get_buf(window)
  local history = vim.fn.getjumplist(window)
  local target_index = direction == 'back' and history[2] - count or history[2] + count
  local destination = history[1][math.max(0, math.min(target_index, #history[1] - 1)) + 1]
  local source_buffer = window_state.file_buffer(window)
  if destination and vim.api.nvim_buf_is_valid(destination.bufnr) then
    local target_buffer = vim.b[destination.bufnr].markdown_preview_source or destination.bufnr
    if target_buffer ~= source_buffer and not allow_transition({
      action = 'jump', window = window, buffer = source_buffer, target_buffer = target_buffer,
    }) then return false end
  end
  if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_buf(window) ~= view_buffer then return false end
  local restore_layout = window_state.capture_layout(vim.api.nvim_win_get_tabpage(window))
  local succeeded, failure = xpcall(function()
    vim.api.nvim_win_call(window, function()
      vim.api.nvim_cmd({ cmd = 'normal', args = { tostring(count) .. vim.keycode(key) }, bang = true }, {})
    end)
  end, debug.traceback)
  restore_layout()
  if not succeeded then vim.notify(failure, vim.log.levels.ERROR) end
  return succeeded
end

function M.back() return M.jump('back') end
function M.forward() return M.jump('forward') end

local request_group = vim.api.nvim_create_augroup('file_operation_requests', { clear = true })
vim.api.nvim_create_autocmd({ 'WinClosed', 'TabClosed', 'BufWipeout' }, {
  group = request_group,
  callback = function(event)
    for tabpage, request in pairs(pending_by_tabpage) do
      if not vim.api.nvim_tabpage_is_valid(tabpage)
          or (event.event == 'WinClosed' and request.source_window == tonumber(event.match))
          or (event.event == 'BufWipeout' and request.source_buffer == event.buf) then
        request.cancel()
      end
    end
  end,
  desc = 'Cancel file opens when their source surface closes',
})

local function is_editor(window)
  if not vim.api.nvim_win_is_valid(window) then return false end
  local buffer = assert(window_state.file_buffer(window))
  return vim.api.nvim_win_get_config(window).relative == ''
    and (vim.bo[buffer].buftype == '' or vim.bo[buffer].filetype == 'dashboard')
end

local function can_replace(window)
  return is_editor(window) and not vim.wo[window].winfixbuf
end

local function editor_windows(tabpage)
  local windows = {}
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if can_replace(window) then windows[#windows + 1] = window end
  end
  return windows
end

local function file_views(buffer)
  local windows = {}
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if window_state.file_buffer(window) == buffer then windows[#windows + 1] = window end
  end
  return windows
end

-- One transient letter badge per eligible pane; the badges never alter splits.
function M.select_window(windows, callback)
  if dismiss_active_picker then dismiss_active_picker() end
  local source = vim.api.nvim_get_current_win()
  local badges, buffers = {}, {}
  local finished = false
  local dismiss
  local group = vim.api.nvim_create_augroup('file_operation_pane_picker', { clear = true })
  local function finish(window)
    if finished then return end
    finished = true
    if dismiss_active_picker == dismiss then dismiss_active_picker = nil end
    local picker_focused = vim.tbl_contains(badges, vim.api.nvim_get_current_win())
    vim.api.nvim_clear_autocmds({ group = group })
    for _, badge in ipairs(badges) do
      if vim.api.nvim_win_is_valid(badge) then vim.api.nvim_win_close(badge, true) end
    end
    for _, buffer in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
    end
    if picker_focused and vim.api.nvim_win_is_valid(source)
        and vim.api.nvim_win_get_tabpage(source) == vim.api.nvim_get_current_tabpage() then
      vim.api.nvim_set_current_win(source)
      if vim.bo.buftype == 'terminal' then
        local source_buffer = vim.api.nvim_get_current_buf()
        -- ToggleTerm restores its mode in a scheduled BufEnter callback. This
        -- picker was launched by an editor action; return to terminal Normal
        -- mode after that callback so another editor action stays usable.
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(source) and vim.api.nvim_get_current_win() == source
              and vim.api.nvim_win_get_buf(source) == source_buffer then
            vim.cmd('stopinsert')
          end
        end)
      end
    end
    callback(window)
  end
  dismiss = function() finish(nil) end
  local characters = 'abcdefghijklmnopqrstuvwxyz0123456789'
  if #windows > #characters then
    vim.notify('Too many editor panes for letter selection', vim.log.levels.ERROR)
    finish(nil)
    return function() end
  end
  for index, window in ipairs(windows) do
    local letter = characters:sub(index, index)
    local buffer = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buffer
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { ' ' .. letter .. ' ' })
    vim.bo[buffer].filetype = 'FilePanePicker'
    vim.bo[buffer].modifiable = false
    local badge = vim.api.nvim_open_win(buffer, false, {
      relative = 'win', win = window, width = 3, height = 1,
      row = math.floor(vim.api.nvim_win_get_height(window) / 2),
      col = math.max(0, math.floor((vim.api.nvim_win_get_width(window) - 3) / 2)),
      style = 'minimal', border = 'single', zindex = 250,
    })
    vim.wo[badge].winhighlight = 'Normal:FilePaneLabel,NormalNC:FilePaneLabel,NormalFloat:FilePaneLabel,FloatBorder:FilePaneBorder'
    vim.wo[badge].winblend = 0
    badges[#badges + 1] = badge
  end
  -- Every badge uses the same bindings, so mouse focus cannot change the policy.
  for _, buffer in ipairs(buffers) do
    for index, window in ipairs(windows) do
      local letter = characters:sub(index, index)
      vim.keymap.set('n', letter, function() finish(window) end, { buffer = buffer, nowait = true })
      if letter:match('%a') then
        vim.keymap.set('n', letter:upper(), function() finish(window) end, { buffer = buffer, nowait = true })
      end
    end
    for _, key in ipairs({ '<Esc>', '<C-c>', '<C-q>' }) do
      vim.keymap.set('n', key, function() finish(nil) end, { buffer = buffer, nowait = true })
    end
    M.register_close(buffer, function() finish(nil) end)
  end
  vim.api.nvim_create_autocmd({ 'WinClosed', 'TabLeave' }, {
    group = group,
    callback = function() vim.schedule(function() finish(nil) end) end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function()
      vim.schedule(function()
        if not vim.tbl_contains(badges, vim.api.nvim_get_current_win()) then finish(nil) end
      end)
    end,
  })
  vim.cmd('stopinsert')
  vim.api.nvim_set_current_win(badges[1])
  dismiss_active_picker = dismiss
  return dismiss
end

-- Reuse the pane badges for focus without applying file-destination filters.
-- Tree, terminal, protected editor, and Git panes are all valid focus targets.
function M.focus_window()
  local source = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(source).relative ~= '' then return false end
  local tabpage = vim.api.nvim_get_current_tabpage()
  local windows = {}
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_config(window).relative == '' then windows[#windows + 1] = window end
  end
  if #windows < 2 then return false end
  return M.select_window(windows, function(window)
    if window and vim.api.nvim_win_is_valid(window)
        and vim.api.nvim_get_current_tabpage() == tabpage
        and vim.api.nvim_win_get_tabpage(window) == tabpage then
      vim.api.nvim_set_current_win(window)
    end
  end)
end

-- A plugin owns disposal of its entire surface. Never close a picker pane alone.
function M.register_close(buffer, close)
  if not closers_by_buffer[buffer] then
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buffer, once = true,
      callback = function() closers_by_buffer[buffer] = nil end,
      desc = 'Release file-operation close adapter',
    })
  end
  closers_by_buffer[buffer] = close
end

function M.close(options)
  local settings = options or {}
  local window = settings.window or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(window) then return false end
  local buffer = vim.api.nvim_win_get_buf(window)
  local close = closers_by_buffer[buffer]
  local ordinary_file = vim.bo[buffer].buftype == ''
    and not vim.api.nvim_buf_get_name(buffer):match('^%w+://')
  vim.api.nvim_win_call(window, function()
    if close then close()
    elseif ordinary_file and #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(window)) > 1 then
      vim.cmd('close')
    else vim.cmd('quit') end
  end)
  return true
end

---@class FileOpenOptions
---@field context? NavigationContext
---@field source_window? integer
---@field command? 'edit'|'split'|'vsplit'|'tabedit'
---@field reopen? boolean Execute the native open even when the source file is already displayed
---@field buffer? integer
---@field keep_focus? boolean
---@field select_destination? boolean Ask which existing editor to replace even for an editor-origin open
---@field line? integer
---@field column? integer One-based byte column
---@field push_cursor? boolean
---@field push_tagstack? boolean
---@field on_open? fun(window: integer)
---@field run_command? fun(command: table) Feature-owned native command wrapper, called only after guards
---@field native_command? table Parsed interactive :edit command, including modifiers

---@param path string
---@param options? FileOpenOptions
function M.open(path, options)
  local settings = options or {}
  local source_window = settings.context and settings.context.source_window
    or settings.source_window or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(source_window) then return end
  local context = settings.context or M.capture(source_window)
  if not context_current(context) then return end
  local source_buffer = context.source_buffer
  local tabpage = context.tabpage
  local restore_layout = context.restore_layout
  local run_command = settings.run_command or function(command) vim.api.nvim_cmd(command, {}) end
  local request = {
    cancelled = false, finished = false, source_window = source_window, source_buffer = source_buffer,
  }
  local mode_change
  local dismiss_picker
  local previous_request = pending_by_tabpage[tabpage]
  if previous_request then previous_request.cancel() end
  pending_by_tabpage[tabpage] = request
  function request.cancel()
    request.cancelled = true
    if dismiss_picker then local dismiss = dismiss_picker; dismiss_picker = nil; dismiss() end
    if mode_change then pcall(vim.api.nvim_del_autocmd, mode_change); mode_change = nil end
    if pending_by_tabpage[tabpage] == request then pending_by_tabpage[tabpage] = nil end
  end
  local function current_request()
    return not request.cancelled and not request.finished
      and pending_by_tabpage[tabpage] == request
      and vim.api.nvim_tabpage_is_valid(tabpage)
      and vim.api.nvim_get_current_tabpage() == tabpage
      and vim.api.nvim_win_is_valid(source_window)
      and vim.api.nvim_win_get_buf(source_window) == source_buffer
  end
  local function open_in(window, create)
    if not current_request() then request.cancel(); return end
    if window and (not vim.api.nvim_win_is_valid(window)
        or vim.api.nvim_win_get_tabpage(window) ~= tabpage) then
      request.cancel()
      return
    end
    -- :stopinsert takes effect after the picker callback returns. Opening and
    -- positioning earlier shifts a requested byte column left on InsertLeave.
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    if mode == 'i' or mode == 't' then
      mode_change = vim.api.nvim_create_autocmd('ModeChanged', {
        group = request_group, pattern = { '*:n', '*:nt' },
        callback = function()
          if mode_change then vim.api.nvim_del_autocmd(mode_change) end
          mode_change = nil
          vim.schedule(function() open_in(window, create) end)
        end,
      })
      vim.cmd('stopinsert')
      -- Telescope can emit ModeChanged while closing its prompt, before this
      -- waiter exists, although nvim_get_mode still reports Insert mode in the
      -- same callback. Reconcile once after that callback has returned.
      vim.schedule(function()
        if not mode_change then return end
        local settled_mode = vim.api.nvim_get_mode().mode:sub(1, 1)
        if settled_mode == 'i' or settled_mode == 't' then return end
        vim.api.nvim_del_autocmd(mode_change)
        mode_change = nil
        open_in(window, create)
      end)
      return
    end
    local command = settings.command or 'edit'
    local native_tab = settings.native_command and settings.native_command.mods.tab >= 0
    local old_buffer = not create and window and window_state.file_buffer(window) or nil
    local target_buffer = settings.buffer or vim.fn.bufnr(vim.fn.fnamemodify(path, ':p'))
    local replacing = command == 'edit' and not native_tab and old_buffer and old_buffer ~= target_buffer
      and vim.bo[old_buffer].buftype == ''
      and not vim.api.nvim_buf_get_name(old_buffer):match('^%w+://')
    local covering = command == 'edit' and not native_tab and old_buffer
      and (old_buffer ~= target_buffer or settings.reopen or settings.native_command)
    if covering and (not allow_transition({
      action = 'open', window = assert(window), buffer = old_buffer, target_buffer = target_buffer,
    }) or not current_request() or not vim.api.nvim_win_is_valid(window)
      or window_state.file_buffer(window) ~= old_buffer) then
      request.cancel()
      return
    end
    request.finished = true
    pending_by_tabpage[tabpage] = nil
    local created_window
    local created_options
    local succeeded, failure = xpcall(function()
      if settings.buffer and not vim.api.nvim_buf_is_valid(settings.buffer) then
        error('The selected buffer is no longer available')
      end
      if create then
        created_options = assert(require('config.ui.window_state').resolve(
          source_window, { 'number', 'relativenumber' }))
        vim.api.nvim_set_current_win(source_window)
        vim.cmd('botright vnew')
        created_window = vim.api.nvim_get_current_win()
      else
        vim.api.nvim_set_current_win(assert(window))
      end
      if command == 'edit' and not native_tab and vim.b.markdown_preview_source
          and old_buffer == target_buffer and (settings.native_command or settings.buffer) then
        -- Explicitly reopening the source needs source restoration. Moving to
        -- another file lets the renderer's native leave/enter lifecycle retain
        -- its generated buffer and restore presentation for back/forward jumps.
        require('render-markdown').leave_preview()
      end
      if settings.push_cursor then vim.cmd("normal! m'") end
      if settings.push_tagstack then
        local from = { vim.fn.bufnr('%'), vim.fn.line('.'), vim.fn.col('.'), 0 }
        vim.fn.settagstack(vim.api.nvim_get_current_win(), {
          items = { { tagname = vim.fn.expand('<cword>'), from = from } },
        }, 't')
      end
      local tab_options = command == 'tabedit' and not is_editor(source_window)
        and require('config.ui.window_state').resolve(source_window, { 'number', 'relativenumber' }) or nil
      local resolved_command = create and (command == 'split' or command == 'vsplit')
        and 'edit' or command
      if settings.native_command then
        local native_command = vim.deepcopy(settings.native_command)
        if replacing then native_command.mods.hide = true end
        run_command(native_command)
      elseif settings.buffer then
        local buffer_commands = {
          edit = 'buffer', split = 'sbuffer', vsplit = 'sbuffer', tabedit = 'sbuffer',
        }
        run_command({
          cmd = assert(buffer_commands[resolved_command]), args = { tostring(settings.buffer) },
          mods = { hide = replacing or false, vertical = resolved_command == 'vsplit',
            tab = resolved_command == 'tabedit' and 0 or -1 },
        })
        vim.bo[settings.buffer].buflisted = true
      elseif resolved_command ~= 'edit' or old_buffer ~= target_buffer or settings.reopen then
        run_command({ cmd = resolved_command, args = { vim.fn.fnameescape(path) },
          mods = { hide = replacing or false } })
      end
      local opened_window = vim.api.nvim_get_current_win()
      local opened_options = created_options or tab_options
      if opened_options then
        require('config.ui.window_state').apply(opened_window, opened_options)
      end
      if settings.line then
        local file_buffer = assert(window_state.file_buffer(opened_window))
        local line = math.max(1, math.min(settings.line, vim.api.nvim_buf_line_count(file_buffer)))
        local text = vim.api.nvim_buf_get_lines(file_buffer, line - 1, line, false)[1] or ''
        local column = math.max(0, math.min((settings.column or 1) - 1, #text))
        local position = { line, column }
        local display_position = vim.b.markdown_preview_source
          and require('render-markdown').display_position(opened_window, position) or nil
        vim.api.nvim_win_set_cursor(opened_window, display_position or position)
      end
      if settings.on_open then settings.on_open(opened_window) end
    end, debug.traceback)
    request.succeeded = succeeded
    if not succeeded then
      if created_window and vim.api.nvim_win_is_valid(created_window) then
        pcall(vim.api.nvim_win_close, created_window, true)
      end
      if vim.api.nvim_win_is_valid(source_window) then vim.api.nvim_set_current_win(source_window) end
      vim.notify(failure, vim.log.levels.ERROR)
    else
      -- Retire only after the replacement succeeds, and never remove another
      -- pane's view or modifications made during the opening callbacks.
      if replacing and vim.api.nvim_buf_is_valid(old_buffer) and #file_views(old_buffer) == 0
          and not vim.bo[old_buffer].modified then
        -- Both :bdelete and :bunload remove native jumps into this file. Keep
        -- the hidden buffer, but remove it from ordinary buffer lists.
        local retired, retire_error = pcall(function()
          vim.bo[old_buffer].buflisted = false
        end)
        if not retired then vim.notify(tostring(retire_error), vim.log.levels.ERROR) end
      end
      if settings.keep_focus and vim.api.nvim_win_is_valid(source_window) then
        vim.api.nvim_set_current_win(source_window)
      end
    end
    if command == 'edit' and not native_tab and not create then restore_layout() end
  end
  -- Editor opens keep current-pane targeting and share the replacement guard.
  if (is_editor(source_window) and not settings.select_destination) or settings.command == 'tabedit' then
    open_in(source_window, false)
    return request
  end
  local windows = editor_windows(tabpage)
  if #windows == 0 then open_in(nil, true)
  elseif #windows == 1 then open_in(windows[1], false)
  else
    local buffers_by_window = {}
    for _, window in ipairs(windows) do buffers_by_window[window] = vim.api.nvim_win_get_buf(window) end
    vim.api.nvim_set_current_win(source_window)
    dismiss_picker = M.select_window(windows, function(window)
      dismiss_picker = nil
      if not window or not can_replace(window)
          or buffers_by_window[window] ~= vim.api.nvim_win_get_buf(window) then
        request.cancel()
        return
      end
      open_in(window, false)
    end)
  end
  return request
end

-- Adapt interactive file opens; programmatic and chained Ex commands remain
-- native. Interactive replacements use the same context and transition boundaries.
function M.command_line_enter()
  if vim.fn.getcmdtype() == ':' and (is_editor(vim.api.nvim_get_current_win())
      or vim.bo.filetype == 'NvimTree' or vim.bo.buftype == 'terminal') then
    local succeeded, command = pcall(vim.api.nvim_parse_cmd, vim.fn.getcmdline(), {})
    if succeeded and command.cmd == 'edit' and #command.args == 1 and command.nextcmd == '' then
      local expanded, resolved = pcall(vim.api.nvim_parse_cmd, vim.fn.expandcmd(vim.fn.getcmdline()), {})
      if expanded then
        local source = vim.api.nvim_get_current_win()
        vim.schedule(function()
          M.open(resolved.args[1], { source_window = source, native_command = resolved })
        end)
        return vim.keycode('<C-c>')
      end
    end
  end
  return vim.keycode('<CR>')
end

return M
