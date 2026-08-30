-- Python hierarchy paths: background-index queries and Python source parsing.
-- Falls back to live LSP definition requests when the index cannot resolve the
-- symbol under the cursor.
local core = require('config.type_hierarchy.core')
local python_hierarchy_index = require('config.python.hierarchy_index')

local M = {}

-- Build a standard type-hierarchy item from an LSP location pointing at a
-- Python `class` line; returns nil when the location is not a class.
function M.class_item(location)
  local filename = vim.uri_to_fname(location.uri)
  local source_lines = core.file_lines(filename)
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

function M.first_class_item(locations)
  for _, location in ipairs(locations) do
    local class_item = M.class_item(location)
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

-- Positions of the base-class references in a class item's superclasses list,
-- parsed from source with Treesitter.
function M.base_references(class_item)
  local filename = vim.uri_to_fname(class_item.uri)
  local source_lines = core.file_lines(filename)
  local source = table.concat(source_lines, '\n')
  local syntax_tree = core.parse_source(source, 'python')
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
  local references = {}
  for child_index = 0, superclasses:named_child_count() - 1 do
    local base_expression = superclasses:named_child(child_index)
    local reference_node = base_expression and base_reference_node(base_expression) or nil
    if reference_node then
      local start_row, start_column = reference_node:range()
      table.insert(references, {
        position = { line = start_row, character = start_column },
      })
    end
  end
  return references
end

-- Class-qualified method name for a Python definition line, found by scanning
-- upwards for an enclosing class with less indentation.
function M.implementation_name(filename, line_number, fallback_text)
  local source_lines = core.file_lines(filename)
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

-- Load the background class index for the context root and hand it to the
-- handler; any load failure or closed session routes to the fallback instead.
local function with_index(session, context, fallback, handler)
  local index_status = python_hierarchy_index.status(context.root)
  if index_status.status == 'idle' or index_status.status == 'loading' then
    vim.notify('Preparing Python class index…', vim.log.levels.INFO)
  end

  python_hierarchy_index.ensure(context.root, function(index_document, error_message)
    if session:is_closed() then
      return
    end
    if error_message ~= '' then
      fallback()
      return
    end
    handler(index_document)
  end)
end

function M.open_indexed_hierarchy(direction, fallback, session, context)
  with_index(session, context, fallback, function(index_document)
    local root_class = python_hierarchy_index.find_class(
      index_document,
      context.filename,
      context.line_number
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
    core.open_location_picker(
      title,
      hierarchy_records,
      core.hierarchy_entry(context.root, direction),
      session
    )
  end)
end

function M.open_indexed_implementations(fallback, session, context)
  with_index(session, context, fallback, function(index_document)
    local root_class = python_hierarchy_index.find_class(
      index_document,
      context.filename,
      context.line_number
    )
    local method_record = python_hierarchy_index.find_method(root_class, context.line_number)
    if not method_record then
      local symbol_class = python_hierarchy_index.find_symbol_class(
        index_document,
        context.filename,
        context.line_number,
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
        core.open_location_picker(
          'Implementations',
          class_implementations,
          core.implementation_entry(context.root),
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
    core.open_location_picker(
      'Implementations',
      implementation_records,
      core.implementation_entry(context.root),
      session
    )
  end)
end

-- Walk the base-class graph through live definition requests, used when the
-- background index cannot resolve the symbol under the cursor.
local function show_supertypes(client, root_item, bufnr, session)
  local walk = core.hierarchy_walk(root_item, 'supertypes', bufnr, session, 'Base Classes')

  local function resolve_bases(class_item, depth)
    for _, base_reference in ipairs(M.base_references(class_item)) do
      walk:begin_request()
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
            for _, location in ipairs(core.normalized_locations(definition_result)) do
              local base_item = M.class_item(location)
              if base_item and walk:record(base_item, depth) then
                resolve_bases(base_item, depth + 1)
              end
            end
          end
          walk:finish_request()
        end,
        bufnr
      )
      if request_succeeded and request_id then
        session:add_cancel(core.cancel_request(client, request_id))
      end
      if not request_succeeded then
        walk:finish_request()
      end
    end
  end

  resolve_bases(root_item, 1)
  walk:publish_if_drained()
end

function M.open_supertypes(session, context)
  local bufnr = context.bufnr
  local method = 'textDocument/definition'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  local client = clients[1]
  if not client then
    session:fail('unsupported by active LSP')
    return
  end

  local request_succeeded, request_id = client:request(
    method,
    vim.lsp.util.make_position_params(context.window, client.offset_encoding),
    function(request_error, definition_result)
      if session:is_closed() then
        return
      end
      if request_error then
        session:fail(request_error.message)
        return
      end
      local definition_locations = core.normalized_locations(definition_result)
      local root_item = M.first_class_item(definition_locations)
      if not root_item then
        session:finish({})
        return
      end
      show_supertypes(client, root_item, bufnr, session)
    end,
    bufnr
  )
  if request_succeeded and request_id then
    session:add_cancel(core.cancel_request(client, request_id))
  end
  if not request_succeeded then
    session:fail('failed to request class definition')
  end
end

return M
