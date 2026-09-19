-- Theme selection and bounded asynchronous persistence. The colorscheme and
-- config.syntax.highlights own rendering; Telescope owns the picker surface.
local M = {}
local generation = 0
local pending_save
local saving = false
local save_sequence = 0
local preference_path
local active_preset
local picker_session

function M.state_path()
  return preference_path or vim.fn.stdpath('state') .. '/theme.json'
end

local function notify(message)
  vim.schedule(function() vim.notify('Theme: ' .. message, vim.log.levels.WARN) end)
end

local function valid_name(name)
  return type(name) == 'string' and #name > 0 and #name <= 128 and name:match('^[%w_.%-]+$') ~= nil
end

local function current()
  return { name = active_preset or vim.g.colors_name or 'default', background = vim.o.background }
end

M.current = current

local function preset_file(name)
  for _, directory in ipairs({ 'themes/', 'themes/default/' }) do
    local path = vim.api.nvim_get_runtime_file(directory .. name .. '.lua', false)[1]
    if path then return path end
  end
end

local function load_selection(name, background)
  local path = preset_file(name)
  local preset = path and dofile(path) or { colorscheme = name }
  assert(type(preset) == 'table' and valid_name(preset.colorscheme), 'invalid theme preset')
  assert(preset.background == nil or preset.background == 'dark' or preset.background == 'light',
    'invalid theme background')
  -- Changing background while the previous colorscheme is still named can
  -- reload it recursively. Retire its name before loading the chosen variant.
  vim.g.colors_name = nil
  vim.o.background = background or preset.background or vim.o.background
  -- Some schemes clear old groups only when colors_name is set. We retired it
  -- above to avoid a background-triggered reload, so clear stale colors here.
  vim.cmd('highlight clear')
  vim.api.nvim_cmd({ cmd = 'colorscheme', args = { preset.colorscheme } }, {})
  if preset.palette then
    require('config.syntax.highlights').load_palette(preset.palette)
    vim.api.nvim_exec_autocmds('ColorScheme', { pattern = preset.colorscheme })
  end
  active_preset = path and name or nil
end

local function restore(selection)
  return pcall(load_selection, selection.name, selection.background)
end

local function apply(name)
  if not valid_name(name) then return false, 'invalid theme name' end
  local previous = current()
  local succeeded, failure = pcall(load_selection, name)
  if not succeeded then restore(previous); return false, tostring(failure) end
  return true
end

local save_next
save_next = function()
  if saving or not pending_save then return end
  local request = pending_save
  pending_save = nil
  saving = true
  save_sequence = save_sequence + 1
  local temporary_path = request.path .. '.' .. vim.uv.os_getpid() .. '.' .. save_sequence .. '.tmp'
  local function finish(failure)
    if failure then
      vim.uv.fs_unlink(temporary_path, function() end)
      notify('could not save selection: ' .. failure)
    end
    saving = false
    save_next()
  end
  vim.uv.fs_mkdir(vim.fs.dirname(request.path), 448, function(directory_error)
    if directory_error and not directory_error:find('EEXIST', 1, true) then finish(directory_error); return end
    vim.uv.fs_open(temporary_path, 'w', 384, function(open_error, descriptor)
      if open_error then finish(open_error); return end
      vim.uv.fs_write(descriptor, request.document, 0, function(write_error, written)
        vim.uv.fs_close(descriptor, function(close_error)
          if write_error or close_error or written ~= #request.document then
            finish(write_error or close_error or 'incomplete write')
            return
          end
          vim.uv.fs_rename(temporary_path, request.path, finish)
        end)
      end)
    end)
  end)
end

local function remember()
  pending_save = { path = M.state_path(), document = vim.json.encode(current()) }
  save_next()
end

function M.select(name)
  local succeeded, failure = apply(name)
  if not succeeded then notify(failure); return false end
  remember()
  return true
end

