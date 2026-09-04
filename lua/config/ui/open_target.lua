local project = require('config.project')

local M = {}

local function notify_error(error_message)
  vim.notify(error_message, vim.log.levels.ERROR)
  return false
end

local function is_external_uri(target)
  local uri_scheme = target:match('^([%a][%w+.-]*):')
  local is_windows_path = target:match('^%a:[/\\]') ~= nil
  return uri_scheme ~= nil and uri_scheme ~= 'file' and not is_windows_path
end

local function split_file_reference(target)
  local fragment_start = target:find('#', 1, true)
  local path_text = fragment_start and target:sub(1, fragment_start - 1) or target
  local fragment_text = fragment_start and target:sub(fragment_start + 1) or ''
  return path_text, fragment_text
end

local function markdown_destination_at_cursor()
  if vim.bo.filetype ~= 'markdown' then
    return nil
  end
  local cursor_column = vim.api.nvim_win_get_cursor(0)[2] + 1
  local current_line = vim.api.nvim_get_current_line()
  local search_start = 1
  while search_start <= #current_line do
    local label_start, label_end = current_line:find('%b[]', search_start)
    if not label_start then
      return nil
    end
    local destination_start, destination_end = current_line:find('%b()', label_end + 1)
    local is_inline_link = destination_start == label_end + 1
    if is_inline_link
      and cursor_column >= label_start
      and cursor_column <= assert(destination_end)
    then
      local destination_text = current_line:sub(destination_start + 1, destination_end - 1)
      local angle_destination = destination_text:match('^%s*<(.-)>')
      return angle_destination or destination_text:match('^%s*(%S+)')
    end
    search_start = label_end + 1
  end
  return nil
end

local function resolve_file_reference(target)
  local path_text, fragment_text = split_file_reference(target)
  local current_buffer_path = vim.api.nvim_buf_get_name(0)
  local decoded_path
  if vim.startswith(path_text, 'file://') then
    local decoded_file_path
    local decode_ok = pcall(function()
      decoded_file_path = vim.uri_to_fname(path_text)
    end)
    if not decode_ok then
      return nil, ('Invalid file URI: %s'):format(target)
    end
    decoded_path = assert(decoded_file_path)
  elseif path_text == '' and current_buffer_path ~= '' then
    decoded_path = current_buffer_path
  else
    decoded_path = vim.uri_decode(path_text)
  end

  if decoded_path == '' then
    return nil, 'No filepath or URI under cursor'
  end

  local normalized_path = vim.fs.normalize(decoded_path)
  local is_absolute_path = normalized_path:sub(1, 1) == '/'
    or normalized_path:match('^%a:/') ~= nil
  local buffer_directory = current_buffer_path ~= ''
      and vim.fs.dirname(vim.fs.normalize(current_buffer_path))
    or vim.fn.getcwd()
  local resolved_path = is_absolute_path
      and normalized_path
    or vim.fs.normalize(vim.fs.joinpath(buffer_directory, normalized_path))
  if vim.fn.filereadable(resolved_path) ~= 1 then
    return nil, ('File does not exist: %s'):format(resolved_path)
  end

  local referenced_line = tonumber(fragment_text:match('^L(%d+)'))
  local source_project_root = current_buffer_path ~= ''
      and project.resolve_path(current_buffer_path)
    or nil
  local target_project_root = project.resolve_path(resolved_path)
  local same_project = source_project_root ~= nil
    and target_project_root == source_project_root
  return {
    line = referenced_line,
    outside_project = not same_project,
    path = resolved_path,
  }, nil
end

local function jump_to_referenced_line(referenced_line)
  if not referenced_line then
    return
  end
  local buffer_line_count = vim.api.nvim_buf_line_count(0)
  local bounded_line = math.max(1, math.min(referenced_line, buffer_line_count))
  vim.api.nvim_win_set_cursor(0, { bounded_line, 0 })
end

