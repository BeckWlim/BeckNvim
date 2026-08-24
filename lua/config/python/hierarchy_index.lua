local project = require('config.project')
local python_environment = require('config.python.environment')

local M = {}
local index_states = {}
local setup_complete = false

local function script_path()
  return vim.fs.joinpath(
    vim.fn.stdpath('config'),
    'scripts',
    'python_hierarchy_index.py'
  )
end

local function python_executable(root)
  local system_python = vim.fn.exepath('python3')
  if system_python ~= '' then
    return system_python
  end
  local environment = python_environment.resolve(root)
  if environment then
    return environment.python
  end
  return 'python3'
end

local function new_index_document()
  return {
    classes = {},
    classes_by_id = {},
    classes_by_file = {},
    classes_by_name = {},
    children_by_base_id = {},
  }
end

local function prepare_index_document(response_document)
  local index_document = new_index_document()
  local response_classes = type(response_document) == 'table'
      and response_document.classes
    or nil
  if type(response_classes) ~= 'table' then
    return index_document
  end

  for _, class_record in ipairs(response_classes) do
    if type(class_record) == 'table'
        and type(class_record.id) == 'string'
        and type(class_record.filename) == 'string' then
      local normalized_filename = vim.fs.normalize(class_record.filename)
      local normalized_class_record = vim.tbl_extend('force', {}, class_record, {
        filename = normalized_filename,
      })
      table.insert(index_document.classes, normalized_class_record)
      index_document.classes_by_id[normalized_class_record.id] = normalized_class_record
      local named_classes = index_document.classes_by_name[normalized_class_record.name] or {}
      index_document.classes_by_name[normalized_class_record.name] = named_classes
      table.insert(named_classes, normalized_class_record)
      local file_classes = index_document.classes_by_file[normalized_filename] or {}
      index_document.classes_by_file[normalized_filename] = file_classes
      table.insert(file_classes, normalized_class_record)
      for _, base_id in ipairs(normalized_class_record.base_ids or {}) do
        local children = index_document.children_by_base_id[base_id] or {}
        index_document.children_by_base_id[base_id] = children
        table.insert(children, normalized_class_record)
      end
    end
  end
  return index_document
end

local function index_state(root)
  local state = index_states[root]
  if state then
    return state
  end
  local created_state = {
    status = 'idle',
    generation = 0,
    callbacks = {},
    document = new_index_document(),
    error_message = '',
  }
  index_states[root] = created_state
  return created_state
end

local function notify_callbacks(state)
  local pending_callbacks = state.callbacks
  state.callbacks = {}
  for _, callback in ipairs(pending_callbacks) do
    callback(state.document, state.error_message)
  end
end

local function start_build(root, state, serve_stale_document)
  local ready_document_available = state.status == 'ready' or state.status == 'refreshing'
  state.status = serve_stale_document and ready_document_available
      and 'refreshing'
    or 'loading'
  state.error_message = ''
  state.generation = state.generation + 1
  local active_generation = state.generation
  local started_at = vim.uv.hrtime()
  local command = {
    python_executable(root),
    script_path(),
    root,
  }

  vim.system(command, { text = true }, function(completed_process)
    vim.schedule(function()
      if state.generation ~= active_generation then
        return
      end
      if completed_process.code ~= 0 then
        if serve_stale_document and ready_document_available then
          state.status = 'ready'
          state.error_message = ''
        else
          state.status = 'error'
          state.error_message = vim.trim(completed_process.stderr)
        end
        notify_callbacks(state)
        return
      end

      local response_document = {}
      local decode_succeeded = pcall(function()
        local decoded_value = vim.json.decode(completed_process.stdout)
        if type(decoded_value) ~= 'table' then
          error('Python hierarchy index did not return a JSON object')
        end
        response_document = decoded_value
      end)
      if not decode_succeeded then
        if serve_stale_document and ready_document_available then
          state.status = 'ready'
          state.error_message = ''
        else
          state.status = 'error'
          state.error_message = 'Python hierarchy index returned invalid JSON'
        end
        notify_callbacks(state)
        return
      end

      state.document = prepare_index_document(response_document)
      state.status = 'ready'
      state.error_message = ''
      state.elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6
      notify_callbacks(state)
    end)
  end)
end

function M.ensure(root, callback)
  local normalized_root = vim.fs.normalize(root)
  local state = index_state(normalized_root)
  if state.status == 'ready' or state.status == 'refreshing' then
    callback(state.document, '')
    return
  end
  table.insert(state.callbacks, callback)
  if state.status ~= 'loading' then
    start_build(normalized_root, state, false)
  end
end

function M.refresh(root)
  local normalized_root = vim.fs.normalize(root)
  local state = index_state(normalized_root)
  start_build(normalized_root, state, true)
end

function M.for_buffer(bufnr, callback)
  local selected_buffer = bufnr or vim.api.nvim_get_current_buf()
  local root = project.for_buffer(selected_buffer)
  M.ensure(root, callback)
end

