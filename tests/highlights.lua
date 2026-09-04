require('config.syntax.highlights').setup()

local normal_highlight = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
local normal_float = vim.api.nvim_get_hl(0, { name = 'NormalFloat', link = false })
local popup_menu = vim.api.nvim_get_hl(0, { name = 'Pmenu', link = false })
local popup_menu_selection = vim.api.nvim_get_hl(0, { name = 'PmenuSel', link = false })
local completion_match = vim.api.nvim_get_hl(0, {
  name = 'CmpItemAbbrMatch',
  link = false,
})
local tree_normal = vim.api.nvim_get_hl(0, { name = 'NvimTreeNormal', link = false })
local tree_normal_nc = vim.api.nvim_get_hl(0, { name = 'NvimTreeNormalNC', link = false })
local tree_sign_column = vim.api.nvim_get_hl(0, { name = 'NvimTreeSignColumn', link = false })
local tree_end_of_buffer = vim.api.nvim_get_hl(0, {
  name = 'NvimTreeEndOfBuffer',
  link = false,
})
local cursor_line = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false })
local color_column = vim.api.nvim_get_hl(0, { name = 'ColorColumn', link = false })
local inline_code = vim.api.nvim_get_hl(0, {
  name = '@markup.raw.markdown_inline',
  link = false,
})
local tree_cursor_line = vim.api.nvim_get_hl(0, { name = 'NvimTreeCursorLine', link = false })
local detail_cursor_line = vim.api.nvim_get_hl(0, {
  name = 'TypeInformationCursorLine',
  link = false,
})
local markdown_heading_four = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownH4',
  link = false,
})
local markdown_heading_four_background = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownH4Bg',
  link = false,
})
local markdown_table_rule = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableRule',
  link = false,
})
local markdown_table_row_rule = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableRowRule',
  link = false,
})
local markdown_table_header = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableHeader',
  link = false,
})
local markdown_table_cell = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableCell',
  link = false,
})
local markdown_table_code = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableCode',
  link = false,
})
local markdown_table_source = vim.api.nvim_get_hl(0, {
  name = '@markup.table.markdown',
  link = false,
})
local markdown_table_icon = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableIcon',
  link = false,
})
local markdown_table_label = vim.api.nvim_get_hl(0, {
  name = 'RenderMarkdownTableLabel',
  link = false,
})
local translation_content = vim.api.nvim_get_hl(0, {
  name = 'TranslationContent',
  link = false,
})
local translation_float = vim.api.nvim_get_hl(0, {
  name = 'TranslationFloat',
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
local telescope_selection_caret = vim.api.nvim_get_hl(0, {
  name = 'TelescopeSelectionCaret',
  link = false,
})
local telescope_matching = vim.api.nvim_get_hl(0, {
  name = 'TelescopeMatching',
  link = false,
})
local telescope_prompt_prefix = vim.api.nvim_get_hl(0, {
  name = 'TelescopePromptPrefix',
  link = false,
})
local telescope_preview_line = vim.api.nvim_get_hl(0, {
  name = 'TelescopePreviewLine',
  link = false,
})
local telescope_preview_match = vim.api.nvim_get_hl(0, {
  name = 'TelescopePreviewMatch',
  link = false,
})
local telescope_title = vim.api.nvim_get_hl(0, {
  name = 'TelescopeResultsTitle',
  link = false,
})
local diffview_title = vim.api.nvim_get_hl(0, {
  name = 'DiffviewFilePanelTitle',
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
local treesitter_context = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContext',
  link = false,
})
local treesitter_context_bottom = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContextBottom',
  link = false,
})
local treesitter_context_preview = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContextPreview',
  link = false,
})
local treesitter_context_preview_separator = vim.api.nvim_get_hl(0, {
  name = 'TreesitterContextPreviewSeparator',
  link = false,
})

assert(tree_normal.bg == normal_highlight.bg, 'file tree background differs from the editor')
assert(
  normal_float.bg == normal_highlight.bg and normal_float.fg == normal_highlight.fg,
  'ordinary floating windows do not share the editor base palette'
)
assert(
  popup_menu.bg == normal_highlight.bg and popup_menu.fg == normal_highlight.fg,
  'completion menu does not share the editor base palette'
)
assert(
  popup_menu_selection.bg == cursor_line.bg and popup_menu_selection.fg == normal_highlight.fg,
  'completion selection does not share the editor focus treatment'
)
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
assert(
  markdown_heading_four.fg == tonumber('FFB3D1', 16) and markdown_heading_four.bold,
  'level-four Markdown heading marker lost its visible accent'
)
assert(
  markdown_heading_four_background.bg == tonumber('363139', 16)
    and markdown_heading_four_background.fg == tonumber('F8F8F2', 16)
    and markdown_heading_four_background.bold,
  'level-four Markdown heading text lost its high-contrast treatment'
)
assert(
  markdown_table_rule.bg == color_column.bg
    and markdown_table_rule.fg == tonumber('49483E', 16)
    and markdown_table_rule.fg ~= normal_highlight.fg,
  'Markdown table rules are not muted below normal text'
)
assert(
  markdown_table_row_rule.bg == color_column.bg
    and markdown_table_row_rule.fg == tonumber('3E3D32', 16)
    and markdown_table_row_rule.fg ~= normal_highlight.fg,
  'Markdown body-row separators are not quieter than ordinary text'
)
assert(
  markdown_table_header.bg == color_column.bg
    and markdown_table_header.fg == normal_highlight.fg
    and markdown_table_header.bold
    and markdown_table_cell.bg == color_column.bg
    and markdown_table_cell.fg == normal_highlight.fg
    and markdown_table_code.bg == cursor_line.bg
    and markdown_table_code.bg ~= markdown_table_cell.bg
    and markdown_table_code.fg == inline_code.fg
    and markdown_table_source.bg == color_column.bg,
  'Markdown table body or inline-code key mark uses the wrong semantic color'
)
assert(
  markdown_table_icon.bg == color_column.bg
    and markdown_table_icon.fg == tonumber('89E051', 16)
    and markdown_table_icon.bold
    and markdown_table_label.bg == color_column.bg
    and markdown_table_label.fg == tonumber('A6A69C', 16),
  'Markdown table label does not match the fenced-text identity'
)
assert(
  translation_float.bg == normal_highlight.bg and translation_float.fg == normal_highlight.fg,
  'translation surface does not share the editor base palette'
)
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
  telescope_normal.bg == normal_highlight.bg
    and telescope_normal.fg == normal_highlight.fg
    and diffview_normal.bg == normal_highlight.bg
    and diffview_normal.fg == normal_highlight.fg,
  'Telescope and Diffview do not share the editor base palette'
)
for _, group_name in ipairs({
  'TelescopePromptNormal',
  'TelescopeResultsNormal',
  'TelescopePreviewNormal',
}) do
  local plane_highlight = vim.api.nvim_get_hl(0, { name = group_name, link = false })
  assert(
    plane_highlight.bg == telescope_normal.bg and plane_highlight.fg == telescope_normal.fg,
    group_name .. ' left the shared neutral search plane'
  )
