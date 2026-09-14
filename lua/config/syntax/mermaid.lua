local M = {
  name = 'mermaid',
  command = 'termaid',
  max_blocks = 8,
  max_concurrent = 2,
  max_output_bytes = 1024 * 1024,
  max_rendered_chunks = 65536,
  max_rendered_lines = 4096,
  max_source_bytes = 256 * 1024,
  timeout_ms = 8000,
  width_ratio = 0.85,
}
local markdown_features = require('config.syntax.markdown_features')

local states_by_buffer = {}
local block_query
local block_query_resolved = false
local styled_support_by_executable = {}

local style_highlights = {
  active = 'RenderMarkdownMermaidActive',
  arrow = 'RenderMarkdownMermaidArrow',
  bold_label = 'RenderMarkdownMermaidContentLabel',
  crit = 'RenderMarkdownMermaidCritical',
  default = 'RenderMarkdownMermaid',
  done = 'RenderMarkdownMermaidDone',
  edge = 'RenderMarkdownMermaidEdge',
  edge_label = 'RenderMarkdownMermaidEdgeLabel',
  italic_label = 'RenderMarkdownMermaidItalicLabel',
  label = 'RenderMarkdownMermaidContentLabel',
  milestone = 'RenderMarkdownMermaidMilestone',
  node = 'RenderMarkdownMermaidNode',
  normal = 'RenderMarkdownMermaidNode',
  subgraph = 'RenderMarkdownMermaidSubgraph',
  subgraph_label = 'RenderMarkdownMermaidSubgraphLabel',
}

local section_highlights = {
  'RenderMarkdownMermaidSection1',
  'RenderMarkdownMermaidSection2',
  'RenderMarkdownMermaidSection3',
  'RenderMarkdownMermaidSection4',
  'RenderMarkdownMermaidSection5',
  'RenderMarkdownMermaidSection6',
  'RenderMarkdownMermaidSection7',
  'RenderMarkdownMermaidSection8',
}

local function query()
  if block_query_resolved then
    return block_query
  end
  block_query_resolved = true
  pcall(function()
    block_query = vim.treesitter.query.parse(
      'markdown',
      '(fenced_code_block) @block'
    )
  end)
  return block_query
end

local function child_of_type(node, node_type)
  for child in node:iter_children() do
    if child:named() and child:type() == node_type then
      return child
    end
  end
  return nil
end

local function is_mermaid(info)
  local language = vim.trim(info):match('^(%S+)')
  return language ~= nil and language:lower() == 'mermaid'
end

local function line_end_exclusive(node)
  local _, _, end_row, end_column = node:range()
  return end_row + (end_column > 0 and 1 or 0)
end

local function block_from_node(buffer, node, width)
  local info_node = child_of_type(node, 'info_string')
  local content_node = child_of_type(node, 'code_fence_content')
  local info = info_node and vim.treesitter.get_node_text(info_node, buffer) or ''
  if not content_node or not is_mermaid(info) then
    return nil
  end

  local source = vim.treesitter.get_node_text(content_node, buffer)
    :gsub('\r\n', '\n')
    :gsub('\r', '\n')
    :gsub('\n+$', '')
  local block_start = node:range()
  local content_start = content_node:range()
  local content_end = line_end_exclusive(content_node)
  local block_end = line_end_exclusive(node)
  local key = table.concat({
    block_start,
    block_end,
    content_start,
    content_end,
    width,
    vim.fn.sha256(source),
  }, ':')
  return {
    block_end = block_end,
    block_start = block_start,
    content_end = content_end,
    content_start = content_start,
    key = key,
    source = source,
    width = width,
  }
end

local function text_lines(text)
  local normalized = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\n+$', '')
  if normalized == '' then
    return nil
  end
  return vim.split(normalized, '\n', { plain = true })
end

local function common_indent(lines)
  local indent
  for _, line in ipairs(lines) do
    if line:find('%S') then
      local line_indent = #(line:match('^ *') or '')
      indent = math.min(indent or line_indent, line_indent)
    end
  end
  return indent or 0
end

