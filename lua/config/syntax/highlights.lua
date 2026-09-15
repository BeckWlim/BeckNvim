local M = {}
local palette = require('config.ui.palette')
local overrides
local refresh_pending = false

local completion_kind_roles = {
  Function = 'func', Method = 'func', Class = 'type', Interface = 'type', Struct = 'type',
  Variable = 'type', Module = 'type', Property = 'type', Keyword = 'keyword', Field = 'keyword',
  Operator = 'keyword', Snippet = 'constant', Constant = 'constant', Enum = 'constant',
  EnumMember = 'constant', Unit = 'string', Value = 'string', Color = 'string', Folder = 'string',
}

local function apply()
  local colors = palette.resolve()
  local editor_background = colors.background
  local editor_foreground = colors.foreground
  local cursor_line_background = colors.selection
  local markdown_block_background = colors.block
  local inline_code_foreground = colors.inline_code
  local history_colors = colors.history
  local markdown_mermaid_colors = colors.mermaid
  local context_colors = colors.context
  local markdown_heading_four_colors = colors.heading
  local markdown_table_colors = colors.table
  local rainbow_delimiter_colors = colors.rainbow
  local current_scope_background = colors.scope
  -- Preserve each inactive window's mapped foreground (including Telescope
  -- borders) while sharing the editor's backing surface.
  vim.api.nvim_set_hl(0, 'NormalNC', { bg = editor_background })
  vim.api.nvim_set_hl(0, 'NormalFloat', {
    bg = editor_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'StatusLine', {
    bg = colors.statusline.background,
    fg = colors.statusline.foreground,
  })
  vim.api.nvim_set_hl(0, 'StatusLineNC', {
    bg = colors.statusline.inactive_background,
    fg = colors.statusline.inactive_foreground,
  })
  for _, group_name in ipairs({ 'FloatBorder', 'FloatTitle', 'FloatFooter' }) do
    vim.api.nvim_set_hl(0, group_name, {
      bg = editor_background,
      fg = history_colors.border,
    })
  end
  vim.api.nvim_set_hl(0, 'Pmenu', { bg = editor_background, fg = editor_foreground })
  vim.api.nvim_set_hl(0, 'PmenuSel', {
    bg = cursor_line_background,
    fg = editor_foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'PmenuFloatBorder', {
    bg = editor_background,
    fg = history_colors.border,
  })
  vim.api.nvim_set_hl(0, 'CmpItemAbbr', { fg = editor_foreground })
  vim.api.nvim_set_hl(0, 'CmpItemAbbrMatch', { fg = history_colors.focus, bold = true })
  vim.api.nvim_set_hl(0, 'CmpItemAbbrMatchFuzzy', {
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'CmpItemMenu', { fg = history_colors.muted })
  vim.api.nvim_set_hl(0, 'TreesitterContext', {
    bg = context_colors.background,
    fg = context_colors.foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextLineNumber', {
    bg = context_colors.background,
    fg = context_colors.muted_foreground,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextBottom', {
    underline = true,
    sp = context_colors.border,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextPreview', {
    bg = context_colors.background,
    fg = context_colors.foreground,
    bold = true,
    underline = true,
    sp = context_colors.border,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextPreviewSeparator', {
    bg = context_colors.background,
    fg = context_colors.muted_foreground,
    underline = true,
    sp = context_colors.border,
  })

  for group_name, color in pairs(rainbow_delimiter_colors) do
    vim.api.nvim_set_hl(0, group_name, { fg = color, bold = true })
  end
  vim.api.nvim_set_hl(0, 'CurrentCodeScope', { bg = current_scope_background })
  vim.api.nvim_set_hl(0, 'CursorLine', { bg = cursor_line_background })
  vim.api.nvim_set_hl(0, 'TypeInformationSection', {
    fg = colors.syntax.func,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationSeparator', { fg = colors.border })
  vim.api.nvim_set_hl(0, 'TypeInformationIndex', {
    fg = colors.syntax.constant,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationLocation', {
    fg = colors.syntax.type,
    underline = true,
  })
  vim.api.nvim_set_hl(0, 'DashboardFile', { fg = colors.syntax.type })
  vim.api.nvim_set_hl(0, 'TypeInformationHint', {
    fg = colors.muted,
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationPreview', { bg = colors.scope })
  vim.api.nvim_set_hl(0, 'TypeInformationCursorLine', { bg = cursor_line_background })
  vim.api.nvim_set_hl(0, 'RenderMarkdownH4', {
    fg = markdown_heading_four_colors.accent,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownH4Bg', {
    bg = markdown_heading_four_colors.background,
    fg = markdown_heading_four_colors.foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableRule', {
    bg = markdown_block_background,
    fg = colors.border,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableRowRule', {
    bg = markdown_block_background,
    fg = colors.table.rule,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableHeader', {
    bg = markdown_block_background,
    fg = editor_foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableCell', {
    bg = markdown_block_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableCode', {
    bg = cursor_line_background,
    fg = inline_code_foreground,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableIcon', {
    bg = markdown_block_background,
    fg = markdown_table_colors.icon,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableLabel', {
    bg = markdown_block_background,
    fg = markdown_table_colors.label,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaid', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.foreground,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidActive', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.active,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidArrow', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.arrow,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidCritical', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.critical,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidDone', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.done,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidEdge', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.edge,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidEdgeLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.edge_label,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidItalicLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.node_label,
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidBoldLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.node_label,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidContentLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.node_label,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidMilestone', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.milestone,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidNode', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.node,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidSubgraph', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.subgraph,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidSubgraphLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.subgraph_label,
  })
  for index, foreground in ipairs(markdown_mermaid_colors.sections) do
    vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidSection' .. index, {
      bg = markdown_block_background,
      fg = foreground,
      bold = true,
    })
  end
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidIcon', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.icon,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownMermaidLabel', {
    bg = markdown_block_background,
    fg = markdown_mermaid_colors.label,
  })
  vim.api.nvim_set_hl(0, '@markup.table.markdown', {
    bg = markdown_block_background,
  })
  vim.api.nvim_set_hl(0, 'TranslationFloat', {
    bg = editor_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'TranslationSeparator', {
    fg = colors.border,
    bg = editor_background,
  })
  vim.api.nvim_set_hl(0, 'TranslationSection', {
    fg = colors.syntax.type,
    bg = editor_background,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationContent', {
    fg = editor_foreground,
    bg = editor_background,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationDictionary', {
    fg = editor_foreground,
    bg = editor_background,
  })
  vim.api.nvim_set_hl(0, 'TranslationNotification', {
    fg = colors.muted,
    bg = editor_background,
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationError', {
    fg = colors.history.deleted,
    bg = editor_background,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'NvimTreeNormal', {
    bg = editor_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'NvimTreeNormalNC', {
    bg = editor_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'NvimTreeSignColumn', { bg = editor_background })
  vim.api.nvim_set_hl(0, 'NvimTreeEndOfBuffer', {
    bg = editor_background,
    fg = editor_background,
  })
  vim.api.nvim_set_hl(0, 'NvimTreeCursorLine', { bg = cursor_line_background })

  for _, group_name in ipairs({
    'TelescopeNormal',
    'TelescopePromptNormal',
    'TelescopeResultsNormal',
    'TelescopePreviewNormal',
    'DiffviewNormal',
  }) do
    vim.api.nvim_set_hl(0, group_name, {
      bg = history_colors.background,
      fg = history_colors.foreground,
    })
  end
  for _, group_name in ipairs({
    'TelescopeBorder',
    'TelescopePromptBorder',
    'TelescopeResultsBorder',
    'TelescopePreviewBorder',
  }) do
    vim.api.nvim_set_hl(0, group_name, {
      -- Telescope's border windows include the corner and margin cells.
      -- Contrast the edge glyph while keeping its backing cell on the editor base.
      bg = editor_background,
      fg = history_colors.border,
    })
  end
  vim.api.nvim_set_hl(0, 'DiffviewWinSeparator', {
    bg = history_colors.background,
    fg = history_colors.border,
  })
  for _, group_name in ipairs({
    'TelescopeTitle',
    'TelescopePromptTitle',
    'TelescopeResultsTitle',
    'TelescopePreviewTitle',
    'DiffviewFilePanelTitle',
    'DiffviewFilePanelRootPath',
  }) do
    vim.api.nvim_set_hl(0, group_name, {
      bg = history_colors.background,
      fg = history_colors.title,
      bold = true,
    })
  end
  vim.api.nvim_set_hl(0, 'TelescopeSelection', {
    bg = history_colors.selected,
    fg = history_colors.selected_foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopeSelectionCaret', {
    bg = history_colors.selected,
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopeMatching', {
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopePromptPrefix', {
    bg = history_colors.background,
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopePreviewLine', {
    bg = history_colors.selected,
    fg = history_colors.selected_foreground,
  })
  vim.api.nvim_set_hl(0, 'TelescopePreviewMatch', {
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelFileName', {
    bg = history_colors.background,
    fg = history_colors.foreground,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelPath', {
    bg = history_colors.background,
    fg = history_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelCounter', {
    bg = history_colors.background,
    fg = history_colors.information,
  })
  vim.api.nvim_set_hl(0, 'DiffviewHash', {
    bg = history_colors.background,
    fg = history_colors.hash,
  })
  vim.api.nvim_set_hl(0, 'GitHistoryMessageMatch', {
    fg = history_colors.focus,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelInsertions', {
    bg = history_colors.background,
    fg = history_colors.added,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelDeletions', {
    bg = history_colors.background,
    fg = history_colors.deleted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewStatusModified', { fg = history_colors.changed })
  vim.api.nvim_set_hl(0, 'DiffviewStatusAdded', { fg = history_colors.added })
  vim.api.nvim_set_hl(0, 'DiffviewStatusDeleted', { fg = history_colors.deleted })
  vim.api.nvim_set_hl(0, 'DiffviewDiffAdd', {
    bg = history_colors.added_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffAddAsDelete', {
    bg = history_colors.deleted_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffChange', {
    bg = history_colors.changed_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffText', {
    bg = history_colors.changed_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffDeleteDim', {
    bg = history_colors.background,
    fg = history_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewSecondary', {
    bg = history_colors.background,
    fg = history_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDim1', {
    bg = history_colors.background,
    fg = history_colors.muted,
  })

  for kind, role in pairs(completion_kind_roles) do
    vim.api.nvim_set_hl(0, 'CmpItemKind' .. kind, { fg = colors.syntax[role] })
  end
  for _, kind in ipairs({ 'Text', 'File', 'Reference' }) do
    vim.api.nvim_set_hl(0, 'CmpItemKind' .. kind, { fg = editor_foreground })
  end
  if overrides then
    local custom_groups = type(overrides) == 'function' and overrides(colors) or overrides
    for name, definition in pairs(custom_groups) do
      vim.api.nvim_set_hl(0, name, definition)
    end
  end
end

function M.apply()
  apply()
end

-- Optional theme-file palettes replace the base schema in the existing owner.
-- The active native colorscheme remains the reload target for :colorscheme.
function M.load_palette(colors)
  for _, role in ipairs({ 'background', 'foreground', 'red', 'green', 'yellow', 'blue', 'purple', 'orange' }) do
    assert(type(colors[role]) == 'number' and colors[role] >= 0 and colors[role] <= 0xFFFFFF
      and colors[role] % 1 == 0, 'Invalid theme palette color: ' .. role)
  end
  vim.cmd('highlight clear')
  local muted = palette.blend(colors.background, colors.foreground, 0.65)
  local selection = palette.blend(colors.background, colors.foreground, 0.12)
  local definitions = {
    Normal = { fg = colors.foreground, bg = colors.background },
    NormalNC = { link = 'Normal' },
    CursorLine = { bg = selection },
    CursorColumn = { link = 'CursorLine' },
    ColorColumn = { bg = palette.blend(colors.background, colors.foreground, 0.06) },
    Visual = { bg = selection },
    Search = { fg = colors.background, bg = colors.yellow },
    IncSearch = { fg = colors.background, bg = colors.orange, bold = true },
    CurSearch = { link = 'IncSearch' },
    LineNr = { fg = muted }, CursorLineNr = { fg = colors.foreground, bold = true },
    SignColumn = { bg = colors.background }, FoldColumn = { fg = muted },
    Folded = { fg = muted, bg = selection },
    NonText = { fg = muted }, EndOfBuffer = { fg = colors.background },
    WinSeparator = { fg = muted }, Whitespace = { fg = muted },
    Comment = { fg = muted, italic = true },
    Constant = { fg = colors.purple }, String = { fg = colors.yellow },
    Character = { link = 'String' }, Number = { link = 'Constant' }, Boolean = { link = 'Constant' },
    Float = { link = 'Constant' }, Identifier = { fg = colors.blue },
    Function = { fg = colors.green }, Statement = { fg = colors.red },
    Operator = { fg = colors.red }, PreProc = { fg = colors.green },
    Type = { fg = colors.blue }, Special = { fg = colors.orange },
    Delimiter = { fg = colors.foreground }, Underlined = { fg = colors.blue, underline = true },
    Title = { fg = colors.foreground, bold = true },
    Directory = { fg = colors.blue }, MoreMsg = { fg = colors.green },
    Question = { fg = colors.green }, WarningMsg = { fg = colors.yellow },
    ErrorMsg = { fg = colors.red }, Error = { fg = colors.red },
    Todo = { fg = colors.orange, bold = true },
    MatchParen = { bg = selection, bold = true, underline = true },
    StatusLine = { fg = colors.foreground, bg = selection },
    StatusLineNC = { fg = muted, bg = colors.background },
    TabLine = { fg = muted, bg = colors.background },
    TabLineSel = { fg = colors.foreground, bg = selection, bold = true },
    TabLineFill = { bg = colors.background },
    DiagnosticError = { fg = colors.red }, DiagnosticWarn = { fg = colors.yellow },
    DiagnosticInfo = { fg = colors.blue }, DiagnosticHint = { fg = colors.purple },
    DiagnosticOk = { fg = colors.green },
    Added = { fg = colors.green }, Changed = { fg = colors.yellow }, Removed = { fg = colors.red },
    DiffAdd = { bg = palette.blend(colors.background, colors.green, 0.12) },
    DiffChange = { bg = palette.blend(colors.background, colors.yellow, 0.12) },
    DiffDelete = { bg = palette.blend(colors.background, colors.red, 0.12) },
    DiffText = { bg = palette.blend(colors.background, colors.yellow, 0.25) },
  }
  for group, definition in pairs(definitions) do vim.api.nvim_set_hl(0, group, definition) end
  for index, color in ipairs({
    colors.background, colors.red, colors.green, colors.yellow,
    colors.blue, colors.purple, colors.blue, colors.foreground,
    muted, colors.red, colors.green, colors.yellow,
    colors.blue, colors.purple, colors.blue, colors.foreground,
  }) do
    vim.g['terminal_color_' .. (index - 1)] = string.format('#%06x', color)
  end
  M.apply()
end

function M.setup(options)
  if options then overrides = options.overrides end
  local group = vim.api.nvim_create_augroup('user_interface_highlights', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    pattern = '*',
    callback = M.apply,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LazyLoad',
    callback = function()
      if refresh_pending then return end
      refresh_pending = true
      vim.schedule(function()
        refresh_pending = false
        M.apply()
      end)
    end,
  })
  M.apply()
end

return M