local function eventignore_with_filetype(previous_eventignore)
  local ignored_events = vim.split(previous_eventignore, ',', { plain = true, trimempty = true })
  if vim.list_contains(ignored_events, 'FileType') then
    return previous_eventignore
  end
  ignored_events[#ignored_events + 1] = 'FileType'
  return table.concat(ignored_events, ',')
end

local function execute_safely(action)
  local action_error
  local action_ok = xpcall(action, function(execution_error)
    action_error = tostring(execution_error)
  end)
  return action_ok, action_error
end

local function execute_while_ignoring_filetype(action)
  local previous_eventignore = vim.o.eventignore
  vim.o.eventignore = eventignore_with_filetype(previous_eventignore)
  local action_ok, action_error = execute_safely(action)
  vim.o.eventignore = previous_eventignore
  return action_ok, action_error
end

local function execute_open_command(open_command, command_options, lightweight)
  if lightweight then
    return execute_while_ignoring_filetype(function()
      open_command(command_options)
    end)
  end
  return execute_safely(function()
    open_command(command_options)
  end)
end

local function set_lightweight_filetype(buffer)
  if vim.bo[buffer].filetype ~= '' then
    return
  end
  local buffer_path = vim.api.nvim_buf_get_name(buffer)
  local detected_filetype = vim.filetype.match({ buf = buffer, filename = buffer_path })
  if not detected_filetype then
    return
  end
  local filetype_ok, filetype_error = execute_while_ignoring_filetype(function()
    vim.bo[buffer].filetype = detected_filetype
  end)
  if not filetype_ok then
    notify_error(assert(filetype_error))
  end
end

local function start_lightweight_syntax(buffer)
  vim.b[buffer].gx_lightweight_render = true
  set_lightweight_filetype(buffer)
  pcall(vim.treesitter.start, buffer)
end

local function open_file_reference(file_reference)
  local display_path = vim.fn.fnamemodify(file_reference.path, ':~:.')
  local confirmation = vim.fn.confirm(
    ('Open local file? A current-window jump replaces this window\'s render.\n%s'):format(
      display_path
    ),
    '&Yes (current window)\n&No\n&Vertical split\n&Horizontal split',
    2,
    'Question'
  )
  if confirmation == 0 or confirmation == 2 then
    return false
  end

  local command_name = confirmation == 3 and 'vsplit'
    or confirmation == 4 and 'split'
    or 'edit'
  local lightweight = file_reference.outside_project
  local open_command = vim.cmd[command_name]
  local command_options = { args = { file_reference.path } }
  local open_ok, command_error = execute_open_command(
    open_command,
    command_options,
    lightweight
  )
  if not open_ok then
    return notify_error(assert(command_error))
  end
  if lightweight then
    start_lightweight_syntax(vim.api.nvim_get_current_buf())
  end
  jump_to_referenced_line(file_reference.line)
  return true
end

local function open_external_uri(target)
  -- Opening is a detached handoff. In WSL, explorer.exe may return 1 after
  -- Windows has already accepted the target, so its eventual status is not a
  -- reliable signal of whether the browser opened.
  local _, open_error = vim.ui.open(target)
  if open_error then
    return notify_error(open_error)
  end
  return true
end

local function open_github_record(target)
  if not target:lower():match('^https?://[^/]*github[^/]*/') then
    return false
  end
  local module_loaded, issue_view = pcall(require, 'config.git.issue')
  if not module_loaded or type(issue_view.open_url) ~= 'function' then
    return false
  end
  local render_started, target_handled = pcall(issue_view.open_url, target)
  return render_started and target_handled == true
end

function M.open_external(target)
  if not is_external_uri(target) then
    return notify_error(('Not an external URI: %s'):format(target))
  end
  return open_external_uri(target)
end

function M.open(target)
  if is_external_uri(target) then
    if open_github_record(target) then
      return true
    end
    return M.open_external(target)
  end
  local file_reference, resolution_error = resolve_file_reference(target)
  if resolution_error then
    return notify_error(resolution_error)
  end
  local resolved_file_reference = assert(file_reference)
  return open_file_reference(resolved_file_reference)
end

function M.open_at_cursor()
  local markdown_destination = markdown_destination_at_cursor()
  local cursor_targets = markdown_destination
      and { markdown_destination }
    or require('vim.ui')._get_urls()
  local opened_targets = {}
  for _, cursor_target in ipairs(cursor_targets) do
    if not opened_targets[cursor_target] then
      opened_targets[cursor_target] = true
      M.open(cursor_target)
    end
  end
end

function M.open_selection()
  local selection_start = vim.fn.getpos('.')
  local selection_end = vim.fn.getpos('v')
  local selection_type = vim.fn.mode()
  local selected_lines = vim.fn.getregion(selection_start, selection_end, {
    type = selection_type,
  })
  local trimmed_lines = vim.iter(selected_lines):map(vim.trim):totable()
  M.open(table.concat(trimmed_lines))
end

return M
