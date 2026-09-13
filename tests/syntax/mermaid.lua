-- Focused inline rendering, fallback, and process-budget tests for Mermaid.
local markdown_features = require('config.syntax.markdown_features')
local mermaid = require('config.syntax.mermaid')

local original = {
  buffer = vim.api.nvim_get_current_buf(),
  find_executable = mermaid.find_executable,
  guicursor = vim.o.guicursor,
  max_concurrent = mermaid.max_concurrent,
  feature_request_render = markdown_features.request_render,
  request_context = package.loaded['render-markdown.request.context'],
  start_process = mermaid.start_process,
  timeout = mermaid.timeout_ms,
  width_ratio = mermaid.width_ratio,
}

package.loaded['render-markdown.request.context'] = {
  get = function(buffer)
    return {
      win = 0,
      view = {
        query = function(_, root, parsed_query, callback)
          for capture_id, node in parsed_query:iter_captures(root, buffer, 0, -1) do
            callback(capture_id, node)
          end
        end,
      },
    }
  end,
}

local refreshes = 0
markdown_features.request_render = function(buffer, event)
  assert(vim.api.nvim_buf_is_valid(buffer), 'Mermaid requested an invalid buffer')
  assert(event == 'MermaidRender', 'Mermaid used the wrong shared render event')
  refreshes = refreshes + 1
end

local function fixture(lines)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].filetype = 'markdown'
  vim.api.nvim_set_current_buf(buffer)
  local parser = vim.treesitter.get_parser(buffer, 'markdown')
  local tree = assert(parser:parse()[1])
  return buffer, { buf = buffer, root = tree:root() }
end

local buffer, context = fixture({
  '',
  '```mermaid',
  'graph LR',
  '  A --> B',
  '```',
  '```python',
  'print("not mermaid")',
  '```',
})

local fitted_lines = mermaid.fit_lines({
  '    ABCD',
  '    你好',
}, 4)
assert(
  vim.deep_equal(fitted_lines, { 'ABCD', '你好' }),
  'Mermaid output was not validated and left-aligned'
)
for _, line in ipairs(fitted_lines) do
  assert(
    vim.fn.strdisplaywidth(line) <= 4,
    'Mermaid width validation accepted an oversized display line'
  )
end
assert(
  mermaid.fit_lines({ 'ABCDE' }, 4) == nil,
  'Mermaid accepted a canvas wider than the strict width contract'
)

local process_requests = {}
local killed_processes = 0
local function styled_output(lines)
  return vim.json.encode({ version = 1, lines = lines })
end

local colorful_output = styled_output({
  {
    { text = '┌', style = 'node' },
    { text = '─', style = 'edge' },
    { text = '►', style = 'arrow' },
  },
  {
    { text = '│ ', style = 'node' },
    { text = 'A', style = 'label' },
    { text = ' │', style = 'node' },
  },
  { { text = '└───┘', style = 'node' } },
})

local decoded_colorful = assert(mermaid.decode_styled_output(colorful_output, 8))
assert(
  decoded_colorful[1].chunks[1][2] == 'RenderMarkdownMermaidNode'
    and decoded_colorful[1].chunks[2][2] == 'RenderMarkdownMermaidEdge'
    and decoded_colorful[1].chunks[3][2] == 'RenderMarkdownMermaidArrow'
    and decoded_colorful[2].chunks[2][2]
      == 'RenderMarkdownMermaidContentLabel',
  'Mermaid semantic output did not map to its bounded color palette'
)
assert(
  mermaid.decode_styled_output('{"version":2,"lines":[]}', 8) == nil
    and mermaid.decode_styled_output(styled_output({ {
      { text = 'too wide', style = 'node' },
    } }), 3) == nil,
  'Mermaid accepted an unknown styled schema or oversized semantic row'
)

mermaid.find_executable = function()
  return nil
end
mermaid.start_process = function()
  error('Missing Termaid fallback started a process')
