local project = require('config.project')
local python_hierarchy_index = require('config.python.hierarchy_index')
local query_picker = require('config.query_picker')

local M = {}

local hierarchy_methods = {
  subtypes = 'typeHierarchy/subtypes',
  supertypes = 'typeHierarchy/supertypes',
}

local function current_query_context()
  local source_buffer = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  local source_cursor = vim.api.nvim_win_get_cursor(source_window)
  return {
    bufnr = source_buffer,
    column_number = source_cursor[2] + 1,
    filename = vim.api.nvim_buf_get_name(source_buffer),
    line_number = source_cursor[1],
    root = project.for_buffer(source_buffer),
    root_name = vim.fn.expand('<cword>'),
    window = source_window,
  }
end

local function relative_path(root, filename)
  return vim.fs.relpath(root, filename) or filename
end

local function new_location_picker(title, entry_maker)
  local telescope_config = require('telescope.config').values
  local picker_options = {}
  return query_picker.open({
    title = title,
    picker_options = picker_options,
    entry_maker = entry_maker,
    previewer = telescope_config.grep_previewer(picker_options),
    sorter = telescope_config.generic_sorter(picker_options),
  })
end

local function open_location_picker(title, records, entry_maker, session)
  local active_session = session or new_location_picker(title, entry_maker)
  active_session:finish(records)
end

local function hierarchy_item_key(item)
  local item_range = item.selectionRange or item.range
  return table.concat({
    item.uri,
    item.name,
    item_range.start.line,
    item_range.start.character,
  }, ':')
end

local function hierarchy_entry(root, direction)
  local arrow = direction == 'subtypes' and '↳ ' or '↰ '
  return function(record)
    local item = record.item
    local item_range = item.selectionRange or item.range
    local filename = vim.uri_to_fname(item.uri)
    local item_path = relative_path(root, filename)
    local hierarchy_name = string.rep('  ', record.depth - 1) .. arrow .. item.name
    local detail = item.detail or ''
    return {
      value = record,
      ordinal = ('%s %s %s'):format(item.name, detail, item_path),
      display = ('%-42s  %-24s  %s:%d'):format(
        hierarchy_name,
        detail,
        item_path,
        item_range.start.line + 1
      ),
      filename = filename,
      lnum = item_range.start.line + 1,
      col = item_range.start.character + 1,
      text = item.name,
    }
  end
end

local function show_hierarchy(client, root_item, direction, bufnr, session)
  local method = hierarchy_methods[direction]
  local root = project.for_buffer(bufnr)
  local visited_items = { [hierarchy_item_key(root_item)] = true }
  local hierarchy_records = {}
  local pending_request_count = 0
  local picker_opened = false

  local function finish_if_complete()
    if pending_request_count ~= 0 or picker_opened then
      return
    end
    picker_opened = true
    table.sort(hierarchy_records, function(left_record, right_record)
      if left_record.depth ~= right_record.depth then
        return left_record.depth < right_record.depth
      end
      return left_record.item.name < right_record.item.name
    end)
    local title = direction == 'subtypes' and 'Derived Classes' or 'Base Classes'
    open_location_picker(title, hierarchy_records, hierarchy_entry(root, direction), session)
  end

  local function request_related_items(parent_item, depth)
    pending_request_count = pending_request_count + 1
    local request_succeeded, request_id = client:request(
      method,
      { item = parent_item },
      function(request_error, related_items)
        if session:is_closed() then
          return
        end
        if request_error then
          vim.notify(request_error.message, vim.log.levels.WARN)
        elseif related_items then
          for _, related_item in ipairs(related_items) do
            local related_key = hierarchy_item_key(related_item)
            if not visited_items[related_key] then
              visited_items[related_key] = true
              table.insert(hierarchy_records, {
                depth = depth,
                item = related_item,
              })
              session:update(
                hierarchy_records,
                ('querying… %d classes available'):format(#hierarchy_records)
              )
              request_related_items(related_item, depth + 1)
            end
          end
        end
        pending_request_count = pending_request_count - 1
        finish_if_complete()
      end,
      bufnr
    )
    if request_succeeded and request_id then
      session:add_cancel(function()
        if client.requests and client.requests[request_id] then
          client:cancel_request(request_id)
        end
      end)
    end
    if not request_succeeded then
      pending_request_count = pending_request_count - 1
      finish_if_complete()
    end
  end

  request_related_items(root_item, 1)
end

local function select_hierarchy_root(resolved_items, direction, bufnr, session)
  if #resolved_items == 0 then
    session:finish({})
    return
  end

  local function use_selection(selection)
    if selection then
      show_hierarchy(selection.client, selection.item, direction, bufnr, session)
    else
      session:finish({})
    end
  end

  if #resolved_items == 1 then
    use_selection(resolved_items[1])
    return
  end

  vim.ui.select(resolved_items, {
    prompt = 'Select class for type hierarchy:',
    format_item = function(selection)
      local detail = selection.item.detail or ''
      return ('%s %s'):format(selection.item.name, detail)
    end,
  }, use_selection)
end

local function open_hierarchy(direction, session, context)
  local bufnr = context.bufnr
  local window = context.window
  local prepare_method = 'textDocument/prepareTypeHierarchy'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = prepare_method })
  if #clients == 0 then
    session:fail('unsupported by active LSP')
    return
  end

  local cancel_prepare = vim.lsp.buf_request_all(bufnr, prepare_method, function(client)
    return vim.lsp.util.make_position_params(window, client.offset_encoding)
  end, function(request_results)
    if session:is_closed() then
      return
    end
    local resolved_items = {}
    for client_id, response in pairs(request_results) do
      local client = vim.lsp.get_client_by_id(client_id)
      if response.err then
        vim.notify(response.err.message, vim.log.levels.WARN)
      elseif client and response.result then
        for _, item in ipairs(response.result) do
          table.insert(resolved_items, { client = client, item = item })
        end
      end
    end
    select_hierarchy_root(resolved_items, direction, bufnr, session)
  end)
  session:add_cancel(cancel_prepare)
