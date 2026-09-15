-- Shared palette contracts across project surfaces and real dark/light themes.
local highlights = require('config.syntax.highlights')
local palette = require('config.ui.palette')
local previous_theme = vim.g.colors_name or 'default'
local previous_background = vim.o.background
local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end
local function contrast_text(name, background)
  local role = hl(name)
  assert(role.fg and palette.contrast(role.fg, role.bg or background) >= 4.5,
    name .. ' text has insufficient contrast')
end
local function check_surfaces()
  local normal = hl('Normal')
  local cursor = hl('CursorLine')
  local block = hl('RenderMarkdownTableCell')
  for _, name in ipairs({ 'StatusLine', 'StatusLineNC' }) do
    local footer = hl(name)
    assert(footer.bg ~= normal.bg and palette.contrast(footer.bg, normal.bg) < 1.5,
      name .. ' must have subtle contrast with the editor')
    contrast_text(name, normal.bg)
  end
  assert(palette.contrast(hl('StatusLineNC').bg, normal.bg)
      < palette.contrast(hl('StatusLine').bg, normal.bg), 'Inactive footer is too prominent')
  for _, name in ipairs({
    'NormalFloat', 'Pmenu', 'NvimTreeNormal', 'NvimTreeNormalNC',
    'TelescopeNormal', 'TelescopePromptNormal', 'TelescopeResultsNormal', 'TelescopePreviewNormal',
    'DiffviewNormal', 'TranslationFloat', 'TranslationContent', 'TranslationDictionary',
  }) do
    local role = hl(name)
    assert(role.bg == normal.bg and role.fg == normal.fg, name .. ' left the editor base plane')
  end
  assert(hl('NormalNC').bg == normal.bg and not hl('NormalNC').fg,
    'Inactive windows must share the editor background and retain their own foreground')
  for _, name in ipairs({
    'PmenuSel', 'NvimTreeCursorLine', 'TypeInformationCursorLine', 'TelescopeSelection', 'TelescopePreviewLine',
  }) do
    assert(hl(name).bg == cursor.bg, name .. ' left the shared selection background')
  end
  assert(cursor.bg ~= normal.bg and palette.contrast(normal.fg, cursor.bg) >= 4.5,
    'Selection does not remain visible and readable')
  assert(hl('CurrentCodeScope').bg ~= normal.bg and hl('CurrentCodeScope').bg ~= cursor.bg,
    'Scope and cursor backgrounds lost their hierarchy')
  local border = hl('FloatBorder')
  for _, name in ipairs({
    'DiffviewWinSeparator', 'PmenuFloatBorder',
  }) do
    assert(hl(name).fg == border.fg and hl(name).bg == normal.bg, name .. ' lost shared border styling')
  end
  for _, name in ipairs({
    'TelescopeBorder', 'TelescopePromptBorder', 'TelescopeResultsBorder', 'TelescopePreviewBorder',
  }) do
    assert(hl(name).fg == border.fg and hl(name).bg == normal.bg
        and palette.contrast(hl(name).fg, normal.bg) >= 3,
      name .. ' must contrast its edge without changing the margin background')
  end
  for _, name in ipairs({ 'NvimTreeSignColumn', 'NvimTreeEndOfBuffer' }) do
    assert(hl(name).bg == normal.bg, name .. ' introduces a background strip')
  end
  for _, name in ipairs({
    'TelescopeTitle', 'TelescopePromptTitle', 'TelescopeResultsTitle', 'TelescopePreviewTitle',
    'DiffviewFilePanelTitle', 'DiffviewFilePanelRootPath',
  }) do
    assert(hl(name).fg == normal.fg and hl(name).bold, name .. ' lost neutral title emphasis')
  end
  local focus = hl('TelescopeMatching').fg
  for _, name in ipairs({
    'TelescopeSelectionCaret', 'TelescopePromptPrefix', 'TelescopePreviewMatch', 'CmpItemAbbrMatch',
  }) do
    assert(hl(name).fg == focus, name .. ' lost the shared focus foreground')
  end
  assert(hl('RenderMarkdownH4').bold and hl('RenderMarkdownH4Bg').bold, 'Heading emphasis was removed')
  assert(hl('RenderMarkdownTableHeader').bold, 'Table header lost emphasis')
  for _, name in ipairs({
    'RenderMarkdownTableRule', 'RenderMarkdownTableRowRule', 'RenderMarkdownTableHeader',
    'RenderMarkdownTableIcon', 'RenderMarkdownTableLabel', '@markup.table.markdown',
    'RenderMarkdownMermaid', 'RenderMarkdownMermaidNode', 'RenderMarkdownMermaidEdge',
    'RenderMarkdownMermaidArrow', 'RenderMarkdownMermaidContentLabel', 'RenderMarkdownMermaidEdgeLabel',
    'RenderMarkdownMermaidSubgraph', 'RenderMarkdownMermaidSubgraphLabel',
    'RenderMarkdownMermaidActive', 'RenderMarkdownMermaidCritical', 'RenderMarkdownMermaidDone',
    'RenderMarkdownMermaidItalicLabel', 'RenderMarkdownMermaidBoldLabel',
    'RenderMarkdownMermaidMilestone', 'RenderMarkdownMermaidIcon', 'RenderMarkdownMermaidLabel',
  }) do
    assert(hl(name).bg == block.bg, name .. ' left the code block plane')
  end
  for index = 1, 8 do
    assert(hl('RenderMarkdownMermaidSection' .. index).bg == block.bg,
      'Mermaid section lost the table background')
  end
  local colors = palette.resolve()
  assert(hl('RenderMarkdownTableIcon').fg == colors.table.icon, 'Table icon lost its semantic accent')
  assert(hl('RenderMarkdownMermaidIcon').fg == colors.mermaid.icon, 'Mermaid icon lost its semantic accent')
  for _, feature in ipairs({ 'Table', 'Mermaid' }) do
    local icon = hl('RenderMarkdown' .. feature .. 'Icon')
    local label = hl('RenderMarkdown' .. feature .. 'Label')
    assert(icon.fg == label.fg and label.fg ~= colors.muted,
      feature .. ' icon and label do not share a distinct semantic accent')
    contrast_text('RenderMarkdown' .. feature .. 'Label', block.bg)
  end
  assert(hl('RenderMarkdownTableCode').bg == cursor.bg, 'Inline code lost shared selection background')
  for _, name in ipairs({ 'RenderMarkdownMermaidContentLabel', 'RenderMarkdownMermaidEdgeLabel' }) do
    assert(hl(name).fg == normal.fg and not hl(name).bold and not hl(name).italic,
      name .. ' must share plain readable text')
    assert(hl(name).fg ~= hl('RenderMarkdownMermaidEdge').fg
      and hl(name).fg ~= hl('RenderMarkdownMermaidArrow').fg, 'Connector and label colors merged')
  end
  assert(hl('RenderMarkdownMermaidArrow').bold, 'Arrowheads lost emphasis')
  assert(hl('RenderMarkdownMermaidBoldLabel').bold, 'Explicit bold labels lost emphasis')
  assert(hl('RenderMarkdownMermaidItalicLabel').italic, 'Explicit italic labels lost styling')
  assert(not hl('RenderMarkdownMermaidSubgraphLabel').bold, 'Scope hints gained blanket emphasis')
  assert(hl('TranslationContent').bold and hl('TranslationNotification').italic,
    'Translation content and notification hierarchy changed')
  for _, name in ipairs({ 'DiffviewDiffAdd', 'DiffviewDiffAddAsDelete', 'DiffviewDiffChange',
    'DiffviewDiffText' }) do
    assert(hl(name).bg and not hl(name).fg, name .. ' overrides syntax foreground')
  end
  assert(hl('DiffviewStatusAdded').fg == hl('DiffviewFilePanelInsertions').fg,
    'Git additions use inconsistent colors')
  assert(hl('DiffviewStatusDeleted').fg == hl('DiffviewFilePanelDeletions').fg,
    'Git deletions use inconsistent colors')
  local context = hl('TreesitterContext')
  local boundary = hl('TreesitterContextBottom')
  assert(context.bg ~= normal.bg and boundary.underline and boundary.sp,
    'Pinned context lost its tint and lower boundary')
  assert(hl('TreesitterContextPreview').bg == context.bg
    and hl('TreesitterContextPreview').sp == boundary.sp
    and hl('TreesitterContextPreviewSeparator').bg == context.bg,
    'Preview context does not share the pinned context treatment')
  for _, name in ipairs({
    'PmenuSel', 'CmpItemAbbr', 'CmpItemMenu', 'TypeInformationHint', 'DashboardFile',
    'TelescopeSelection', 'TranslationNotification', 'TranslationError',
    'RenderMarkdownTableCode', 'RenderMarkdownTableLabel', 'RenderMarkdownH4Bg',
    'RenderMarkdownMermaidEdgeLabel', 'RenderMarkdownMermaidSubgraphLabel',
    'TreesitterContext', 'TreesitterContextLineNumber',
  }) do
    contrast_text(name, normal.bg)
  end
