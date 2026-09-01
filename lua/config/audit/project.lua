local M = {}
local project = require('config.project')
local float = require('config.ui.float')
local audit_states = {}
local write_tracking_setup = false

local python_config_names = {
  ['pyrightconfig.json'] = true,
  ['basedpyrightconfig.json'] = true,
  ['pyproject.toml'] = true,
  ['setup.py'] = true,
}

local function audit_state(root)
  local normalized_root = vim.fs.normalize(root)
  local existing_state = audit_states[normalized_root]
  if existing_state then
    return existing_state
  end

  local new_state = {
    completed = false,
    write_generation = 0,
    dirty_paths = {},
    requires_full_scan = false,
  }
  audit_states[normalized_root] = new_state
  return new_state
end

local function sorted_dirty_paths(state)
  local paths = vim.tbl_keys(state.dirty_paths)
  table.sort(paths)
  return paths
end

local function clear_scanned_writes(state, scan_generation)
  for path, write_generation in pairs(state.dirty_paths) do
    if write_generation <= scan_generation then
      state.dirty_paths[path] = nil
    end
  end
  if state.write_generation <= scan_generation then
    state.requires_full_scan = false
  end
end

local function subscribe_to_completion(task, root)
  task:subscribe('on_complete', function(completed_task, _, result)
    local state = audit_state(root)
    local scan_generation = completed_task.metadata.project_audit_scan_generation or 0
    local completed_successfully = type(result) == 'table'
      and result.project_audit_report_valid == true

    if completed_successfully then
      state.completed = true
      clear_scanned_writes(state, scan_generation)
    end
  end)
end

local function close_task_float(bufnr)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid)
        and vim.api.nvim_win_get_buf(winid) == bufnr
        and vim.api.nvim_win_get_config(winid).relative ~= '' then
      vim.api.nvim_win_close(winid, true)
    end
  end
end