end

local function file_lines(filename)
  local buffer_number = vim.fn.bufnr(filename)
  if buffer_number >= 0 and vim.api.nvim_buf_is_loaded(buffer_number) then
    return vim.api.nvim_buf_get_lines(buffer_number, 0, -1, false)
  end

  local source_lines = {}
  local read_succeeded = pcall(function()
    source_lines = vim.fn.readfile(filename)
  end)
  return read_succeeded and source_lines or {}
end

local function parse_source(source, language)
  local parsed_trees = {}
  local parse_succeeded = pcall(function()
    local parser = vim.treesitter.get_string_parser(source, language)
    parsed_trees = parser:parse()
  end)
  return parse_succeeded and parsed_trees[1] or nil
end

local function normalized_locations(result)
  if not result then
    return {}
  end
  local locations = vim.islist(result) and result or { result }
  local normalized = {}
  for _, location in ipairs(locations) do
    local location_uri = location.targetUri or location.uri
    local location_range = location.targetSelectionRange
      or location.targetRange
      or location.range
    if location_uri and location_range then
      table.insert(normalized, { uri = location_uri, range = location_range })
    end
  end
  return normalized
end

local function python_class_item(location)
  local filename = vim.uri_to_fname(location.uri)
  local source_lines = file_lines(filename)
  local line_number = location.range.start.line + 1
  local definition_line = source_lines[line_number] or ''
  local class_name = definition_line:match('^%s*class%s+([%a_][%w_]*)')
  if not class_name then
    return
  end
  return {
    name = class_name,
    kind = vim.lsp.protocol.SymbolKind.Class,
    uri = location.uri,
    range = location.range,
    selectionRange = location.range,
  }
end

local function first_python_class_item(locations)
  for _, location in ipairs(locations) do
    local class_item = python_class_item(location)
    if class_item then
      return class_item
    end
  end
end

local function base_reference_node(base_expression)
  local expression_type = base_expression:type()
  if expression_type == 'identifier' then
    return base_expression
  end
  if expression_type == 'attribute' then
    return base_expression:field('attribute')[1]
  end
  if expression_type == 'subscript' or expression_type == 'call' then
    local value_field = expression_type == 'subscript' and 'value' or 'function'
    local value_node = base_expression:field(value_field)[1]
    return value_node and base_reference_node(value_node) or nil
  end
  if expression_type == 'keyword_argument' then
    return
  end

  local first_named_child = base_expression:named_child(0)
  return first_named_child and base_reference_node(first_named_child) or nil
