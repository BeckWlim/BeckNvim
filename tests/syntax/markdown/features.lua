local features = require('config.syntax.markdown_features')
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'before', 'table source', 'mermaid source', 'after' })
local rows = features.project({
  { project = function() return { { start_row = 1, end_row = 2, rows = {
    { chunks = { { 'wrapped first', 'Normal' } }, source_row = 1, spans = { { first = 0, last = 7, source_column = 0 } } },
    { chunks = { { 'wrapped second', 'Normal' } }, source_row = 1, spans = { { first = 0, last = 7, source_column = 6 } } },
  } } } end },
  { project = function() return { { start_row = 2, end_row = 3, rows = {
    { chunks = { { 'diagram', 'Normal' } }, source_row = 2 },
  } } } end },
}, { buf = buffer })
assert(#rows == 5 and rows[1].identity and rows[5].identity, 'Shared projection lost surrounding prose')
assert(vim.deep_equal(features.source_position(rows[3], 2), { 2, 6 }), 'Wrapped row lost its source byte mapping')
assert(vim.deep_equal(features.source_position(rows[5], 2), { 4, 2 }), 'Prose source mapping changed its column')
assert(vim.deep_equal(features.preview_position(rows, 1, 6), { 3, 0 }), 'Source navigation did not select the matching continuation')
local refreshes = 0
features.subscribe(buffer, function() refreshes = refreshes + 1 end)
features.request_render(buffer, 'table')
features.request_render(buffer, 'mermaid')
assert(vim.wait(100, function() return refreshes == 1 end), 'Feature refreshes were not coalesced')
features.request_render(buffer)
features.forget_buffer(buffer)
vim.wait(10)
assert(refreshes == 1, 'Closed preview accepted a stale refresh')
vim.api.nvim_buf_delete(buffer, { force = true })