function M.find_class(index_document, filename, line_number)
  local normalized_filename = vim.fs.normalize(filename)
  local file_classes = index_document.classes_by_file[normalized_filename] or {}
  local containing_classes = {}
  for _, class_record in ipairs(file_classes) do
    if class_record.line <= line_number and line_number <= class_record.end_line then
      table.insert(containing_classes, class_record)
    end
  end
  table.sort(containing_classes, function(left_class, right_class)
    local left_span = left_class.end_line - left_class.line
    local right_span = right_class.end_line - right_class.line
    return left_span < right_span
  end)
  return containing_classes[1]
end

function M.find_method(class_record, line_number)
  if not class_record then
    return
  end
  for _, method_record in ipairs(class_record.methods or {}) do
    if method_record.start_line <= line_number and line_number <= method_record.end_line then
      return method_record
    end
  end
end

local function position_in_base(base_record, line_number, column_number)
  if line_number < base_record.line or line_number > base_record.end_line then
    return false
  end
  if line_number == base_record.line and column_number < base_record.column then
    return false
  end
  return line_number ~= base_record.end_line or column_number < base_record.end_column
end

function M.find_symbol_class(index_document, filename, line_number, column_number, symbol_name)
  local containing_class = M.find_class(index_document, filename, line_number)
  if containing_class then
    for _, base_record in ipairs(containing_class.bases or {}) do
      if base_record.resolved_id
        and position_in_base(base_record, line_number, column_number)
      then
        return index_document.classes_by_id[base_record.resolved_id]
      end
    end
    local declaration_end_column = containing_class.column + #containing_class.name
    if line_number == containing_class.line
      and containing_class.column <= column_number
      and column_number < declaration_end_column
    then
      return containing_class
    end
  end

  local named_classes = index_document.classes_by_name[symbol_name] or {}
  return #named_classes == 1 and named_classes[1] or nil
end

local function traverse_classes(index_document, root_class, direction)
  local traversed_records = {}
  local visited_ids = { [root_class.id] = true }
  local queue = {}
  local function enqueue(class_record, depth)
    if class_record and not visited_ids[class_record.id] then
      visited_ids[class_record.id] = true
      table.insert(queue, { class_record = class_record, depth = depth })
    end
  end

  if direction == 'derived' then
    for _, child_class in ipairs(index_document.children_by_base_id[root_class.id] or {}) do
      enqueue(child_class, 1)
    end
  else
    for _, base_id in ipairs(root_class.base_ids or {}) do
      enqueue(index_document.classes_by_id[base_id], 1)
    end
  end

  local queue_index = 1
  while queue_index <= #queue do
    local queued_record = queue[queue_index]
    queue_index = queue_index + 1
    table.insert(traversed_records, queued_record)
    if direction == 'derived' then
      for _, child_class in ipairs(
        index_document.children_by_base_id[queued_record.class_record.id] or {}
      ) do
        enqueue(child_class, queued_record.depth + 1)
      end
    else
      for _, base_id in ipairs(queued_record.class_record.base_ids or {}) do
        enqueue(
          index_document.classes_by_id[base_id],
          queued_record.depth + 1
        )
      end
    end
  end
  table.sort(traversed_records, function(left_record, right_record)
    if left_record.depth ~= right_record.depth then
      return left_record.depth < right_record.depth
    end
    return left_record.class_record.name < right_record.class_record.name
  end)
  return traversed_records
end

function M.derived(index_document, root_class)
  return traverse_classes(index_document, root_class, 'derived')
end

function M.supertypes(index_document, root_class)
  return traverse_classes(index_document, root_class, 'supertypes')
end

function M.implementations(index_document, root_class, method_record)
  local implementation_records = {}
  if not root_class or not method_record then
    return implementation_records
  end
  for _, derived_record in ipairs(M.derived(index_document, root_class)) do
    for _, candidate_method in ipairs(derived_record.class_record.methods or {}) do
      if candidate_method.name == method_record.name and not candidate_method.abstract then
        table.insert(implementation_records, {
          class_record = derived_record.class_record,
          method_record = candidate_method,
          depth = derived_record.depth,
        })
      end
    end
  end
  return implementation_records
end

function M.status(root)
  local normalized_root = vim.fs.normalize(root)
  local state = index_states[normalized_root]
  if not state then
    return { status = 'idle', elapsed_ms = 0, class_count = 0 }
  end
  return {
    status = state.status,
    elapsed_ms = state.elapsed_ms or 0,
    class_count = #state.document.classes,
  }
end

function M.reset()
  index_states = {}
end

function M.setup()
  if setup_complete then
    return
  end
  setup_complete = true
  local index_group = vim.api.nvim_create_augroup('python_hierarchy_index', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = index_group,
    pattern = 'python',
    callback = function(event)
      M.for_buffer(event.buf, function() end)
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = index_group,
    pattern = '*.py',
    callback = function(event)
      M.refresh(project.for_buffer(event.buf))
    end,
  })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'python' then
      M.for_buffer(bufnr, function() end)
    end
  end
end

return M