end

local function python_base_references(class_item)
  local filename = vim.uri_to_fname(class_item.uri)
  local source_lines = file_lines(filename)
  local source = table.concat(source_lines, '\n')
  local syntax_tree = parse_source(source, 'python')
  if not syntax_tree then
    return {}
  end

  local target_line = class_item.selectionRange.start.line
  local class_node = syntax_tree:root():named_descendant_for_range(
    target_line,
    0,
    target_line,
    0
  )
  while class_node and class_node:type() ~= 'class_definition' do
    class_node = class_node:parent()
  end
  if not class_node then
    return {}
  end

  local superclasses = class_node:field('superclasses')[1]
  if not superclasses then
    return {}
  end
  local base_references = {}
  for child_index = 0, superclasses:named_child_count() - 1 do
    local base_expression = superclasses:named_child(child_index)
    local reference_node = base_expression and base_reference_node(base_expression) or nil
    if reference_node then
      local start_row, start_column = reference_node:range()
      table.insert(base_references, {
        position = { line = start_row, character = start_column },
      })
    end
  end
  return base_references
end

local function python_implementation_name(filename, line_number, fallback_text)
  local source_lines = file_lines(filename)
  local definition_line = source_lines[line_number] or ''
  local async_method_indent, async_method_name = definition_line:match(
    '^(%s*)async%s+def%s+([%a_][%w_]*)'
  )
  local synchronous_method_indent, synchronous_method_name = definition_line:match(
    '^(%s*)def%s+([%a_][%w_]*)'
  )
  local method_indent = async_method_indent or synchronous_method_indent
  local method_name = async_method_name or synchronous_method_name
  if not method_name then
    return vim.trim(fallback_text)
  end

  for source_index = line_number - 1, 1, -1 do
    local class_indent, class_name = source_lines[source_index]:match(
      '^(%s*)class%s+([%a_][%w_]*)'
    )
    if class_name and #class_indent < #method_indent then
      return class_name .. '.' .. method_name
    end
  end
  return method_name
end

local function cpp_implementation_name(filename, line_number, column_number, fallback_text)
  local method_name = fallback_text:match('([%a_~][%w_:~]*)%s*%(')
  if not method_name then
    return vim.trim(fallback_text)
  end
  if method_name:find('::', 1, true) then
    return method_name
  end

  local source_lines = file_lines(filename)
  local source = table.concat(source_lines, '\n')
  local syntax_tree = parse_source(source, 'cpp')
  if not syntax_tree then
    return vim.trim(fallback_text)
  end

  local target_line = line_number - 1
  local target_column = math.max(0, column_number - 1)
  local owner_node = syntax_tree:root():named_descendant_for_range(
    target_line,
    target_column,
    target_line,
    target_column
  )
  while owner_node
      and owner_node:type() ~= 'class_specifier'
      and owner_node:type() ~= 'struct_specifier' do
    owner_node = owner_node:parent()
  end
  if not owner_node then
    return method_name
  end

  local class_name_node = owner_node:field('name')[1]
  if not class_name_node then
    return method_name
  end
  local class_name = vim.treesitter.get_node_text(class_name_node, source)
  return class_name .. '::' .. method_name
end

local c_family_extensions = {
  c = true,
  cc = true,
  cpp = true,
  cxx = true,
  h = true,
  hh = true,
  hpp = true,
  hxx = true,
  cu = true,
  cuh = true,
}

local function implementation_name(filename, line_number, column_number, fallback_text)
  local extension = filename:match('%.([^./]+)$')
  local normalized_extension = extension and extension:lower() or ''
  if normalized_extension == 'py' then
    return python_implementation_name(filename, line_number, fallback_text)
  end
  if c_family_extensions[normalized_extension] then
    return cpp_implementation_name(
      filename,
      line_number,
      column_number,
      fallback_text
    )
  end
  return vim.trim(fallback_text)
end

local function implementation_entry(root)
  return function(record)
    local implementation_path = relative_path(root, record.filename)
    return {
      value = record,
      ordinal = ('%s %s'):format(record.name, implementation_path),
      display = ('%-48s  %s:%d'):format(
        record.name,
        implementation_path,
        record.lnum
      ),
      filename = record.filename,
      lnum = record.lnum,
      col = record.col,
      text = record.text,
    }
  end
