require('config.syntax.highlights').setup()

local normal_highlight = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
local tree_normal = vim.api.nvim_get_hl(0, { name = 'NvimTreeNormal', link = false })
local tree_normal_nc = vim.api.nvim_get_hl(0, { name = 'NvimTreeNormalNC', link = false })
local tree_sign_column = vim.api.nvim_get_hl(0, { name = 'NvimTreeSignColumn', link = false })
local tree_end_of_buffer = vim.api.nvim_get_hl(0, {
  name = 'NvimTreeEndOfBuffer',
  link = false,
})
local cursor_line = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false })
local tree_cursor_line = vim.api.nvim_get_hl(0, { name = 'NvimTreeCursorLine', link = false })
local detail_cursor_line = vim.api.nvim_get_hl(0, {
  name = 'TypeInformationCursorLine',
  link = false,
})

assert(tree_normal.bg == normal_highlight.bg, 'file tree background differs from the editor')
assert(tree_normal_nc.bg == tree_normal.bg, 'inactive file tree changes its background')
assert(tree_sign_column.bg == tree_normal.bg, 'file tree sign column creates a background strip')
assert(
  tree_end_of_buffer.bg == tree_normal.bg,
  'file tree end-of-buffer region creates a background patch'
)
assert(tree_cursor_line.bg == cursor_line.bg, 'file tree cursor line uses a different color')
assert(detail_cursor_line.bg == cursor_line.bg, 'detail cursor line uses a different color')