end
for _, group_name in ipairs({
  'TelescopePromptBorder',
  'TelescopeResultsBorder',
  'TelescopePreviewBorder',
}) do
  local edge_highlight = vim.api.nvim_get_hl(0, { name = group_name, link = false })
  assert(
    edge_highlight.bg == telescope_normal.bg and edge_highlight.fg == telescope_border.fg,
    group_name .. ' left the shared grey edge treatment'
  )
end
assert(
  telescope_border.fg == diffview_separator.fg,
  'Telescope borders and Diffview separators use different colors'
)
assert(
  telescope_border.fg == tonumber('666666', 16)
    and telescope_title.fg == normal_highlight.fg,
  'Git/search edge or title left the neutral editor palette'
)
assert(
  telescope_selection.bg == cursor_line.bg
    and telescope_selection.fg == normal_highlight.fg
    and telescope_selection.bg ~= telescope_normal.bg,
  'Search selection lost the editor cursor-line treatment'
)
assert(
  telescope_selection_caret.fg == telescope_matching.fg
    and telescope_matching.fg == telescope_prompt_prefix.fg
    and telescope_matching.fg == telescope_preview_match.fg
    and telescope_matching.fg == completion_match.fg
    and telescope_matching.fg == tonumber('FFFFFF', 16),
  'Search/completion matches, prompt, and selection caret do not share the neutral focus accent'
)
assert(
  telescope_preview_line.bg == telescope_selection.bg
    and telescope_preview_line.fg == telescope_selection.fg,
  'Search preview targets do not reuse the shared selection treatment'
)
assert(
  telescope_title.fg == diffview_title.fg,
  'Telescope and Diffview headings use different neutral emphasis colors'
)
for _, group_name in ipairs({
  'DiffviewFilePanelFileName',
  'DiffviewFilePanelPath',
  'DiffviewFilePanelCounter',
  'DiffviewHash',
}) do
  local footer_highlight = vim.api.nvim_get_hl(0, { name = group_name, link = false })
  assert(
    footer_highlight.bg == normal_highlight.bg,
    group_name .. ' does not share the editor and search background'
  )
end
for group_name, expected_color in pairs({
  DiffviewFilePanelCounter = '66D9EF',
  DiffviewFilePanelDeletions = 'F92672',
  DiffviewFilePanelInsertions = 'A6E22E',
  DiffviewHash = 'AE81FF',
  DiffviewStatusAdded = 'A6E22E',
  DiffviewStatusDeleted = 'F92672',
  DiffviewStatusModified = 'E6DB74',
}) do
  local footer_highlight = vim.api.nvim_get_hl(0, { name = group_name, link = false })
  assert(
    footer_highlight.fg == tonumber(expected_color, 16),
    group_name .. ' lost its saturated Git-semantic foreground'
  )
end
assert(diffview_addition.bg, 'Diffview additions lost their restrained background tint')
assert(diffview_addition.fg == nil, 'Diffview additions override syntax foreground colors')
assert(diffview_deletion.bg, 'Diffview deletions lost their restrained background tint')
assert(diffview_deletion.fg == nil, 'Diffview deletions override syntax foreground colors')
assert(diffview_change.bg, 'Diffview modifications lost their restrained background tint')
assert(diffview_change.fg == nil, 'Diffview modifications override syntax foreground colors')
assert(
  treesitter_context.bg == tonumber('3A3D32', 16),
  'Pinned code context lost its restrained light-green declaration background'
)
assert(
  treesitter_context_bottom.underline == true
    and treesitter_context_bottom.sp == tonumber('A6E22E', 16),
  'Pinned code context lost its distinct green lower boundary'
)
assert(
  treesitter_context_preview.bg == treesitter_context.bg
    and treesitter_context_preview.underline == true
    and treesitter_context_preview.sp == treesitter_context_bottom.sp
    and treesitter_context_preview_separator.bg == treesitter_context.bg
    and treesitter_context_preview_separator.underline == true
    and treesitter_context_preview_separator.sp == treesitter_context_bottom.sp,
  'Search preview context does not share the declaration background and lower boundary'
)