end

local function indexed_class_item(class_record)
  local start_line = class_record.line - 1
  local start_character = class_record.column - 1
  return {
    name = class_record.name,
    detail = class_record.module,
    kind = vim.lsp.protocol.SymbolKind.Class,
    uri = vim.uri_from_fname(class_record.filename),
    range = {
      start = { line = start_line, character = start_character },
      ['end'] = {
        line = start_line,
        character = start_character + #class_record.name,
      },
    },
    selectionRange = {
      start = { line = start_line, character = start_character },
      ['end'] = {
        line = start_line,
        character = start_character + #class_record.name,
      },
    },
  }
end

local function open_indexed_python_hierarchy(direction, fallback, session, context)
  local bufnr = context.bufnr
  local filename = context.filename
  local line_number = context.line_number
  local root = context.root
  local index_status = python_hierarchy_index.status(root)
  if index_status.status == 'idle' or index_status.status == 'loading' then
    vim.notify('Preparing Python class index…', vim.log.levels.INFO)
  end

  python_hierarchy_index.ensure(root, function(index_document, error_message)
    if session:is_closed() then
      return
    end
    if error_message ~= '' then
      fallback()
      return
    end
    local root_class = python_hierarchy_index.find_class(
      index_document,
      filename,
      line_number
    )
    if not root_class then
      fallback()
      return
    end

    local indexed_records = direction == 'subtypes'
        and python_hierarchy_index.derived(index_document, root_class)
      or python_hierarchy_index.supertypes(index_document, root_class)
    local hierarchy_records = vim.tbl_map(function(indexed_record)
      return {
        depth = indexed_record.depth,
        item = indexed_class_item(indexed_record.class_record),
      }
    end, indexed_records)
    local title = direction == 'subtypes' and 'Derived Classes' or 'Base Classes'
    open_location_picker(
      title,
      hierarchy_records,
      hierarchy_entry(root, direction),
      session
    )
  end)
end

local function open_indexed_python_implementations(fallback, session, context)
  local bufnr = context.bufnr
  local filename = context.filename
  local line_number = context.line_number
  local root = context.root
  local index_status = python_hierarchy_index.status(root)
  if index_status.status == 'idle' or index_status.status == 'loading' then
    vim.notify('Preparing Python class index…', vim.log.levels.INFO)
  end

  python_hierarchy_index.ensure(root, function(index_document, error_message)
    if session:is_closed() then
      return
    end
    if error_message ~= '' then
      fallback()
      return
    end
    local root_class = python_hierarchy_index.find_class(
      index_document,
      filename,
      line_number
    )
    local method_record = python_hierarchy_index.find_method(root_class, line_number)
    if not method_record then
      local symbol_class = python_hierarchy_index.find_symbol_class(
        index_document,
        filename,
        line_number,
        context.column_number,
        context.root_name
      )
      if symbol_class then
        local class_implementations = vim.tbl_map(function(indexed_record)
          local implementation_class = indexed_record.class_record
          return {
            filename = implementation_class.filename,
            lnum = implementation_class.line,
            col = implementation_class.column,
            text = implementation_class.name,
            name = implementation_class.name,
          }
        end, python_hierarchy_index.derived(index_document, symbol_class))
        open_location_picker(
          'Implementations',
          class_implementations,
          implementation_entry(root),
          session
        )
        return
      end
      fallback()
      return
    end

    local indexed_implementations = python_hierarchy_index.implementations(
      index_document,
      root_class,
      method_record
    )
    local implementation_records = vim.tbl_map(function(indexed_record)
      local implementation_class = indexed_record.class_record
      local implementation_method = indexed_record.method_record
      return {
        filename = implementation_class.filename,
        lnum = implementation_method.line,
        col = implementation_method.column,
        text = implementation_method.name,
        name = implementation_class.name .. '.' .. implementation_method.name,
      }
    end, indexed_implementations)
    open_location_picker(
      'Implementations',
      implementation_records,
      implementation_entry(root),
      session
    )
  end)
end