end
assert(
  #mermaid.parse(context) == 0,
  'Missing Termaid support did not leave Mermaid source as raw text'
)
assert(#process_requests == 0, 'Missing Termaid support queued a renderer')

mermaid.detach(buffer)
mermaid.find_executable = function()
  return '/test/bin/termaid'
end
mermaid.start_process = function(command, options, callback)
  process_requests[#process_requests + 1] = {
    callback = callback,
    command = command,
    options = options,
  }
  return {
    kill = function(_, signal)
      assert(signal == 15, 'Mermaid renderer did not terminate with SIGTERM')
      killed_processes = killed_processes + 1
    end,
  }
end
mermaid.timeout_ms = 4321

assert(
  #mermaid.parse(context) == 0 and #process_requests == 1,
  'Initial Markdown parsing did not automatically try the Mermaid renderer'
)
local render_request = process_requests[1]
local window_info = vim.fn.getwininfo(0)[1] or { textoff = 0 }
local expected_width = math.max(1, math.floor(
  (vim.api.nvim_win_get_width(0) - window_info.textoff) * 0.85
))
assert(
  render_request.command[1] == '/test/bin/termaid'
    and render_request.command[2] == '--width'
    and tonumber(render_request.command[3]) == expected_width,
  'Mermaid renderer did not receive the expanded near-80-percent view width'
)
assert(
  render_request.command[4] == '--strict-width'
    and render_request.command[5] == '--fit-mode'
    and render_request.command[6] == 'reflow'
    and render_request.command[7] == '--max-height'
    and tonumber(render_request.command[8]) == mermaid.max_rendered_lines
    and render_request.command[9] == '--format'
    and render_request.command[10] == 'styled-json',
  'Mermaid renderer did not request strict bounded semantic output'
)
assert(
  render_request.options.stdin == 'graph LR\n  A --> B'
    and render_request.options.text == true
    and render_request.options.timeout == 4321,
  'Mermaid renderer lost its source, text mode, or timeout budget'
)
render_request.callback({
  code = 0,
  stderr = '',
  stdout = colorful_output,
})
assert(vim.wait(100, function()
  return refreshes == 1
end, 1), 'Completed Mermaid rendering did not use the shared refresh pipeline')

assert(#mermaid.parse(context) == 0, 'Mermaid leaked plugin-managed render marks')
local marks = mermaid.stage(buffer, 0)
assert(#marks == 4, 'Inactive Mermaid output lost its label, fence, or source rows')
local inactive_label = marks[1]
assert(
  inactive_label.row == 1
    and inactive_label.options.priority == 201
    and inactive_label.options.virt_text_pos == 'overlay'
    and inactive_label.options.virt_text[1][1] == '󰙅 '
    and inactive_label.options.virt_text[1][2] == 'RenderMarkdownMermaidIcon'
    and inactive_label.options.virt_text[2][1] == 'mermaid'
    and inactive_label.options.virt_text[2][2] == 'RenderMarkdownMermaidLabel',
  'Inactive Mermaid fence did not keep its table-style icon label'
)
assert(
  marks[2].row == 4
    and marks[2].options.conceal_lines == ''
    and marks[2].options.priority == 201,
  'Successful Mermaid rendering did not hide its closing fence'
)
local rendered_lines = {}
for mark_index = 3, #marks do
  local mark = marks[mark_index]
  assert(
    mark.row == mark_index - 1
      and mark.options.conceal_lines == nil
      and mark.options.virt_text_pos == 'overlay',
    'Mermaid output is not a persistent source-backed overlay'
  )
  local primary = table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, mark.options.virt_text)):gsub('%s+$', '')
  rendered_lines[#rendered_lines + 1] = primary
  for _, virtual_line in ipairs(mark.options.virt_lines or {}) do
    rendered_lines[#rendered_lines + 1] = table.concat(vim.tbl_map(function(chunk)
      return chunk[1]
    end, virtual_line))
  end
end
local rendered_text = table.concat(rendered_lines, '\n')
assert(
  rendered_text == '┌─►\n│ A │\n└───┘',
  'Mermaid output was changed before inline display'
)
local semantic_highlights = {}
for mark_index = 3, #marks do
  local options = marks[mark_index].options
  for _, chunks in ipairs(vim.list_extend(
    { options.virt_text },
    options.virt_lines or {}
  )) do
    for _, chunk in ipairs(chunks) do
      semantic_highlights[chunk[2]] = true
    end
  end
end
assert(
  semantic_highlights.RenderMarkdownMermaidNode
    and semantic_highlights.RenderMarkdownMermaidEdge
    and semantic_highlights.RenderMarkdownMermaidArrow
    and semantic_highlights.RenderMarkdownMermaidContentLabel,
  'Inline Mermaid rendering flattened semantic color chunks'
)
assert(
  #mermaid.parse(context) == 0
    and #mermaid.stage(buffer, 0) == 4
    and #process_requests == 1,
  'Cached Mermaid output started a duplicate process'
)

mermaid.render({ buf = buffer, win = 0 })
local feature_namespace = vim.api.nvim_get_namespaces().markdown_features
assert(
  feature_namespace
    and #vim.api.nvim_buf_get_extmarks(
      buffer,
      feature_namespace,
      0,
      -1,
      {}
    ) == 4,
  'Mermaid output did not use the shared persistent Markdown extmark pipeline'
)