local function open_task_output(task)
  local bufnr = task:get_bufnr()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.b[bufnr].project_audit_root = task.cwd

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid)
        and vim.api.nvim_win_get_buf(winid) == bufnr
        and vim.api.nvim_win_get_config(winid).relative ~= '' then
      vim.api.nvim_set_current_win(winid)
      return
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content_width = 0
  for _, line in ipairs(lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
  end

  -- Keep the audit window close to a diagnostic float: content-sized with
  -- conservative caps, rather than Overseer's near-fullscreen task window.
  local width_cap = math.max(40, math.min(88, math.floor(vim.o.columns * 0.62)))
  local height_cap = math.max(8, math.min(16, math.floor((vim.o.lines - 2) * 0.34)))
  local width = math.max(40, math.min(content_width + 2, width_cap))
  local height = math.max(8, math.min(#lines, height_cap))
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Project Audit ',
    title_pos = 'center',
  })
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true

  local close = function()
    close_task_float(bufnr)
  end
  float.bind_close({
    buffer = bufnr,
    close = close,
    description = 'Close audit log',
  })
  vim.keymap.set('n', '<Esc>', close, { buffer = bufnr, nowait = true, silent = true, desc = 'Close audit log' })
end

local function current_project_root()
  local audit_root = vim.b.project_audit_root
  if type(audit_root) == 'string' and audit_root ~= '' then
    return vim.fs.normalize(audit_root)
  end
  return project.for_buffer(0)
end

local function buffer_project_root(bufnr)
  return project.for_buffer(bufnr)
end

local function audited_root_for_path(path)
  local selected_root
  for root in pairs(audit_states) do
    if project.contains(root, path) and (not selected_root or #root > #selected_root) then
      selected_root = root
    end
  end
  return selected_root
end

local function relevant_write_kind(root, path)
  if path:sub(1, #root + 7) == root .. '/.venv/' then
    return
  end

  local basename = vim.fs.basename(path)
  local extension = path:match('%.([^./]+)$')
  if project.is_python(root) then
    if python_config_names[basename] then
      return 'python-config'
    end
    if extension == 'py' or extension == 'pyi' then
      return 'python-source'
    end
  end
end

local function setup_write_tracking()
  if write_tracking_setup then
    return
  end
  write_tracking_setup = true

  local group = vim.api.nvim_create_augroup('project_audit_writes', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(event)
      local buffer_path = vim.api.nvim_buf_get_name(event.buf)
      if buffer_path == '' then
        return
      end
      local normalized_path = vim.fs.normalize(buffer_path)
      local detected_root = audited_root_for_path(normalized_path)
        or buffer_project_root(event.buf)
      if not detected_root then
        return
      end
      local root = vim.fs.normalize(detected_root)
      local state = audit_states[root]
      if not state then
        -- The first explicit audit establishes the initial state, so writes
        -- that happened before it do not need a separate incremental index.
        return
      end

      local write_kind = relevant_write_kind(root, normalized_path)
      if not write_kind then
        return
      end
      state.write_generation = state.write_generation + 1
      state.dirty_paths[normalized_path] = state.write_generation
      if write_kind == 'python-config' then
        state.requires_full_scan = true
      end
    end,
    desc = 'Track saved files for incremental project audits',
  })
end

local function task_name(root, kind)
  return ('Project Audit: %s [%s:%s]'):format(
    kind,
    vim.fs.basename(root),
    vim.fn.sha256(root):sub(1, 8)
  )
end

local function find_existing_task(overseer, name)
  for _, task in ipairs(overseer.list_tasks({ recent_first = true })) do
    if task.name == name then
      return task
    end
  end
end

local function run_basedpyright(overseer, root)
  local python_environment = require('config.python.environment').resolve(root)
  local path_analyzer = vim.fn.exepath('basedpyright')
  local analyzer = python_environment and python_environment.basedpyright
    or path_analyzer ~= '' and path_analyzer
    or nil
  if not analyzer then
    vim.notify(
      'Project audit: basedpyright is unavailable; install it in .venv or on PATH',
      vim.log.levels.ERROR
    )
    return
  end

  local name = task_name(root, 'basedpyright')
  local existing_task = find_existing_task(overseer, name)
  if existing_task and existing_task:is_running() then
    open_task_output(existing_task)
    vim.notify('Project audit: existing scan is still running; focused its log')
    return
  end

  local state = audit_state(root)
  local dirty_paths = sorted_dirty_paths(state)
  if existing_task and state.completed and #dirty_paths == 0 and not state.requires_full_scan then
    open_task_output(existing_task)
    vim.notify('Project audit: <Space>gs already completed; no relevant files were written')
    return
  end

  local incremental = existing_task ~= nil
    and state.completed
    and not state.requires_full_scan
    and #dirty_paths > 0
  local scan_mode = incremental and 'incremental' or 'full'
  local scan_targets = incremental and dirty_paths or {}
  local scan_generation = state.write_generation

  local command = { analyzer, '--outputjson', '--project', root }
  if python_environment then
    vim.list_extend(command, { '--pythonpath', python_environment.python })
  end
  if incremental then
    vim.list_extend(command, scan_targets)
  end

  if existing_task then
    existing_task.cmd = command
    existing_task.metadata.project_audit_mode = scan_mode
    existing_task.metadata.project_audit_targets = scan_targets
    existing_task.metadata.project_audit_scan_generation = scan_generation
    existing_task.metadata.project_audit_python = python_environment and python_environment.python or nil
    existing_task.metadata.project_audit_environment = python_environment and python_environment.directory or nil
    existing_task:restart()
    open_task_output(existing_task)
    return
  end

  local audit_task = overseer.new_task({
    name = name,
    -- An argv list bypasses shell parsing, so project paths remain safe even
    -- when they contain spaces or shell metacharacters.
    cmd = command,
    cwd = root,
    metadata = {
      project_audit_kind = 'basedpyright',
      project_audit_mode = scan_mode,
      project_audit_targets = scan_targets,
      project_audit_scan_generation = scan_generation,
      project_audit_python = python_environment and python_environment.python or nil,
      project_audit_environment = python_environment and python_environment.directory or nil,
    },
    strategy = { 'jobstart', use_terminal = false },
    components = {
      'project_audit.basedpyright',
      'on_exit_set_status',
      'on_complete_notify',
    },
  })
  subscribe_to_completion(audit_task, root)
  audit_task:start()
  open_task_output(audit_task)
end

function M.run_or_open()
  local root = current_project_root()
  if project.is_python(root) then
    local ok, overseer = pcall(require, 'overseer')
    if not ok then
      vim.notify('Project audit: Overseer is not available', vim.log.levels.ERROR)
      return
    end
    run_basedpyright(overseer, root)
    return
  end

  if vim.uv.fs_stat(vim.fs.joinpath(root, 'CMakeLists.txt')) then
    vim.notify(
      'Project audit: C/C++ is not supported by <Space>gs; '
        .. 'use <Space>gq for diagnostics published by clangd from open files',
      vim.log.levels.WARN
    )
    return
  end

  -- Other ecosystems can use Overseer's standard templates without extending
  -- this module with another scheduler/provider abstraction.
  local ok, overseer = pcall(require, 'overseer')
  if not ok then
    vim.notify('Project audit: Overseer is not available', vim.log.levels.ERROR)
    return
  end
  vim.cmd.OverseerRun()
end

setup_write_tracking()

return M
