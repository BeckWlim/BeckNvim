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
local translation_content = vim.api.nvim_get_hl(0, {
  name = 'TranslationContent',
  link = false,
})
local translation_notification = vim.api.nvim_get_hl(0, {
  name = 'TranslationNotification',
  link = false,
})
local translation_separator = vim.api.nvim_get_hl(0, {
  name = 'TranslationSeparator',
  link = false,
})
local telescope_normal = vim.api.nvim_get_hl(0, { name = 'TelescopeNormal', link = false })
local diffview_normal = vim.api.nvim_get_hl(0, { name = 'DiffviewNormal', link = false })
local telescope_border = vim.api.nvim_get_hl(0, { name = 'TelescopeBorder', link = false })
local diffview_separator = vim.api.nvim_get_hl(0, {
  name = 'DiffviewWinSeparator',
  link = false,
})
local telescope_selection = vim.api.nvim_get_hl(0, {
  name = 'TelescopeSelection',
  link = false,
})
local diffview_selection = vim.api.nvim_get_hl(0, {
  name = 'DiffviewFilePanelSelected',
  link = false,
})
local diffview_addition = vim.api.nvim_get_hl(0, {
  name = 'DiffviewDiffAdd',
  link = false,
})
local diffview_deletion = vim.api.nvim_get_hl(0, {
  name = 'DiffviewDiffAddAsDelete',
  link = false,
})
local diffview_change = vim.api.nvim_get_hl(0, {
  name = 'DiffviewDiffChange',
  link = false,
})
local git_local_tag = vim.api.nvim_get_hl(0, { name = 'GitHistoryLocalTag', link = false })
local git_remote_tag = vim.api.nvim_get_hl(0, { name = 'GitHistoryRemoteTag', link = false })
local treesitter_context = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContext',
  link = false,
})
local treesitter_context_bottom = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContextBottom',
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
assert(
  cursor_line.bg and cursor_line.underline ~= true,
  'editor cursor line must use a background without an underline'
)
assert(detail_cursor_line.bg == cursor_line.bg, 'detail cursor line uses a different color')
assert(translation_content.bold, 'translation content must be visually emphasized')
assert(translation_notification.italic, 'translation notifications must remain secondary')
assert(
  translation_content.fg ~= translation_notification.fg,
  'translation content and notifications use the same foreground color'
)
assert(
  translation_separator.fg ~= translation_content.fg,
  'translation dividers compete with translated content'
)
assert(
  telescope_normal.bg == diffview_normal.bg and telescope_normal.fg == diffview_normal.fg,
  'Telescope and Diffview do not share one Git/search plane palette'
)
assert(
  telescope_border.fg == diffview_separator.fg,
  'Telescope borders and Diffview separators use different colors'
)
assert(
  telescope_selection.bg == diffview_selection.bg,
  'Telescope and Diffview selections use different backgrounds'
)
assert(diffview_addition.bg, 'Diffview additions lost their restrained background tint')
assert(diffview_addition.fg == nil, 'Diffview additions override syntax foreground colors')
assert(diffview_deletion.bg, 'Diffview deletions lost their restrained background tint')
assert(diffview_deletion.fg == nil, 'Diffview deletions override syntax foreground colors')
assert(diffview_change.bg, 'Diffview modifications lost their restrained background tint')
assert(diffview_change.fg == nil, 'Diffview modifications override syntax foreground colors')
assert(
  treesitter_context.bg == tonumber('405A45', 16),
  'Pinned code context lost its light-green code-pane background'
)
assert(
  treesitter_context_bottom.underline ~= true,
  'Pinned code context restored its obsolete underline'
)
assert(
  git_local_tag.fg and git_local_tag.bg,
  'Local Git search-result tag is not visible against the shared history plane'
)
assert(
  git_remote_tag.fg and git_remote_tag.bg and git_remote_tag.fg ~= git_local_tag.fg,
  'Remote Git search-result tag is not distinct on the shared history plane'
)
