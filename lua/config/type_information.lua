local M = {}

local active_session
local highlight_namespace = vim.api.nvim_create_namespace('type_information')

local function display_path(filename)
  local relative_path = vim.fs.relpath(vim.fn.getcwd(), filename)
  if relative_path then
    return relative_path
  end
  return vim.fn.fnamemodify(filename, ':~')
end

local function plain_hover_lines(hover_contents)
  if hover_contents == nil then
    return {}, {}
  end
  local converted_lines = vim.lsp.util.convert_input_to_markdown_lines(hover_contents)
  local line_records = {}
  local inside_code_fence = false
  for _, converted_line in ipairs(converted_lines) do
    if converted_line:match('^%s*```') then
      inside_code_fence = not inside_code_fence
    elseif not inside_code_fence and converted_line:match('^%s*[-*_][%s%-%*_]*$') then
      -- Markdown separators are presentation metadata, not hover content.
    else
      local without_heading = converted_line:gsub('^%s*#+%s*', '')
      local without_links = without_heading:gsub('%[([^%]]+)%]%([^%)]+%)', '%1')
      local without_inline_code = without_links:gsub('`([^`]*)`', '%1')
      local without_emphasis = without_inline_code:gsub('%*%*([^*]+)%*%*', '%1')
      local without_escapes = without_emphasis:gsub('\\([%p])', '%1')
      line_records[#line_records + 1] = {
        text = without_escapes,
        is_code = inside_code_fence,
      }
    end
  end
  while #line_records > 0 and line_records[1].text == '' do
    table.remove(line_records, 1)
  end
  while #line_records > 0 and line_records[#line_records].text == '' do
    table.remove(line_records)
  end
  local plain_lines = {}
  local code_line_indexes = {}
  for _, line_record in ipairs(line_records) do
    plain_lines[#plain_lines + 1] = line_record.text
    if line_record.is_code then
      code_line_indexes[#code_line_indexes + 1] = #plain_lines
    end
  end
  return plain_lines, code_line_indexes
end

local function location_items(client, response_result)
  if not client or response_result == nil then
    return {}
  end
  local response_locations = vim.islist(response_result) and response_result
    or { response_result }
  local conversion_succeeded, converted_items = pcall(
    vim.lsp.util.locations_to_items,
    response_locations,
    client.offset_encoding
  )
  if not conversion_succeeded then
    return {}
  end
  local definition_records = {}
  for _, converted_item in ipairs(converted_items) do
    definition_records[#definition_records + 1] = {
      filename = converted_item.filename,
      lnum = converted_item.lnum,
      col = converted_item.col,
      text = converted_item.text,
      location = converted_item.user_data,
      offset_encoding = client.offset_encoding,
    }
  end
  return definition_records
end

local function rendered_document(session)
  local document = {
    lines = {},
    definition_by_row = {},
    location_styles = {},
    code_fragments = {},
    section_rows = {},
    separator_rows = {},
    hint_rows = {},
    preview_rows = {},
  }

  local function append_section(title)
    local section_row = #document.lines + 1
    document.lines[section_row] = title
    document.section_rows[section_row] = true
    local separator_row = #document.lines + 1
    document.lines[separator_row] = string.rep('─', math.max(16, #title + 2))
    document.separator_rows[separator_row] = true
  end

  local function append_hint(message)
    local hint_row = #document.lines + 1
    document.lines[hint_row] = '  ' .. message
    document.hint_rows[hint_row] = true
  end

  append_section('Inferred type')
  table.sort(session.hover_entries, function(left_entry, right_entry)
    return left_entry.client_name < right_entry.client_name
  end)
  if #session.hover_entries == 0 then
    append_hint(
      session.hover_pending
          and 'Loading…'
        or 'No inferred type or hover information returned.'
    )
  else
    for entry_index, hover_entry in ipairs(session.hover_entries) do
      if #session.hover_entries > 1 then
        append_hint(('%s:'):format(hover_entry.client_name))
      end
      local hover_start_row = #document.lines
      for _, hover_line in ipairs(hover_entry.lines) do
        document.lines[#document.lines + 1] = hover_line == '' and '' or '  ' .. hover_line
      end
      for _, line_index in ipairs(hover_entry.code_line_indexes) do
        document.code_fragments[#document.code_fragments + 1] = {
          row = hover_start_row + line_index,
          column = 2,
          text = hover_entry.lines[line_index],
        }
      end
      if entry_index < #session.hover_entries then
        document.lines[#document.lines + 1] = ''
      end
    end
  end

  document.lines[#document.lines + 1] = ''
  append_section('Type definitions')
  append_hint('<Enter> jump  ·  <Space>k/q close  ·  y copy')
  table.sort(session.definition_items, function(left_item, right_item)
    if left_item.filename ~= right_item.filename then
      return left_item.filename < right_item.filename
    end
    if left_item.lnum ~= right_item.lnum then
      return left_item.lnum < right_item.lnum
    end
    return left_item.col < right_item.col
  end)
  if #session.definition_items == 0 then
    append_hint(session.definition_pending and 'Loading…' or 'No type definition returned.')
  else
    for item_index, definition_item in ipairs(session.definition_items) do
      local index_prefix = ('  %d  '):format(item_index)
      local location_text = ('%s:%d:%d'):format(
        display_path(definition_item.filename),
        definition_item.lnum,
        definition_item.col
      )
      local location_row = #document.lines + 1
      document.lines[location_row] = index_prefix .. location_text
      document.definition_by_row[location_row] = definition_item
      document.location_styles[location_row] = {
        index_end_column = #index_prefix,
        location_end_column = #index_prefix + #location_text,
      }
      local definition_text = vim.trim(definition_item.text or '')
      if definition_text ~= '' then
        local preview_row = #document.lines + 1
        document.lines[preview_row] = '     ' .. definition_text
        document.definition_by_row[preview_row] = definition_item
        document.preview_rows[preview_row] = true
        document.code_fragments[#document.code_fragments + 1] = {
          row = preview_row,
          column = 5,
          text = definition_text,
        }
      end
      if item_index < #session.definition_items then
        document.lines[#document.lines + 1] = ''
      end
    end
  end

  return document
end

local function apply_treesitter_highlights(bufnr, source_filetype, code_fragments)
  local parser_language = vim.treesitter.language.get_lang(source_filetype)
  if not parser_language then
    return
  end
  local query_succeeded, highlight_query = pcall(
    vim.treesitter.query.get,
    parser_language,
    'highlights'
  )
  if not query_succeeded or not highlight_query then
    return
  end

  for _, code_fragment in ipairs(code_fragments) do
    local parser_succeeded, string_parser = pcall(
      vim.treesitter.get_string_parser,
      code_fragment.text,
      parser_language
    )
    if parser_succeeded and string_parser then
      string_parser:parse(true)
      string_parser:for_each_tree(function(syntax_tree, language_tree)
        local tree_language = language_tree:lang()
        local tree_query = tree_language == parser_language
            and highlight_query
          or vim.treesitter.query.get(tree_language, 'highlights')
        if not syntax_tree or not tree_query then
          return
        end
        for capture_id, node in tree_query:iter_captures(
          syntax_tree:root(),
          code_fragment.text
        ) do
          local start_row, start_column, end_row, end_column = node:range()
          local capture_name = tree_query.captures[capture_id]
          if start_row == 0
            and end_row == 0
            and capture_name
            and capture_name:sub(1, 1) ~= '_'
          then
            vim.api.nvim_buf_set_extmark(
              bufnr,
              highlight_namespace,
              code_fragment.row - 1,
              code_fragment.column + start_column,
              {
                end_col = code_fragment.column + end_column,
                hl_group = ('@%s.%s'):format(capture_name, tree_language),
                priority = vim.hl.priorities.treesitter,
              }
            )
          end
        end
      end)
    end
  end
end

local function window_size(content_lines)
  local maximum_width = math.max(20, math.min(88, vim.o.columns - 4))
  local content_width = 0
  for _, content_line in ipairs(content_lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(content_line))
  end
  local window_width = math.min(maximum_width, math.max(52, content_width))
  local display_rows = 0
  for _, content_line in ipairs(content_lines) do
    display_rows = display_rows
      + math.max(1, math.ceil(vim.fn.strdisplaywidth(content_line) / window_width))
  end
  local maximum_height = math.max(4, math.min(30, vim.o.lines - 4))
  local window_height = math.min(maximum_height, math.max(4, display_rows))
  return window_width, window_height
end

local function update_window(session)
  if session.closed
    or not vim.api.nvim_buf_is_valid(session.bufnr)
    or not vim.api.nvim_win_is_valid(session.winid)
  then
    return
  end

  local document = rendered_document(session)
  session.definition_rows = document.definition_by_row
  vim.bo[session.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(session.bufnr, 0, -1, false, document.lines)
  vim.bo[session.bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(session.bufnr, highlight_namespace, 0, -1)
  for section_row in pairs(document.section_rows) do
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      section_row - 1,
      0,
      {
        end_col = #document.lines[section_row],
        hl_group = 'TypeInformationSection',
        priority = 200,
      }
    )
  end
  for separator_row in pairs(document.separator_rows) do
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      separator_row - 1,
      0,
      {
        end_col = #document.lines[separator_row],
        hl_group = 'TypeInformationSeparator',
        priority = 200,
      }
    )
  end
  for hint_row in pairs(document.hint_rows) do
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      hint_row - 1,
      0,
      {
        end_col = #document.lines[hint_row],
        hl_group = 'TypeInformationHint',
        priority = 200,
      }
    )
  end
  for location_row, location_style in pairs(document.location_styles) do
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      location_row - 1,
      0,
      {
        end_col = location_style.index_end_column,
        hl_group = 'TypeInformationIndex',
        priority = 200,
      }
    )
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      location_row - 1,
      location_style.index_end_column,
      {
        end_col = location_style.location_end_column,
        hl_group = 'TypeInformationLocation',
        priority = 200,
      }
    )
  end
  for preview_row in pairs(document.preview_rows) do
    vim.api.nvim_buf_set_extmark(
      session.bufnr,
      highlight_namespace,
      preview_row - 1,
      0,
      {
        end_col = #document.lines[preview_row],
        hl_eol = true,
        hl_group = 'TypeInformationPreview',
        hl_mode = 'combine',
        priority = 50,
      }
    )
  end
  apply_treesitter_highlights(
    session.bufnr,
    session.source_filetype,
    document.code_fragments
  )
  local window_width, window_height = window_size(document.lines)
  vim.api.nvim_win_set_width(session.winid, window_width)
  vim.api.nvim_win_set_height(session.winid, window_height)
end

local function cancel_requests(session)
  for _, cancel_request in ipairs(session.cancel_requests) do
    pcall(cancel_request)
  end
  session.cancel_requests = {}
end

local function close_session(session)
  if session.closed then
    return
  end
  session.closed = true
  cancel_requests(session)
  if active_session == session then
    active_session = nil
  end
  if vim.api.nvim_win_is_valid(session.winid) then
    vim.api.nvim_win_close(session.winid, true)
  end
end

local function jump_to_definition(session)
  local cursor_row = vim.api.nvim_win_get_cursor(session.winid)[1]
  local definition_item = session.definition_rows[cursor_row]
  if not definition_item and #session.definition_items == 1 then
    definition_item = session.definition_items[1]
  end
  if not definition_item then
    vim.notify('Move the cursor to a type definition before jumping', vim.log.levels.INFO)
    return
  end

  local target_location = definition_item.location
  local offset_encoding = definition_item.offset_encoding
  local source_window = session.source_window
  close_session(session)
  if vim.api.nvim_win_is_valid(source_window) then
    vim.api.nvim_set_current_win(source_window)
  end
  if not target_location
    or not vim.lsp.util.show_document(
      target_location,
      offset_encoding,
      { focus = true, reuse_win = true }
    )
  then
    vim.notify('Unable to open the selected type definition', vim.log.levels.WARN)
  end
end

local function open_window(session)
  local initial_document = rendered_document(session)
  session.definition_rows = initial_document.definition_by_row
  local window_width, window_height = window_size(initial_document.lines)
  local window_config = vim.lsp.util.make_floating_popup_options(
    window_width,
    window_height,
    {
      border = 'rounded',
      focusable = true,
      relative = 'cursor',
      title = ' Type inspector ',
      title_pos = 'center',
    }
  )
  session.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[session.bufnr].bufhidden = 'wipe'
  vim.bo[session.bufnr].filetype = 'text'
  vim.api.nvim_buf_set_lines(session.bufnr, 0, -1, false, initial_document.lines)
  vim.bo[session.bufnr].modifiable = false
  session.winid = vim.api.nvim_open_win(session.bufnr, true, window_config)

  require('config.detail_window').attach({
    bufnr = session.bufnr,
    winid = session.winid,
    toggle_key = '<Space>k',
    close = function()
      close_session(session)
    end,
  })
  vim.keymap.set('n', '<CR>', function()
    jump_to_definition(session)
  end, {
    buffer = session.bufnr,
    nowait = true,
    silent = true,
    desc = 'Jump to type definition',
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    once = true,
    pattern = tostring(session.winid),
    callback = function()
      if not session.closed then
        session.closed = true
        cancel_requests(session)
        if active_session == session then
          active_session = nil
        end
      end
    end,
  })
end

local function position_params(source_window)
  return function(client)
    return vim.lsp.util.make_position_params(source_window, client.offset_encoding)
  end
end

local function collect_hover_responses(session, response_documents)
  if session.closed then
    return
  end
  local seen_content = {}
  for client_id, response_document in pairs(response_documents) do
    if not response_document.err and response_document.result then
      local response_lines, code_line_indexes = plain_hover_lines(
        response_document.result.contents
      )
      local content_key = table.concat(response_lines, '\n')
      if #response_lines > 0 and not seen_content[content_key] then
        seen_content[content_key] = true
        local client = vim.lsp.get_client_by_id(client_id)
        session.hover_entries[#session.hover_entries + 1] = {
          client_name = client and client.name or ('client %d'):format(client_id),
          lines = response_lines,
          code_line_indexes = code_line_indexes,
        }
      end
    end
  end
  session.hover_pending = false
  update_window(session)
end

local function collect_definition_responses(session, response_documents)
  if session.closed then
    return
  end
  local seen_locations = {}
  for client_id, response_document in pairs(response_documents) do
    if not response_document.err and response_document.result then
      local client = vim.lsp.get_client_by_id(client_id)
      for _, definition_item in ipairs(location_items(client, response_document.result)) do
        local location_key = ('%s:%d:%d'):format(
          definition_item.filename,
          definition_item.lnum,
          definition_item.col
        )
        if not seen_locations[location_key] then
          seen_locations[location_key] = true
          session.definition_items[#session.definition_items + 1] = definition_item
        end
      end
    end
  end
  session.definition_pending = false
  update_window(session)
end

local function start_requests(session)
  local hover_clients = vim.lsp.get_clients({
    bufnr = session.source_buffer,
    method = 'textDocument/hover',
  })
  local definition_clients = vim.lsp.get_clients({
    bufnr = session.source_buffer,
    method = 'textDocument/typeDefinition',
  })

  session.hover_pending = #hover_clients > 0
  session.definition_pending = #definition_clients > 0
  update_window(session)

  if session.hover_pending then
    local cancel_hover = vim.lsp.buf_request_all(
      session.source_buffer,
      'textDocument/hover',
      position_params(session.source_window),
      function(response_documents)
        collect_hover_responses(session, response_documents)
      end
    )
    session.cancel_requests[#session.cancel_requests + 1] = cancel_hover
  end

  if session.definition_pending then
    local cancel_definitions = vim.lsp.buf_request_all(
      session.source_buffer,
      'textDocument/typeDefinition',
      position_params(session.source_window),
      function(response_documents)
        collect_definition_responses(session, response_documents)
      end
    )
    session.cancel_requests[#session.cancel_requests + 1] = cancel_definitions
  end
end

function M.toggle()
  if active_session then
    close_session(active_session)
    return
  end

  local source_buffer = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  local session = {
    source_buffer = source_buffer,
    source_window = source_window,
    source_filetype = vim.bo[source_buffer].filetype,
    bufnr = -1,
    winid = -1,
    closed = false,
    cancel_requests = {},
    hover_pending = true,
    hover_entries = {},
    definition_pending = true,
    definition_items = {},
    definition_rows = {},
  }
  active_session = session
  open_window(session)
  start_requests(session)
end

return M