function M.pick()
  -- Starting a picker retires a pending startup restore even before its first
  -- preview, so a late read cannot change the picker or its rollback target.
  generation = generation + 1
  if picker_session then return end
  local session = { previous = current(), confirmed = false }
  picker_session = session
  local opened, failure = pcall(require('config.search.telescope').theme_picker, {
    names = M.names(),
    preview = function(name)
      if picker_session ~= session then return end
      if session.previewed_name == name then return session.preview_error end
      session.previewed_name = name
      local succeeded, preview_error = apply(name)
      session.preview_error = preview_error
      if not succeeded then return preview_error end
    end,
    confirm = function(name)
      if picker_session ~= session then return false end
      if current().name ~= name then
        local succeeded, selection_error = apply(name)
        if not succeeded then notify(selection_error); return false end
      end
      session.confirmed = true
      remember()
      return true
    end,
    close = function()
      if picker_session ~= session then return end
      picker_session = nil
      if not session.confirmed then restore(session.previous) end
    end,
  })
  if not opened then
    picker_session = nil
    restore(session.previous)
    notify(tostring(failure))
  end
end

function M.names()
  local names = { current().name }
  local seen = { [names[1]] = true }
  for _, pattern in ipairs({ 'themes/*.lua', 'themes/default/*.lua' }) do
    for _, path in ipairs(vim.api.nvim_get_runtime_file(pattern, true)) do
      local name = vim.fn.fnamemodify(path, ':t:r')
      if not seen[name] then names[#names + 1] = name; seen[name] = true end
    end
  end
  return names
end

local function read_saved(callback)
  vim.uv.fs_open(M.state_path(), 'r', 384, function(open_error, descriptor)
    if open_error then
      if not open_error:find('ENOENT', 1, true) then notify(open_error) end
      return
    end
    vim.uv.fs_fstat(descriptor, function(stat_error, statistics)
      if stat_error or not statistics or statistics.type ~= 'file' or statistics.size > 4096 then
        vim.uv.fs_close(descriptor, function() end)
        notify('saved selection is unreadable or too large')
        return
      end
      vim.uv.fs_read(descriptor, statistics.size, 0, function(read_error, document)
        vim.uv.fs_close(descriptor, function() end)
        if read_error then notify(read_error); return end
        vim.schedule(function()
          local decoded, selection = pcall(vim.json.decode, document)
          if not decoded or type(selection) ~= 'table' or not valid_name(selection.name)
              or (selection.background ~= 'dark' and selection.background ~= 'light') then
            notify('saved selection is invalid; using the default')
            return
          end
          callback(selection)
        end)
      end)
    end)
  end)
end

function M.setup(options)
  local settings = options or {}
  preference_path = settings.state_file
  require('config.syntax.highlights').setup({ overrides = settings.overrides })
  local group = vim.api.nvim_create_augroup('project_theme', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      generation = generation + 1
      active_preset = nil
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      vim.wait(500, function() return not saving and not pending_save end, 10)
    end,
  })
  local function refresh_startup_highlights()
    vim.schedule(function()
      require('config.syntax.highlights').apply()
      vim.cmd('redraw!')
    end)
  end
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    once = true,
    callback = refresh_startup_highlights,
  })
  vim.api.nvim_create_user_command('Theme', function(command)
    if command.args == '' then M.pick() else M.select(command.args) end
  end, {
    nargs = '?',
    complete = function(lead)
      return vim.tbl_filter(function(name) return name:sub(1, #lead) == lead end, M.names())
    end,
    desc = 'Preview or apply and save a project theme',
  })
  local applied = apply(settings.default or 'monokai')
  if not applied then apply('habamax') end
  local startup_generation = generation
  read_saved(function(selection)
    if generation ~= startup_generation then return end
    local previous = current()
    local restored, failure = restore(selection)
    if not restored then
      restore(previous)
      notify('saved theme is unavailable; using the default: ' .. tostring(failure))
    end
    refresh_startup_highlights()
  end)
end

return M
