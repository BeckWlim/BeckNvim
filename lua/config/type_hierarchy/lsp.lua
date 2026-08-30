-- Live LSP-request hierarchy paths: the standard type-hierarchy protocol
-- (clangd), implementation requests, and class-qualified result naming.
local core = require('config.type_hierarchy.core')
local python = require('config.type_hierarchy.python')

local M = {}

local hierarchy_methods = {
  subtypes = 'typeHierarchy/subtypes',
  supertypes = 'typeHierarchy/supertypes',
}

local hierarchy_titles = {
  subtypes = 'Derived Classes',
  supertypes = 'Base Classes',
}

local function show_hierarchy(client, root_item, direction, bufnr, session)
  local walk = core.hierarchy_walk(root_item, direction, bufnr, session, hierarchy_titles[direction])

  local function request_related_items(parent_item, depth)
    walk:begin_request()
    local request_succeeded, request_id = client:request(
      hierarchy_methods[direction],
      { item = parent_item },
      function(request_error, related_items)
        if session:is_closed() then
          return
        end
        if request_error then
          vim.notify(request_error.message, vim.log.levels.WARN)
        elseif related_items then
          for _, related_item in ipairs(related_items) do
            if walk:record(related_item, depth) then
              request_related_items(related_item, depth + 1)
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

function M.open_hierarchy(direction, session, context)
  local bufnr = context.bufnr
  local prepare_method = 'textDocument/prepareTypeHierarchy'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = prepare_method })
  if #clients == 0 then
    session:fail('unsupported by active LSP')
    return
  end

  local cancel_prepare = vim.lsp.buf_request_all(bufnr, prepare_method, function(client)
    return vim.lsp.util.make_position_params(context.window, client.offset_encoding)
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

-- Owner-qualified method name for a C++ implementation location, resolved
-- through Treesitter when the cursor line does not name the owner itself.
local function cpp_implementation_name(filename, line_number, column_number, fallback_text)
  local method_name = fallback_text:match('([%a_~][%w_:~]*)%s*%(')
  if not method_name then
    return vim.trim(fallback_text)
  end
  if method_name:find('::', 1, true) then
    return method_name
  end

  local source_lines = core.file_lines(filename)
  local source = table.concat(source_lines, '\n')
  local syntax_tree = core.parse_source(source, 'cpp')
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
    return python.implementation_name(filename, line_number, fallback_text)
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

-- Derived classes through implementation requests, for servers without the
-- type-hierarchy protocol and as the Python index fallback.
function M.open_implementation_subtypes(session, context)
  local bufnr = context.bufnr
  local method = 'textDocument/implementation'
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if #clients == 0 then
    session:fail('unsupported by active LSP')
    return
  end

  local cancel_subtypes = vim.lsp.buf_request_all(bufnr, method, function(client)
    return vim.lsp.util.make_position_params(context.window, client.offset_encoding)
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
        for _, location in ipairs(core.normalized_locations(response.result)) do
          local class_item = python.class_item(location)
          if class_item and class_item.name ~= context.root_name then
            local item_key = core.hierarchy_item_key(class_item)
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
    core.open_location_picker(
      'Derived Classes',
      subtype_records,
      core.hierarchy_entry(context.root, 'subtypes'),
      session
    )
  end)
  session:add_cancel(cancel_subtypes)
end

function M.open_implementations(session, context)
  local bufnr = context.bufnr
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
  local cancel_implementations = vim.lsp.buf_request_all(bufnr, method, function(client)
    return vim.lsp.util.make_position_params(context.window, client.offset_encoding)
  end, function(request_results)
    if session:is_closed() then
      return
    end
    local implementation_records = collect_implementation_records(
      request_results,
      current_location
    )
    core.open_location_picker(
      'Implementations',
      implementation_records,
      core.implementation_entry(context.root),
      session
    )
  end)
  session:add_cancel(cancel_implementations)
end

return M