local function collect_implementation_records(request_results, current_location)
  local implementation_records = {}
  local visited_locations = {}
  for client_id, response in pairs(request_results) do
    local client = vim.lsp.get_client_by_id(client_id)
    if response.err then
      vim.notify(response.err.message, vim.log.levels.WARN)
    elseif client and response.result then
      local locations = vim.islist(response.result) and response.result or { response.result }
      local location_items = vim.lsp.util.locations_to_items(
        locations,
        client.offset_encoding
      )
      for _, location_item in ipairs(location_items) do
        local location_key = ('%s:%d:%d'):format(
          location_item.filename,
          location_item.lnum,
          location_item.col
        )
        local is_current_definition = location_item.filename == current_location.filename
          and location_item.lnum == current_location.lnum
        if not is_current_definition and not visited_locations[location_key] then
          visited_locations[location_key] = true
          table.insert(implementation_records, {
            filename = location_item.filename,
            lnum = location_item.lnum,
            col = location_item.col,
            text = location_item.text,
            name = implementation_name(
              location_item.filename,
              location_item.lnum,
              location_item.col,
              location_item.text
            ),
          })
        end
      end
    end
  end
  table.sort(implementation_records, function(left_record, right_record)
    if left_record.name ~= right_record.name then
      return left_record.name < right_record.name
    end
    return left_record.filename < right_record.filename
  end)
  return implementation_records
end

local function open_implementation_subtypes(session, context)
  local bufnr = context.bufnr
  local window = context.window
  local method = 'textDocument/implementation'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if #clients == 0 then
    session:fail('unsupported by active LSP')
    return
  end

  local root_name = context.root_name
  local root = context.root
  local cancel_subtypes = vim.lsp.buf_request_all(bufnr, method, function(client)
    return vim.lsp.util.make_position_params(window, client.offset_encoding)
  end, function(request_results)
    if session:is_closed() then
      return
    end
    local visited_items = {}
    local subtype_records = {}
    for _, response in pairs(request_results) do
      if response.err then
        vim.notify(response.err.message, vim.log.levels.WARN)
      elseif response.result then
        for _, location in ipairs(normalized_locations(response.result)) do
          local class_item = python_class_item(location)
          if class_item and class_item.name ~= root_name then
            local item_key = hierarchy_item_key(class_item)
            if not visited_items[item_key] then
              visited_items[item_key] = true
              table.insert(subtype_records, { depth = 1, item = class_item })
            end
          end
        end
      end
    end
    table.sort(subtype_records, function(left_record, right_record)
      return left_record.item.name < right_record.item.name
    end)
    open_location_picker(
      'Derived Classes',
      subtype_records,
      hierarchy_entry(root, 'subtypes'),
      session
    )
  end)
  session:add_cancel(cancel_subtypes)
end