end
highlights.setup()
for _, name in ipairs({ 'habamax', 'morning', 'habamax' }) do
  vim.api.nvim_cmd({ cmd = 'colorscheme', args = { name } }, {})
  check_surfaces()
  local first_apply = vim.api.nvim_get_hl(0, {})
  highlights.apply()
  assert(vim.deep_equal(first_apply, vim.api.nvim_get_hl(0, {})), 'Palette application drifts on repeat')
end
-- A plugin loaded later can overwrite derived diff groups after our immediate
-- ColorScheme callback. One deferred pass must settle on the newest theme.
local late_theme_group = vim.api.nvim_create_augroup('test_late_theme_refresh', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', {
  group = late_theme_group,
  callback = function()
    vim.api.nvim_set_hl(0, 'DiffviewDiffAddAsDelete', { bg = 0x123456, fg = 0xABCDEF })
  end,
})
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'morning' } }, {})
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'habamax' } }, {})
assert(vim.wait(1000, function()
  local deleted = hl('DiffviewDiffAddAsDelete')
  return deleted.bg == palette.resolve().history.deleted_background and not deleted.fg
end, 10), 'Late plugin refresh overrode the final theme or its syntax foregrounds')
vim.api.nvim_del_augroup_by_id(late_theme_group)
-- A rendered plugin pane must not turn its previous mapped colors into inputs
-- for the next global palette refresh.
local expected_palette = palette.resolve()
local previous_winhl = vim.wo.winhighlight
vim.api.nvim_set_hl(0, 'TestStalePane', { bg = 0xFFFFFF, fg = 0x000000 })
vim.api.nvim_set_hl(0, 'TestStaleCursor', { bg = 0xFFFF00 })
vim.wo.winhighlight = 'Normal:TestStalePane,CursorLine:TestStaleCursor'
vim.cmd('redraw')
assert(vim.deep_equal(palette.resolve(), expected_palette), 'Window mappings contaminated the shared palette')
highlights.apply()
assert(vim.api.nvim_get_hl(0, { name = 'DiffviewNormal', link = true }).bg == expected_palette.background,
  'Refreshing from a plugin pane retained its stale background')