---@param lines string[]
---@param width integer
---@return string[]?
function M.fit_lines(lines, width)
  local fitted = {}
  local indent = common_indent(lines)
  local limit = math.max(2, math.floor(width))
  for _, raw_line in ipairs(lines) do
    local line = indent > 0 and raw_line:sub(indent + 1) or raw_line
    if vim.fn.strdisplaywidth(line) > limit then
      return nil
    end
    fitted[#fitted + 1] = line
  end
  return fitted
end

local function style_highlight(style)
  local direct = style_highlights[style]
  if direct then
    return direct
  end
  if style:find('^class:') or style:find('^nodestyle:') then
    return style_highlights.node
  end
  if style:find('^linkstyle:') then
    return style_highlights.edge
  end
  local section = tonumber(style:match('^section:(%d+)'))
    or tonumber(style:match('^sectionfg:(%d+)'))
  if section then
    return section_highlights[(section % #section_highlights) + 1]
  end
  return style_highlights.default
end

local function valid_chunk_text(text)
  return type(text) == 'string'
    and not text:find('[%z\1-\31\127]')
end

---@param output string
---@param width integer
---@return table[]?
function M.decode_styled_output(output, width)
  local decoded_ok, decoded = pcall(vim.json.decode, output)
  if not decoded_ok
      or type(decoded) ~= 'table'
      or decoded.version ~= 1
      or type(decoded.lines) ~= 'table'
      or #decoded.lines == 0
      or #decoded.lines > M.max_rendered_lines then
    return nil
  end
  local rendered_lines = {}
  local chunk_count = 0
  for _, raw_line in ipairs(decoded.lines) do
    if type(raw_line) ~= 'table' then
      return nil
    end
    local chunks = {}
    local text_parts = {}
    for _, raw_chunk in ipairs(raw_line) do
      if type(raw_chunk) ~= 'table'
          or not valid_chunk_text(raw_chunk.text)
          or raw_chunk.text:find('\n', 1, true)
          or type(raw_chunk.style) ~= 'string'
          or #raw_chunk.style > 128
          or not raw_chunk.style:match('^[%w_:%-%.]+$') then
        return nil
      end
      if raw_chunk.text ~= '' then
        chunk_count = chunk_count + 1
        if chunk_count > M.max_rendered_chunks then
          return nil
        end
        text_parts[#text_parts + 1] = raw_chunk.text
        chunks[#chunks + 1] = {
          raw_chunk.text,
          style_highlight(raw_chunk.style),
        }
      end
    end
    local line_text = table.concat(text_parts)
    if vim.fn.strdisplaywidth(line_text) > math.max(2, math.floor(width)) then
      return nil
    end
    rendered_lines[#rendered_lines + 1] = {
      chunks = chunks,
      text = line_text,
    }
  end
  return rendered_lines
end

local function plain_rendered_lines(output, width)
  local lines = text_lines(output)
  if not lines then
    return nil
  end
  local fitted_lines = M.fit_lines(lines, width)
  if not fitted_lines or #fitted_lines > M.max_rendered_lines then
    return nil
  end
  return vim.tbl_map(function(line)
    return {
      chunks = { { line == '' and ' ' or line, style_highlights.default } },
      text = line,
    }
  end, fitted_lines)
end

local function content_width(buffer)
  local width
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(window)
        and vim.api.nvim_win_get_buf(window) == buffer then
      local window_info = vim.fn.getwininfo(window)[1] or { textoff = 0 }
      local text_width = vim.api.nvim_win_get_width(window) - window_info.textoff
      local available = math.floor(text_width * M.width_ratio)
      width = math.min(width or available, available)
    end
  end
  return math.max(1, width or math.floor((vim.o.columns - 4) * M.width_ratio))
end

local function stop_request(request)
  if request.process then
    pcall(function()
      request.process:kill(15)
    end)
    request.process = nil
  end
end

local function retire_state(state)
  state.generation = state.generation + 1
  for _, request in pairs(state.jobs) do
    stop_request(request)
  end
  state.active = 0
  state.jobs = {}
  state.queue = {}
end

local function new_state(changedtick, width, generation)
  return {
    active = 0,
    blocks = {},
    changedtick = changedtick,
    generation = generation,
    jobs = {},
    known = {},
    known_count = 0,
    queue = {},
    results = {},
    width = width,
  }
end

local function state_for(buffer, width)
  local changedtick = vim.api.nvim_buf_get_changedtick(buffer)
  local current_state = states_by_buffer[buffer]
  if current_state and current_state.changedtick == changedtick and current_state.width == width then
    return current_state
  end
  if current_state then
    retire_state(current_state)
  end
  local generation = current_state and current_state.generation or 0
  local next_state = new_state(changedtick, width, generation + 1)
  states_by_buffer[buffer] = next_state
  return next_state
end

---@return string?
function M.find_executable()
  local configured_path = vim.fn.expand(M.command)
  if configured_path:find('/', 1, true) then
    return vim.fn.executable(configured_path) == 1 and configured_path or nil
  end
  local executable_path = vim.fn.exepath(configured_path)
  if executable_path ~= '' then
    return executable_path
  end
  if configured_path == 'termaid' then
    local uv_tool_path = vim.fs.joinpath(
      vim.uv.os_homedir(),
      '.local',
      'bin',
      'termaid'
    )
    if vim.fn.executable(uv_tool_path) == 1 then
      return uv_tool_path
    end
  end
  return nil
end

function M.start_process(command, options, callback)
  return vim.system(command, options, callback)
end

local function request_render(buffer)
  markdown_features.request_render(buffer, 'MermaidRender')
end

local pump
local launch_request

local function finish_request(buffer, state, request, completed_process)
  if states_by_buffer[buffer] ~= state
      or state.generation ~= request.generation
      or state.jobs[request.block.key] ~= request then
    return
  end
  request.process = nil

  local stdout = completed_process.stdout or ''
  local rendered_lines
  if completed_process.code == 0 and #stdout <= M.max_output_bytes then
    rendered_lines = request.styled
        and M.decode_styled_output(stdout, request.block.width)
      or plain_rendered_lines(stdout, request.block.width)
  end
  if request.styled and rendered_lines then
    styled_support_by_executable[request.executable] = true
  elseif request.styled then
    local stderr = completed_process.stderr or ''
    local unsupported = completed_process.code == 2
      and (stderr:find('--format', 1, true)
        or stderr:find('unrecognized arguments', 1, true))
    if completed_process.code == 0 or unsupported then
      styled_support_by_executable[request.executable] = unsupported and false or nil
      request.styled = false
      launch_request(buffer, state, request)
      return
    end
  end
  state.jobs[request.block.key] = nil
  state.active = math.max(0, state.active - 1)
  state.results[request.block.key] = rendered_lines and {
    lines = rendered_lines,
    status = 'rendered',
  } or {
    status = completed_process.code == 124 and 'timeout' or 'failed',
  }
  pump(buffer, state)
  request_render(buffer)
end

launch_request = function(buffer, state, request)
  local command = {
    request.executable,
    '--width',
    tostring(request.block.width),
    '--strict-width',
    '--fit-mode',
    'reflow',
    '--max-height',
    tostring(M.max_rendered_lines),
  }
  if request.styled then
    vim.list_extend(command, { '--format', 'styled-json' })
  end
  local started, process = pcall(M.start_process, command, {
    stdin = request.block.source,
    text = true,
    timeout = M.timeout_ms,
  }, function(completed_process)
    vim.schedule(function()
      local handled = pcall(
        finish_request,
        buffer,
        state,
        request,
        completed_process
      )
      if not handled
          and states_by_buffer[buffer] == state
          and state.jobs[request.block.key] == request then
        finish_request(buffer, state, request, { code = 1 })
      end
    end)
  end)
  if not started then
    state.jobs[request.block.key] = nil
    state.active = math.max(0, state.active - 1)
    state.results[request.block.key] = { status = 'unavailable' }
    return
  end
  request.process = process
end

local function start_request(buffer, state, block)
  local executable = M.find_executable()
  if not executable then
    state.results[block.key] = { status = 'unavailable' }
    return
  end
  if #block.source > M.max_source_bytes then
    state.results[block.key] = { status = 'limit' }
    return
  end

  local request = {
    block = block,
    executable = executable,
    generation = state.generation,
    styled = styled_support_by_executable[executable] ~= false,
  }
  state.jobs[block.key] = request
  state.active = state.active + 1
  launch_request(buffer, state, request)
end

pump = function(buffer, state)
  while states_by_buffer[buffer] == state
      and state.active < M.max_concurrent
      and #state.queue > 0 do
    start_request(buffer, state, table.remove(state.queue, 1))
  end
end

local function line_chunks(line)
  if type(line) == 'table' then
    if #line.chunks == 0 then
      return { { ' ', style_highlights.default } }
    end
    return vim.deepcopy(line.chunks)
  end
  return { { line == '' and ' ' or line, style_highlights.default } }
end

local function enqueue(state, block)
  if state.results[block.key] or state.jobs[block.key] or state.known[block.key] then
    return
  end
  if state.known_count >= M.max_blocks then
    return
  end
  state.known[block.key] = true
  state.known_count = state.known_count + 1
  state.queue[#state.queue + 1] = block
end

function M.parse(context)
  local parsed_query = query()
  if not parsed_query then return {} end
  local width = context.width and math.max(1, math.floor(context.width * M.width_ratio))
    or content_width(context.buf)
  local state = state_for(context.buf, width)
  local blocks = {}
  for _, node in parsed_query:iter_captures(context.root, context.buf, 0, -1) do
    local block = block_from_node(context.buf, node, width)
    if block then
      blocks[#blocks + 1] = block
      enqueue(state, block)
    end
  end
  state.blocks = blocks
  pump(context.buf, state)
  return {}
end

function M.stage(buffer)
  local state = states_by_buffer[buffer]
  if not state then return {} end
  local blocks = {}
  for _, block in ipairs(state.blocks) do
    local result = state.results[block.key]
    if result and result.status == 'rendered' then
      local rows = { {
        chunks = { { '󰙅 ', 'RenderMarkdownMermaidIcon' }, { 'mermaid', 'RenderMarkdownMermaidLabel' } },
        source_row = block.block_start,
      } }
      local source_count = block.content_end - block.content_start
      for index, line in ipairs(result.lines) do
        rows[#rows + 1] = {
          chunks = line_chunks(line),
          source_row = block.content_start + math.min(source_count - 1,
            math.floor((index - 1) * source_count / #result.lines)),
        }
      end
      blocks[#blocks + 1] = { start_row = block.block_start, end_row = block.block_end, rows = rows }
    end
  end
  return blocks
end

function M.project(context)
  M.parse(context)
  return M.stage(context.buf)
end

function M.detach(buffer)
  local state = states_by_buffer[buffer]
  if state then
    retire_state(state)
    states_by_buffer[buffer] = nil
  end
end

return M
