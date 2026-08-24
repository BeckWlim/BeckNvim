local M = {}

local function sorted_items(items_by_key)
  local items = vim.tbl_values(items_by_key)
  table.sort(items, function(left_item, right_item)
    if left_item.filename ~= right_item.filename then
      return left_item.filename < right_item.filename
    end
    if left_item.lnum ~= right_item.lnum then
      return left_item.lnum < right_item.lnum
    end
    return left_item.col < right_item.col
  end)
  return items
end

local function location_key(location_item)
  return ('%s:%d:%d'):format(
    location_item.filename,
    location_item.lnum,
    location_item.col
  )
end

local function is_non_reference_identifier(identifier_node)
  local parent_node = identifier_node:parent()
  if not parent_node then
    return false
  end
  for _, field_name in ipairs({ 'attribute', 'name' }) do
    local field_nodes = parent_node:field(field_name)
    for _, field_node in ipairs(field_nodes) do
      if field_node:id() == identifier_node:id() then
        return true
      end
    end
  end
  return false
end

local function python_local_reference_items(
  source_buffer,
  source_filename,
  cursor_row,
  cursor_column,
  skip_source_line
)
  if vim.bo[source_buffer].filetype ~= 'python' then
    return {}
  end

  local syntax_tree
  local parse_succeeded = pcall(function()
    local parser = vim.treesitter.get_parser(source_buffer, 'python')
    local parsed_trees = parser:parse()
    syntax_tree = parsed_trees[1]
  end)
  if not parse_succeeded or not syntax_tree then
    return {}
  end

  local root_node = syntax_tree:root()
  local cursor_node = root_node:named_descendant_for_range(
    cursor_row,
    cursor_column,
    cursor_row,
    cursor_column
  )
  while cursor_node and cursor_node:type() ~= 'identifier' do
    cursor_node = cursor_node:parent()
  end
  if not cursor_node then
    return {}
  end

  local scope_node = cursor_node:parent()
  while scope_node
    and scope_node:type() ~= 'function_definition'
    and scope_node:type() ~= 'lambda'
  do
    scope_node = scope_node:parent()
  end
  if not scope_node then
    return {}
  end

  local symbol_name = vim.treesitter.get_node_text(cursor_node, source_buffer)
  if type(symbol_name) ~= 'string' or symbol_name == '' then
    return {}
  end

  local source_lines = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
  local local_items = {}
  local nested_scope_types = {
    class_definition = true,
    function_definition = true,
    lambda = true,
  }

  local function collect_identifiers(node)
    if node:id() ~= scope_node:id() and nested_scope_types[node:type()] then
      return
    end
    if node:type() == 'identifier'
      and not is_non_reference_identifier(node)
      and vim.treesitter.get_node_text(node, source_buffer) == symbol_name
    then
      local start_row, start_column = node:range()
      if not skip_source_line or start_row ~= cursor_row then
        table.insert(local_items, {
          filename = source_filename,
          lnum = start_row + 1,
          col = start_column + 1,
          text = source_lines[start_row + 1] or symbol_name,
        })
      end
      return
    end
    for child_node in node:iter_children() do
      if child_node:named() then
        collect_identifiers(child_node)
      end
    end
  end

  collect_identifiers(scope_node)
  return local_items
end