local function show_python_supertypes(client, root_item, bufnr, session)
  local root = project.for_buffer(bufnr)
  local visited_items = { [hierarchy_item_key(root_item)] = true }
  local supertype_records = {}
  local pending_request_count = 0
  local picker_opened = false

  local function finish_if_complete()
    if pending_request_count ~= 0 or picker_opened then
      return
    end
    picker_opened = true
    table.sort(supertype_records, function(left_record, right_record)
      if left_record.depth ~= right_record.depth then
        return left_record.depth < right_record.depth
      end
      return left_record.item.name < right_record.item.name
    end)
    open_location_picker(
      'Base Classes',
      supertype_records,
      hierarchy_entry(root, 'supertypes'),
      session
    )
  end

  local function resolve_bases(class_item, depth)
    for _, base_reference in ipairs(python_base_references(class_item)) do
      pending_request_count = pending_request_count + 1
      local request_succeeded, request_id = client:request(
        'textDocument/definition',
        {
          textDocument = { uri = class_item.uri },
          position = base_reference.position,
        },
        function(request_error, definition_result)
          if session:is_closed() then
            return
          end
          if request_error then
            vim.notify(request_error.message, vim.log.levels.WARN)
          else
            for _, location in ipairs(normalized_locations(definition_result)) do
              local base_item = python_class_item(location)
              if base_item then
                local item_key = hierarchy_item_key(base_item)
                if not visited_items[item_key] then
                  visited_items[item_key] = true
                  table.insert(supertype_records, { depth = depth, item = base_item })
                  session:update(
                    supertype_records,
                    ('querying… %d classes available'):format(#supertype_records)
                  )
                  resolve_bases(base_item, depth + 1)
                end
              end
            end
          end
          pending_request_count = pending_request_count - 1
          finish_if_complete()
        end,
        bufnr
      )
      if request_succeeded and request_id then
        session:add_cancel(function()
          if client.requests and client.requests[request_id] then
            client:cancel_request(request_id)
          end
        end)
      end
      if not request_succeeded then
        pending_request_count = pending_request_count - 1
      end
    end
  end

  resolve_bases(root_item, 1)
  finish_if_complete()
end

local function open_python_supertypes(session, context)
  local bufnr = context.bufnr
  local window = context.window
  local method = 'textDocument/definition'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  local client = clients[1]
  if not client then
    session:fail('unsupported by active LSP')
    return
  end

  local request_succeeded, request_id = client:request(
    method,
    vim.lsp.util.make_position_params(window, client.offset_encoding),
    function(request_error, definition_result)
      if session:is_closed() then
        return
      end
      if request_error then
        session:fail(request_error.message)
        return
      end
      local definition_locations = normalized_locations(definition_result)
      local root_item = first_python_class_item(definition_locations)
      if not root_item then
        session:finish({})
        return
      end
      show_python_supertypes(client, root_item, bufnr, session)
    end,
    bufnr
  )
  if request_succeeded and request_id then
    session:add_cancel(function()
      if client.requests and client.requests[request_id] then
        client:cancel_request(request_id)
      end
    end)
  end
  if not request_succeeded then
    session:fail('failed to request class definition')
  end
end

function M.open_subtypes()
  local context = current_query_context()
  local session = new_location_picker(
    'Derived Classes',
    hierarchy_entry(context.root, 'subtypes')
  )
  if vim.bo[context.bufnr].filetype == 'python' then
    open_indexed_python_hierarchy('subtypes', function()
      open_implementation_subtypes(session, context)
    end, session, context)
    return
  end
  local hierarchy_clients = vim.lsp.get_clients({
    bufnr = context.bufnr,
    method = 'textDocument/prepareTypeHierarchy',
  })
  if #hierarchy_clients > 0 then
    open_hierarchy('subtypes', session, context)
  else
    open_implementation_subtypes(session, context)
  end
end

function M.open_supertypes()
  local context = current_query_context()
  local session = new_location_picker(
    'Base Classes',
    hierarchy_entry(context.root, 'supertypes')
  )
  if vim.bo[context.bufnr].filetype == 'python' then
    open_indexed_python_hierarchy('supertypes', function()
      open_python_supertypes(session, context)
    end, session, context)
    return
  end
  local hierarchy_clients = vim.lsp.get_clients({
    bufnr = context.bufnr,
    method = 'textDocument/prepareTypeHierarchy',
  })
  if #hierarchy_clients > 0 then
    open_hierarchy('supertypes', session, context)
  else
    session:fail('unsupported by active LSP')
  end
end

local function open_lsp_implementations(session, context)
  local bufnr = context.bufnr
  local window = context.window
  local method = 'textDocument/implementation'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if #clients == 0 then
    session:fail('unsupported by active LSP')
    return
  end

  local current_location = {
    filename = context.filename,
    lnum = context.line_number,
  }
  local root = context.root
  local cancel_implementations = vim.lsp.buf_request_all(bufnr, method, function(client)
    return vim.lsp.util.make_position_params(window, client.offset_encoding)
  end, function(request_results)
    if session:is_closed() then
      return
    end
    local implementation_records = collect_implementation_records(
      request_results,
      current_location
    )
    open_location_picker(
      'Implementations',
      implementation_records,
      implementation_entry(root),
      session
    )
  end)
  session:add_cancel(cancel_implementations)
end

function M.open_implementations()
  local context = current_query_context()
  local session = new_location_picker(
    'Implementations',
    implementation_entry(context.root)
  )
  if vim.bo[context.bufnr].filetype == 'python' then
    open_indexed_python_implementations(function()
      open_lsp_implementations(session, context)
    end, session, context)
    return
  end
  open_lsp_implementations(session, context)
end

return M
