local M = {
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
local attached_buffers = {}
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
  local state = states_by_buffer[buffer]
  if state and state.changedtick == changedtick and state.width == width then
    return state
  end
  local generation = state and state.generation or 0
  if state then
    retire_state(state)
    generation = state.generation
  end
  state = new_state(changedtick, width, generation + 1)
  states_by_buffer[buffer] = state
  return state
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

local function line_text(line)
  return type(line) == 'table' and line.text or line
end

local function distributed_lines(lines, source_count)
  local groups = {}
  local next_line = 1
  for source_index = 1, source_count do
    local last_line = #lines >= source_count
        and math.floor(source_index * #lines / source_count)
      or math.min(source_index, #lines)
    local group = {}
    while next_line <= last_line do
      group[#group + 1] = lines[next_line]
      next_line = next_line + 1
    end
    groups[source_index] = group
  end
  return groups
end

local function group_cursor(buffer, block, group, source_row, source_column)
  if source_row < block.content_start or source_row >= block.content_end then
    return nil
  end
  local source_index = source_row - block.content_start + 1
  local source_line = vim.api.nvim_buf_get_lines(
    buffer,
    source_row,
    source_row + 1,
    false
  )[1] or ''
  local source_prefix = source_line:sub(1, source_column)
  local source_width = math.max(vim.fn.strdisplaywidth(source_line), 1)
  local source_offset = vim.fn.strdisplaywidth(source_prefix)
  local line_index = math.max(1, math.ceil(#group / 2))
  local line_width = math.max(
    vim.fn.strdisplaywidth(line_text(group[line_index]) or ''),
    1
  )
  return {
    column = math.floor(
      math.min(source_offset / source_width, 1) * (line_width - 1)
    ),
    line = line_index,
    source_index = source_index,
  }
end

local function render_marks(buffer, block, lines, cursor)
  local source_count = block.content_end - block.content_start
  if source_count <= 0 then
    return {}
  end
  local label_chunks = markdown_features.pad_overlay_chunks({
    { '󰙅 ', 'RenderMarkdownMermaidIcon' },
    { 'mermaid', 'RenderMarkdownMermaidLabel' },
  }, string.rep(' ', block.width), 'RenderMarkdownMermaidLabel')
  local marks = {
    {
      key = ('mermaid:%d:label'):format(block.block_start),
      options = {
        priority = 201,
        strict = false,
        virt_text = label_chunks,
        virt_text_pos = 'overlay',
      },
      row = block.block_start,
    },
    {
      key = ('mermaid:%d:closing-fence'):format(block.block_start),
      options = {
        conceal_lines = '',
        priority = 201,
        strict = false,
      },
      row = block.block_end - 1,
    },
  }
  local groups = distributed_lines(lines, source_count)
  local target = cursor and group_cursor(
    buffer,
    block,
    groups[cursor.row - block.content_start + 1] or {},
    cursor.row,
    cursor.column
  ) or nil
  for source_index, group in ipairs(groups) do
    local source_row = block.content_start + source_index - 1
    local source_line = vim.api.nvim_buf_get_lines(
      buffer,
      source_row,
      source_row + 1,
      false
    )[1] or ''
    local primary_chunks = markdown_features.pad_overlay_chunks(
      line_chunks(group[1] or ''),
      source_line,
      'RenderMarkdownMermaid'
    )
    if target and target.source_index == source_index and target.line == 1 then
      primary_chunks = markdown_features.highlighted_chunks(
        primary_chunks,
        'CursorLine'
      )
      primary_chunks = markdown_features.cursor_proxy_chunks(
        primary_chunks,
        target.column
      )
    end
    local options = {
      priority = 200,
      strict = false,
      virt_text = primary_chunks,
      virt_text_pos = 'overlay',
    }
    if #group > 1 then
      options.virt_lines = {}
      for line_index = 2, #group do
        local chunks = line_chunks(group[line_index])
        if target
            and target.source_index == source_index
            and target.line == line_index then
          chunks = markdown_features.highlighted_chunks(chunks, 'CursorLine')
          chunks = markdown_features.cursor_proxy_chunks(
            chunks,
            target.column
          )
        end
        options.virt_lines[#options.virt_lines + 1] = chunks
      end
    end
    marks[#marks + 1] = {
      key = ('mermaid:%d:row:%d'):format(block.block_start, source_row),
      options = options,
      row = source_row,
    }
  end
  return marks
end

local function current_window(window)
  if not window or window == 0 then
    return vim.api.nvim_get_current_win()
  end
  return window
end

local function interaction_mode(mode)
  if mode:sub(1, 1) == 'n' then
    return 'n'
  end
  if mode == 'v' or mode == 'V' or mode == '\22' then
    return mode
  end
  return nil
end

local function active_interaction(buffer, window, state)
  local resolved_window = current_window(window)
  local mode = interaction_mode(vim.api.nvim_get_mode().mode)
  if vim.api.nvim_get_current_win() ~= resolved_window
      or not mode
      or not vim.api.nvim_win_is_valid(resolved_window)
      or vim.api.nvim_win_get_buf(resolved_window) ~= buffer then
    return nil
  end
  local position = vim.api.nvim_win_get_cursor(resolved_window)
  local actual_cursor = { column = position[2], row = position[1] - 1 }
  local interaction = markdown_features.parked_interaction(
    'mermaid',
    buffer,
    resolved_window
  )
  if interaction
      and (interaction.cursor.row ~= actual_cursor.row
        or interaction.mode ~= mode) then
    markdown_features.release_cursor(
      'mermaid',
      buffer,
      resolved_window,
      false
    )
    interaction = nil
  end
  if not interaction then
    interaction = { cursor = actual_cursor, mode = mode }
    if mode ~= 'n' then
      local anchor = vim.fn.getpos('v')
      interaction.anchor = { column = anchor[3] - 1, row = anchor[2] - 1 }
    end
  end
  for _, block in ipairs(state.blocks) do
    local result = state.results[block.key]
    if result
        and result.status == 'rendered'
        and interaction.cursor.row >= block.content_start
        and interaction.cursor.row < block.content_end then
      return interaction, block
    end
  end
  return nil
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

---@param context render.md.handler.Context
---@return render.md.Mark[]
function M.parse(context)
  local parsed_query = query()
  if not parsed_query then
    return {}
  end
  local width = content_width(context.buf)
  local state = state_for(context.buf, width)
  local render_context = require('render-markdown.request.context').get(context.buf)
  local blocks = {}
  render_context.view:query(context.root, parsed_query, function(_, node)
    local block = block_from_node(context.buf, node, width)
    if block then
      blocks[#blocks + 1] = block
      enqueue(state, block)
    end
  end)
  state.blocks = blocks
  pump(context.buf, state)
  return {}
end

function M.clear(context)
  markdown_features.release_cursor('mermaid', context.buf, context.win, true)
  markdown_features.clear('mermaid', context.buf)
end

function M.stage(buffer, window)
  local state = states_by_buffer[buffer]
  if not state then
    return {}, nil
  end
  local resolved_window = current_window(window)
  local interaction, active_block = active_interaction(
    buffer,
    resolved_window,
    state
  )
  local staged_extmarks = {}
  for _, block in ipairs(state.blocks) do
    local result = state.results[block.key]
    if result and result.status == 'rendered' then
      vim.list_extend(staged_extmarks, render_marks(
        buffer,
        block,
        result.lines,
        active_block == block
          and interaction.mode == 'n'
          and interaction.cursor
          or nil
      ))
    end
  end
  return staged_extmarks, interaction
end

function M.render(context)
  local window = current_window(context.win)
  local staged_extmarks, interaction = M.stage(context.buf, window)
  markdown_features.apply(
    'mermaid',
    context.buf,
    staged_extmarks
  )
  if interaction then
    markdown_features.park_cursor(
      'mermaid',
      context.buf,
      window,
      interaction,
      'RenderMarkdownMermaidHiddenCursor'
    )
    vim.api.nvim_win_call(window, function()
      local view = vim.fn.winsaveview()
      if view.leftcol > 0 then
        view.leftcol = 0
        vim.fn.winrestview(view)
      end
    end)
  else
    markdown_features.release_cursor('mermaid', context.buf, window, true)
  end
end

function M.detach(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then
    for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
      markdown_features.release_cursor('mermaid', buffer, window, true)
    end
    markdown_features.clear('mermaid', buffer)
  end
  local state = states_by_buffer[buffer]
  if state then
    retire_state(state)
    states_by_buffer[buffer] = nil
  end
  attached_buffers[buffer] = nil
end

function M.attach(context)
  if attached_buffers[context.buf] then
    return
  end
  attached_buffers[context.buf] = true
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    buffer = context.buf,
    callback = function()
      markdown_features.release_cursor(
        'mermaid',
        context.buf,
        vim.api.nvim_get_current_win(),
        true
      )
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = context.buf,
    once = true,
    callback = function()
      M.detach(context.buf)
    end,
  })
end

return M