local function open_location_query(query)
  local telescope_config = require('telescope.config').values
  local make_entry = require('telescope.make_entry')
  local query_picker = require('config.query_picker')
  local source_buffer = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  local source_cursor = vim.api.nvim_win_get_cursor(source_window)
  local source_line = source_cursor[1]
  local source_row = source_line - 1
  local source_column = source_cursor[2]
  local source_filename = vim.api.nvim_buf_get_name(source_buffer)
  local items_by_key = {}
  local provisional_keys = {}
  local pending_request_count = 0
  local error_count = 0
  local picker_options = {}
  local session = query_picker.open({
    title = query.title,
    picker_options = picker_options,
    entry_maker = make_entry.gen_from_quickfix(picker_options),
    previewer = telescope_config.qflist_previewer(picker_options),
    sorter = telescope_config.generic_sorter(picker_options),
  })

  local function clear_provisional_items()
    for provisional_key in pairs(provisional_keys) do
      items_by_key[provisional_key] = nil
    end
    provisional_keys = {}
  end

  if query.fast_document_highlights then
    local local_items = python_local_reference_items(
      source_buffer,
      source_filename,
      source_row,
      source_column,
      query.skip_source_line
    )
    for _, local_item in ipairs(local_items) do
      local local_key = location_key(local_item)
      items_by_key[local_key] = local_item
      provisional_keys[local_key] = true
    end
    if #local_items > 0 then
      session:update(
        sorted_items(items_by_key),
        ('querying… %d local candidates available'):format(#local_items)
      )
    end
  end

  local function merge_locations(locations, offset_encoding)
    local location_items = vim.lsp.util.locations_to_items(locations, offset_encoding)
    for _, location_item in ipairs(location_items) do
      local is_source_line = location_item.filename == source_filename
        and location_item.lnum == source_line
      if not query.skip_source_line or not is_source_line then
        items_by_key[location_key(location_item)] = location_item
      end
    end
  end

  local function finish_request()
    pending_request_count = pending_request_count - 1
    local current_items = sorted_items(items_by_key)
    if pending_request_count == 0 then
      if error_count > 0 and #current_items == 0 then
        session:fail(('query failed (%d errors)'):format(error_count))
      else
        session:finish(current_items)
      end
      return
    end
    session:update(current_items, ('querying… %d results available'):format(#current_items))
  end

  local function collect_location_responses(response_documents)
    if session:is_closed() then
      return
    end
    for client_id, response_document in pairs(response_documents) do
      local client = vim.lsp.get_client_by_id(client_id)
      if response_document.err then
        error_count = error_count + 1
      elseif client then
        clear_provisional_items()
        if response_document.result then
          local response_locations = vim.islist(response_document.result)
              and response_document.result
            or { response_document.result }
          merge_locations(response_locations, client.offset_encoding)
        end
      end
    end
    finish_request()
  end

  local function collect_highlight_responses(response_documents)
    if session:is_closed() then
      return
    end
    local source_uri = vim.uri_from_bufnr(source_buffer)
    for client_id, response_document in pairs(response_documents) do
      local client = vim.lsp.get_client_by_id(client_id)
      if response_document.err then
        error_count = error_count + 1
      elseif client then
        clear_provisional_items()
        if response_document.result then
          local highlight_locations = vim.tbl_map(function(document_highlight)
            return {
              uri = source_uri,
              range = document_highlight.range,
            }
          end, response_document.result)
          merge_locations(highlight_locations, client.offset_encoding)
        end
      end
    end
    finish_request()
  end

  local function position_params(client)
    local base_params = vim.lsp.util.make_position_params(source_window, client.offset_encoding)
    if query.method == 'textDocument/references' then
      return vim.tbl_extend('force', base_params, {
        context = { includeDeclaration = true },
      })
    end
    return base_params
  end

  vim.schedule(function()
    if session:is_closed() then
      return
    end

    local primary_clients = vim.lsp.get_clients({
      bufnr = source_buffer,
      method = query.method,
    })
    local highlight_clients = query.fast_document_highlights
        and vim.lsp.get_clients({
          bufnr = source_buffer,
          method = 'textDocument/documentHighlight',
        })
      or {}

    if #primary_clients == 0 and #highlight_clients == 0 then
      session:fail('unsupported by active LSP')
      return
    end

    if #highlight_clients > 0 then
      pending_request_count = pending_request_count + 1
      local cancel_highlights = vim.lsp.buf_request_all(
        source_buffer,
        'textDocument/documentHighlight',
        position_params,
        collect_highlight_responses
      )
      session:add_cancel(cancel_highlights)
    end

    if #primary_clients > 0 then
      pending_request_count = pending_request_count + 1
      local cancel_primary = vim.lsp.buf_request_all(
        source_buffer,
        query.method,
        position_params,
        collect_location_responses
      )
      session:add_cancel(cancel_primary)
    end
  end)
end

function M.references()
  open_location_query({
    method = 'textDocument/references',
    title = 'References',
    fast_document_highlights = true,
    skip_source_line = true,
  })
end

function M.implementations()
  open_location_query({
    method = 'textDocument/implementation',
    title = 'Implementations',
  })
end

function M.definitions()
  open_location_query({
    method = 'textDocument/definition',
    title = 'Definitions',
  })
end

function M.declarations()
  open_location_query({
    method = 'textDocument/declaration',
    title = 'Declarations',
  })
end

function M.type_definitions()
  open_location_query({
    method = 'textDocument/typeDefinition',
    title = 'Type Definitions',
  })
end

return M