local function has_highlight(chunks, expected)
  for _, chunk in ipairs(chunks or {}) do
    local highlights = type(chunk[2]) == 'table' and chunk[2] or { chunk[2] }
    if vim.tbl_contains(highlights, expected) then
      return true
    end
  end
  return false
end

vim.api.nvim_win_set_cursor(0, { 3, 2 })
mermaid.render({ buf = buffer, win = 0 })
assert(refreshes == 1, 'Moving in Mermaid source requested a redundant full refresh')
marks = mermaid.stage(buffer, 0)
assert(#marks == 4, 'Active Mermaid lost its persistent icon tag')
local label = marks[1]
assert(
  label.row == 1
    and label.options.priority == 201
    and label.options.virt_text_pos == 'overlay'
    and label.options.virt_text[1][1] == '󰙅 '
    and label.options.virt_text[1][2] == 'RenderMarkdownMermaidIcon'
    and label.options.virt_text[2][1] == 'mermaid'
    and label.options.virt_text[2][2] == 'RenderMarkdownMermaidLabel',
  'Active Mermaid fence did not keep its dedicated icon tag'
)
local rendered_cursor = false
local rendered_cursor_line = false
for mark_index = 3, #marks do
  local options = marks[mark_index].options
  rendered_cursor = rendered_cursor
    or has_highlight(options.virt_text, 'Cursor')
  rendered_cursor_line = rendered_cursor_line
    or has_highlight(options.virt_text, 'CursorLine')
  for _, virtual_line in ipairs(options.virt_lines or {}) do
    rendered_cursor = rendered_cursor
      or has_highlight(virtual_line, 'Cursor')
    rendered_cursor_line = rendered_cursor_line
      or has_highlight(virtual_line, 'CursorLine')
  end
end
assert(rendered_cursor, 'Mermaid cursor did not follow the rendered diagram')
assert(rendered_cursor_line, 'Mermaid cursor row did not receive CursorLine styling')
assert(
  vim.o.guicursor:find('RenderMarkdownMermaidHiddenCursor', 1, true),
  'Mermaid render did not hide the native source cursor'
)

vim.api.nvim_win_set_cursor(0, { 1, 0 })
mermaid.render({ buf = buffer, win = 0 })
assert(refreshes == 1, 'Leaving Mermaid source requested a redundant full refresh')
assert(
  vim.o.guicursor == original.guicursor,
  'Leaving Mermaid source did not restore the native cursor'
)

mermaid.detach(buffer)
assert(
  #vim.api.nvim_buf_get_extmarks(buffer, feature_namespace, 0, -1, {}) == 0,
  'Mermaid teardown did not clear its shared Markdown feature marks'
)

refreshes = 0
process_requests = {}
mermaid.find_executable = function()
  return '/test/bin/old-termaid'
end
assert(#mermaid.parse(context) == 0 and #process_requests == 1)
process_requests[1].callback({
  code = 2,
  stderr = 'error: unrecognized arguments: --format styled-json',
  stdout = '',
})
assert(vim.wait(100, function()
  return #process_requests == 2
end, 1), 'Older Termaid did not receive a bounded plain-output retry')
assert(
  not vim.tbl_contains(process_requests[2].command, '--format'),
  'Mermaid plain fallback retained the unsupported styled-output option'
)
process_requests[2].callback({ code = 0, stdout = 'plain fallback' })
assert(vim.wait(100, function()
  return refreshes == 1
end, 1), 'Mermaid plain fallback did not settle through the shared pipeline')
assert(#mermaid.stage(buffer, 0) == 4, 'Mermaid plain fallback was not rendered')

mermaid.detach(buffer)
refreshes = 0
process_requests = {}
mermaid.find_executable = function()
  return '/test/bin/termaid'
end
assert(#mermaid.parse(context) == 0, 'A fresh Mermaid render was not pending')
process_requests[1].callback({ code = 1, stderr = 'invalid graph', stdout = '' })
assert(vim.wait(100, function()
  return refreshes == 1
end, 1), 'Failed Mermaid rendering did not settle through the shared pipeline')
assert(
  #mermaid.parse(context) == 0 and #process_requests == 1,
  'Failed Mermaid rendering did not retain raw source without retrying'
)

mermaid.detach(buffer)
process_requests = {}
assert(#mermaid.parse(context) == 0 and #process_requests == 1)
vim.api.nvim_buf_set_lines(buffer, 3, 4, false, { '  A --> Changed' })
local changed_tree = assert(vim.treesitter.get_parser(buffer, 'markdown'):parse()[1])
local changed_context = { buf = buffer, root = changed_tree:root() }
assert(#mermaid.parse(changed_context) == 0 and #process_requests == 2)
assert(
  killed_processes >= 1,
  'Editing Mermaid source did not cancel the stale renderer generation'
)
process_requests[1].callback({ code = 0, stdout = 'stale output' })
vim.wait(20)
assert(refreshes == 1, 'A stale Mermaid callback requested another render')

mermaid.detach(buffer)
vim.api.nvim_buf_delete(buffer, { force = true })

local budget_buffer, budget_context = fixture({
  '```mermaid', 'graph LR', 'A --> B', '```',
  '```mermaid', 'graph LR', 'C --> D', '```',
  '```mermaid', 'graph LR', 'E --> F', '```',
})
process_requests = {}
mermaid.max_concurrent = 2
assert(#mermaid.parse(budget_context) == 0)
assert(
  #process_requests == 2,
  'Mermaid render concurrency exceeded or failed to fill its two-job budget'
)
process_requests[1].callback({ code = 0, stdout = styled_output({ {
  { text = 'first', style = 'label' },
} }) })
assert(vim.wait(100, function()
  return #process_requests == 3
end, 1), 'Mermaid render queue did not start the next bounded job')

mermaid.detach(budget_buffer)
vim.api.nvim_buf_delete(budget_buffer, { force = true })
mermaid.find_executable = original.find_executable
mermaid.max_concurrent = original.max_concurrent
mermaid.start_process = original.start_process
mermaid.timeout_ms = original.timeout
mermaid.width_ratio = original.width_ratio
markdown_features.request_render = original.feature_request_render
package.loaded['render-markdown.request.context'] = original.request_context
vim.o.guicursor = original.guicursor
vim.api.nvim_set_current_buf(original.buffer)
