-- Shared plumbing for the type-hierarchy workflows: query context, location
-- pickers, result entries, source parsing, and recursive-walk bookkeeping.
-- Language paths live in `config.type_hierarchy.python` (indexed AST) and
-- `config.type_hierarchy.lsp` (live LSP requests).
local project = require('config.project')
local query_picker = require('config.search.query_picker')

local M = {}

function M.current_query_context()
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

function M.relative_path(root, filename)
  return vim.fs.relpath(root, filename) or filename
end

function M.new_location_picker(title, entry_maker)
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

function M.open_location_picker(title, records, entry_maker, session)
  local active_session = session or M.new_location_picker(title, entry_maker)
  active_session:finish(records)
end

function M.hierarchy_item_key(item)
  local item_range = item.selectionRange or item.range
  return table.concat({
    item.uri,
    item.name,
    item_range.start.line,
    item_range.start.character,
  }, ':')
end

function M.hierarchy_entry(root, direction)
  local arrow = direction == 'subtypes' and '↳ ' or '↰ '
  return function(record)
    local item = record.item
    local item_range = item.selectionRange or item.range
    local filename = vim.uri_to_fname(item.uri)
    local item_path = M.relative_path(root, filename)
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

function M.implementation_entry(root)
  return function(record)
    local implementation_path = M.relative_path(root, record.filename)
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

function M.file_lines(filename)
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

function M.parse_source(source, language)
  local parsed_trees = {}
  local parse_succeeded = pcall(function()
    local parser = vim.treesitter.get_string_parser(source, language)
    parsed_trees = parser:parse()
  end)
  return parse_succeeded and parsed_trees[1] or nil
end

function M.normalized_locations(result)
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

-- Build a session cancel function for an in-flight client request.
function M.cancel_request(client, request_id)
  return function()
    if client.requests and client.requests[request_id] then
      client:cancel_request(request_id)
    end
  end
end

-- Bookkeeping for a recursive hierarchy walk: deduplicates visited items,
-- tracks pending requests, streams progress into the picker session, and
-- publishes the depth-sorted result once the walk drains.
function M.hierarchy_walk(root_item, direction, bufnr, session, title)
  local root = project.for_buffer(bufnr)
  local walk = {
    visited = { [M.hierarchy_item_key(root_item)] = true },
    records = {},
    pending = 0,
    published = false,
  }

  function walk:publish_if_drained()
    if self.pending ~= 0 or self.published then
      return
    end
    self.published = true
    table.sort(self.records, function(left_record, right_record)
      if left_record.depth ~= right_record.depth then
        return left_record.depth < right_record.depth
      end
      return left_record.item.name < right_record.item.name
    end)
    M.open_location_picker(title, self.records, M.hierarchy_entry(root, direction), session)
  end

  -- Records a newly discovered item and reports progress; returns false when
  -- the item was already visited.
  function walk:record(item, depth)
    local item_key = M.hierarchy_item_key(item)
    if self.visited[item_key] then
      return false
    end
    self.visited[item_key] = true
    table.insert(self.records, { depth = depth, item = item })
    session:update(self.records, ('querying… %d classes available'):format(#self.records))
    return true
  end

  function walk:begin_request()
    self.pending = self.pending + 1
  end

  function walk:finish_request()
    self.pending = self.pending - 1
    self:publish_if_drained()
  end

  return walk
end

return M