vim.wo.winhighlight = previous_winhl
vim.cmd('redraw')
-- The pinned tint follows changes to Normal within one theme, not a fixed panel color.
local before_context = hl('TreesitterContext').bg
vim.api.nvim_set_hl(0, 'Normal', { bg = 0x303030, fg = 0xF0F0F0 })
highlights.apply()
assert(hl('TreesitterContext').bg ~= before_context, 'Pinned tint ignores the editor background')
local context_background = hl('TreesitterContext').bg
assert(math.floor(context_background / 65536) == math.floor(context_background / 256) % 256
    and math.floor(context_background / 256) % 256 == context_background % 256,
  'Pinned context adds a hue to a neutral editor background')
local context_border = hl('TreesitterContextBottom').sp
assert(math.floor(context_border / 65536) == math.floor(context_border / 256) % 256
    and math.floor(context_border / 256) % 256 == context_border % 256,
  'Pinned context boundary retained a chromatic accent')
-- Missing highlights, including a transparent Normal, use light/dark fallbacks.
for _, mode in ipairs({ 'dark', 'light' }) do
  vim.o.background = mode
  vim.cmd('highlight clear')
  for _, name in ipairs({ 'Normal', 'CursorLine', 'ColorColumn', 'Function', 'Type', 'Statement', 'String' }) do
    vim.api.nvim_set_hl(0, name, {})
  end
  local resolved = palette.resolve()
  assert(palette.contrast(resolved.foreground, resolved.background) >= 4.5, 'Unreadable fallback palette')
  assert((resolved.background > 0x808080) == (mode == 'light'), 'Fallback ignores light/dark mode')
end
-- Explicit overrides are applied last on every theme change.
highlights.setup({ overrides = function(colors)
  return { RenderMarkdownMermaidEdge = { fg = colors.syntax.special, bg = colors.block, bold = true } }
end })
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'morning' } }, {})
assert(hl('RenderMarkdownMermaidEdge').bold, 'Theme reload discarded a configured override')
highlights.setup({})
vim.o.background = previous_background
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { previous_theme } }, {})
