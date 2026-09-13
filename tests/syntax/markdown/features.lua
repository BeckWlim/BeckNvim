-- Focused tests for the reusable Markdown feature pipeline.
local features = require('config.syntax.markdown_features')

local original_buffer = vim.api.nvim_get_current_buf()
local original_guicursor = vim.o.guicursor
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'table', 'mermaid', 'cursor' })
vim.api.nvim_set_current_buf(buffer)

local function staged(key, row, text)
  return {
    key = key,
    options = {
      strict = false,
      virt_text = { { text, 'Normal' } },
      virt_text_pos = 'overlay',
    },
    row = row,
  }
end

features.apply('table', buffer, { staged('table:row', 0, 'TABLE') })
features.apply('mermaid', buffer, { staged('mermaid:row', 1, 'MERMAID') })
local namespace = vim.api.nvim_get_namespaces().markdown_features
assert(
  #vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 2,
  'Markdown features did not share one persistent extmark namespace'
)

features.update('table', buffer, { staged('table:row', 0, 'UPDATED') })
features.clear('table', buffer)
assert(
  #vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 1,
  'Clearing one Markdown feature removed another feature\'s marks'
)

local interaction = {
  cursor = { column = 3, row = 2 },
  mode = 'n',
}
local window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 3, 3 })
assert(
  features.park_cursor('mermaid', buffer, window, interaction)
    and vim.api.nvim_win_get_cursor(0)[2] == 0
    and features.parked_interaction('mermaid', buffer, window) == interaction,
  'Markdown feature cursor parking lost its logical source position'
)
features.release_cursor('mermaid', buffer, window, true)
assert(
  vim.api.nvim_win_get_cursor(0)[2] == 3,
  'Markdown feature cursor release did not restore its source position'
)

features.park_cursor(
  'mermaid',
  buffer,
  window,
  interaction,
  'RenderMarkdownMermaidHiddenCursor'
)
local table_interaction = {
  cursor = { column = 2, row = 2 },
  mode = 'n',
}
features.park_cursor(
  'table',
  buffer,
  window,
  table_interaction,
  'RenderMarkdownTableHiddenCursor'
)
features.release_cursor('mermaid', buffer, window, false)
assert(
  vim.o.guicursor:find('RenderMarkdownTableHiddenCursor', 1, true)
    and not vim.o.guicursor:find('RenderMarkdownMermaidHiddenCursor', 1, true),
  'Switching Markdown features stacked or cleared the active cursor style'
)
features.release_cursor('table', buffer, window, true)
assert(
  vim.o.guicursor == original_guicursor,
  'Markdown feature cursor teardown did not restore the native cursor style'
)

local calls = {}
local handlers = {
  { render = function() calls[#calls + 1] = 'table' end },
  { render = function() calls[#calls + 1] = 'mermaid' end },
}
features.dispatch(handlers, 'render', { buf = buffer, win = 0 })
assert(
  vim.deep_equal(calls, { 'table', 'mermaid' }),
  'Markdown feature lifecycle dispatch changed feature order'
)

features.clear('mermaid', buffer)
features.forget_buffer(buffer)
vim.o.guicursor = original_guicursor
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(buffer, { force = true })
