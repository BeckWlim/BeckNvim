local M = {}

local context_line_budget = 6

local structural_node_types = {
  arrow_function = true,
  class_declaration = true,
  class_definition = true,
  class_specifier = true,
  closure_expression = true,
  constructor_declaration = true,
  constructor_definition = true,
  destructor_declaration = true,
  destructor_definition = true,
  enum_item = true,
  func_literal = true,
  function_declaration = true,
  function_definition = true,
  function_item = true,
  generator_function_declaration = true,
  impl_item = true,
  interface_declaration = true,
  method_declaration = true,
  method_definition = true,
  mod_item = true,
  namespace_definition = true,
  struct_item = true,
  trait_item = true,
  union_item = true,
}

local function range_height(context_range)
  return context_range[3] - context_range[1] + (context_range[4] == 0 and 0 or 1)
end

local function context_height(context_ranges)
  local total_height = 0
  for _, context_range in ipairs(context_ranges) do
    total_height = total_height + range_height(context_range)
  end
  return total_height
end

local function context_chunks(context_ranges, context_lines)
  local chunks = {}
  local next_line_index = 1
  for range_index, context_range in ipairs(context_ranges) do
    local chunk_height = range_height(context_range)
    local chunk_lines = {}
    for _ = 1, chunk_height do
      chunk_lines[#chunk_lines + 1] = context_lines[next_line_index]
      next_line_index = next_line_index + 1
    end
    chunks[range_index] = {
      height = chunk_height,
      lines = chunk_lines,
      range = context_range,
    }
  end
  return chunks
end

local function structural_header(source_line)
  return source_line:match('^%s*class%s+') ~= nil
    or source_line:match('^%s*async%s+def%s+') ~= nil
    or source_line:match('^%s*def%s+') ~= nil
    or source_line:match('^%s*local%s+function%s+') ~= nil
    or source_line:match('^%s*function%s+') ~= nil
end

local function structural_context_classifier(source_buffer)
  local syntax_roots = {}
  local parse_succeeded = pcall(function()
    local parser = vim.treesitter.get_parser(source_buffer)
    parser:parse()
    parser:for_each_tree(function(syntax_tree)
      syntax_roots[#syntax_roots + 1] = syntax_tree:root()
    end)
  end)

  if not parse_succeeded then
    syntax_roots = {}
  end

  return function(context_range)
    local context_row = context_range[1]
    local source_line = vim.api.nvim_buf_get_lines(
      source_buffer,
      context_row,
      context_row + 1,
      false
    )[1] or ''
    if structural_header(source_line) then
      return true
    end

    local first_nonblank_byte = source_line:find('%S')
    if not first_nonblank_byte then
      return false
    end
    local context_column = first_nonblank_byte - 1

    for _, syntax_root in ipairs(syntax_roots) do
      local root_start_row, _, root_end_row = syntax_root:range()
      if context_row >= root_start_row and context_row <= root_end_row then
        local context_node = syntax_root:named_descendant_for_range(
          context_row,
          context_column,
          context_row,
          context_column
        )
        while context_node do
          local node_start_row = context_node:range()
          if node_start_row ~= context_row then
            break
          end
          if structural_node_types[context_node:type()] then
            return true
          end
          context_node = context_node:parent()
        end
      end
    end
    return false
  end
end

local function captured_node(nodes)
  if type(nodes) == 'table' then
    return nodes[#nodes]
  end
  return nodes
end

local function context_start(query, context_node, source_buffer)
  local node_start_row, node_start_column, node_end_row = context_node:range()
  for _, match in query:iter_matches(
    context_node,
    source_buffer,
    node_start_row,
    node_end_row + 1,
    { max_start_depth = 0 }
  ) do
    local matches_context_node = false
    local captured_start_row = node_start_row
    local captured_start_column = node_start_column
    for capture_id, nodes in pairs(match) do
      local matched_node = captured_node(nodes)
      local capture_name = query.captures[capture_id]
      if capture_name == 'context' and matched_node:id() == context_node:id() then
        matches_context_node = true
      elseif capture_name == 'context.start' then
        captured_start_row, captured_start_column = matched_node:range()
      end
    end
    if matches_context_node then
      return captured_start_row, captured_start_column
    end
  end
end

local function structural_node_label(source_buffer, structural_node)
  local name_nodes = structural_node:field('name')
  local name_node = name_nodes[1]
  if name_node then
    local node_name = vim.treesitter.get_node_text(name_node, source_buffer)
    if type(node_name) == 'string' and node_name ~= '' then
      return node_name
    end
  end

  local node_start_row = structural_node:range()
  local source_line = vim.api.nvim_buf_get_lines(
    source_buffer,
    node_start_row,
    node_start_row + 1,
    false
  )[1] or ''
  return vim.trim(source_line):gsub('%s+', ' ')
end

function M.prioritize(context_ranges, context_lines, line_budget, is_structural_context)
  if context_height(context_ranges) <= line_budget then
    return context_ranges, context_lines
  end

  local chunks = context_chunks(context_ranges, context_lines)
  local selected_indices = {}
  local selected_height = 0

  local function select_chunk(chunk_index)
    if selected_indices[chunk_index] then
      return
    end
    selected_indices[chunk_index] = true
    selected_height = selected_height + chunks[chunk_index].height
  end

  for chunk_index, chunk in ipairs(chunks) do
    if is_structural_context(chunk.range) then
      select_chunk(chunk_index)
    end
  end

  if #chunks > 0 then
    select_chunk(#chunks)
  end

  local remaining_lines = math.max(0, line_budget - selected_height)
  for chunk_index = #chunks - 1, 1, -1 do
    local chunk = chunks[chunk_index]
    if not selected_indices[chunk_index] and chunk.height <= remaining_lines then
      select_chunk(chunk_index)
      remaining_lines = remaining_lines - chunk.height
    end
  end

  local prioritized_ranges = {}
  local prioritized_lines = {}
  for chunk_index, chunk in ipairs(chunks) do
    if selected_indices[chunk_index] then
      prioritized_ranges[#prioritized_ranges + 1] = chunk.range
      vim.list_extend(prioritized_lines, chunk.lines)
    end
  end
  return prioritized_ranges, prioritized_lines
end

function M.go_to_nearest_context()
  local source_window = vim.api.nvim_get_current_win()
  local source_buffer = vim.api.nvim_win_get_buf(source_window)
  local source_cursor = vim.api.nvim_win_get_cursor(source_window)
  local cursor_row = source_cursor[1] - 1
  local cursor_column = source_cursor[2]
  local cursor_range = { cursor_row, cursor_column, cursor_row, cursor_column + 1 }

  local parser
  local parser_available = pcall(function()
    parser = vim.treesitter.get_parser(source_buffer)
    parser:parse()
  end)
  if not parser_available or not parser then
    vim.notify('No syntax context is available for this buffer', vim.log.levels.INFO)
    return
  end

  local language_tree = parser:language_for_range(cursor_range)
  local syntax_tree = language_tree:tree_for_range(cursor_range, { ignore_injections = true })
  if not syntax_tree then
    vim.notify('No enclosing syntax context found', vim.log.levels.INFO)
    return
  end

  local query_succeeded, context_query = pcall(
    vim.treesitter.query.get,
    language_tree:lang(),
    'context'
  )
  if not query_succeeded or not context_query then
    vim.notify('No syntax context query is available for this language', vim.log.levels.INFO)
    return
  end

  local syntax_root = syntax_tree:root()
  local enclosing_node = syntax_root:named_descendant_for_range(
    cursor_row,
    cursor_column,
    cursor_row,
    cursor_column
  )
  while enclosing_node do
    local node_start_row = enclosing_node:range()
    if node_start_row < cursor_row then
      local context_row, context_column = context_start(
        context_query,
        enclosing_node,
        source_buffer
      )
      if context_row then
        vim.cmd([[normal! m']])
        vim.api.nvim_win_set_cursor(source_window, { context_row + 1, context_column })
        return
      end
    end
    enclosing_node = enclosing_node:parent()
  end

  vim.notify('No enclosing syntax context found', vim.log.levels.INFO)
end

function M.structural_context_labels(source_buffer, source_row, source_column)
  local source_range = { source_row, source_column, source_row, source_column + 1 }
  local parser
  local parser_available = pcall(function()
    parser = vim.treesitter.get_parser(source_buffer)
    parser:parse()
  end)
  if not parser_available or not parser then
    return {}
  end

  local language_tree = parser:language_for_range(source_range)
  local syntax_tree = language_tree:tree_for_range(source_range, { ignore_injections = true })
  if not syntax_tree then
    return {}
  end

  local syntax_root = syntax_tree:root()
  local enclosing_node = syntax_root:named_descendant_for_range(
    source_row,
    source_column,
    source_row,
    source_column
  )
  local labels = {}
  while enclosing_node do
    if structural_node_types[enclosing_node:type()] then
      local context_label = structural_node_label(source_buffer, enclosing_node)
      if context_label ~= '' then
        table.insert(labels, 1, context_label)
      end
    end
    enclosing_node = enclosing_node:parent()
  end
  return labels
end

function M.setup()
  require('treesitter-context').setup({
    enable = true,
    max_lines = 0,
    multiline_threshold = 2,
    mode = 'cursor',
  })

  local context_provider = require('treesitter-context.context')
  local get_context = context_provider.get
  context_provider.get = function(window)
    local context_ranges, context_lines = get_context(window)
    if not context_ranges or not context_lines then
      return context_ranges, context_lines
    end
    if context_height(context_ranges) <= context_line_budget then
      return context_ranges, context_lines
    end

    local source_window = window or vim.api.nvim_get_current_win()
    local source_buffer = vim.api.nvim_win_get_buf(source_window)
    return M.prioritize(
      context_ranges,
      context_lines,
      context_line_budget,
      structural_context_classifier(source_buffer)
    )
  end
end

return M
