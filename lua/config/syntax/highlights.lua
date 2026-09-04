local M = {}

local completion_kind_colors = {
  Function = '#A6E22E',
  Method = '#A6E22E',
  Class = '#A6E22E',
  Interface = '#A6E22E',
  Struct = '#A6E22E',
  Variable = '#66D9EF',
  Module = '#66D9EF',
  Property = '#66D9EF',
  Keyword = '#F92672',
  Field = '#F92672',
  Operator = '#F92672',
  Snippet = '#AE81FF',
  Constant = '#AE81FF',
  Enum = '#AE81FF',
  EnumMember = '#AE81FF',
  Unit = '#E6DB74',
  Value = '#E6DB74',
  Color = '#E6DB74',
  Folder = '#E6DB74',
  Text = '#F8F8F2',
  File = '#F8F8F2',
  Reference = '#F8F8F2',
}

local context_colors = {
  background = '#3A3D32',
  border = '#A6E22E',
  foreground = '#F8F8F2',
  muted_foreground = '#A6A69C',
}

local cursor_line_background = '#3A3D3F'

local markdown_heading_four_colors = {
  background = '#363139',
  foreground = '#F8F8F2',
  accent = '#FFB3D1',
}

local markdown_table_colors = {
  icon = '#89E051',
  label = '#A6A69C',
}

local function history_ui_palette(editor_background, editor_foreground)
  return {
    added = '#A6E22E',
    added_background = '#29362D',
    background = editor_background,
    border = '#666666',
    changed = '#E6DB74',
    changed_background = '#34352B',
    deleted = '#F92672',
    deleted_background = '#382A2F',
    focus = '#FFFFFF',
    foreground = editor_foreground,
    hash = '#AE81FF',
    information = '#66D9EF',
    muted = '#8F908A',
    selected = cursor_line_background,
    selected_foreground = editor_foreground,
    title = editor_foreground,
  }
end

local rainbow_delimiter_colors = {
  RainbowDelimiterBase = '#B7B9C0',
  RainbowDelimiterRed = '#D23A78',
  RainbowDelimiterYellow = '#CFC46D',
  RainbowDelimiterBlue = '#62B4CA',
  RainbowDelimiterOrange = '#DA8438',
  RainbowDelimiterGreen = '#8AC44C',
  RainbowDelimiterViolet = '#9479D1',
  RainbowDelimiterCyan = '#73C9CF',
}

local current_scope_background = require('config.syntax.visuals').current_scope_color()

local function apply()
  local normal_highlight = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local code_block_highlight = vim.api.nvim_get_hl(0, {
    name = 'ColorColumn',
    link = false,
  })
  local inline_code_highlight = vim.api.nvim_get_hl(0, {
    name = '@markup.raw.markdown_inline',
    link = false,
  })
  local editor_background = normal_highlight.bg or 0x272822
  local editor_foreground = normal_highlight.fg or 0xF8F8F2
  local inline_code_foreground = inline_code_highlight.fg or 0xAE81FF
  local markdown_block_background = code_block_highlight.bg or cursor_line_background
  local history_colors = history_ui_palette(editor_background, editor_foreground)
  vim.api.nvim_set_hl(0, 'NormalFloat', {
    bg = editor_background,
    fg = editor_foreground,
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
    fg = '#A6E22E',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationSeparator', { fg = '#49483E' })
  vim.api.nvim_set_hl(0, 'TypeInformationIndex', {
    fg = '#AE81FF',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationLocation', {
    fg = '#66D9EF',
    underline = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationHint', {
    fg = '#75715E',
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'TypeInformationPreview', { bg = '#2B2C26' })
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
    fg = '#49483E',
  })
  vim.api.nvim_set_hl(0, 'RenderMarkdownTableRowRule', {
    bg = markdown_block_background,
    fg = '#3E3D32',
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
  vim.api.nvim_set_hl(0, '@markup.table.markdown', {
    bg = markdown_block_background,
  })
  vim.api.nvim_set_hl(0, 'TranslationFloat', {
    bg = editor_background,
    fg = editor_foreground,
  })
  vim.api.nvim_set_hl(0, 'TranslationSeparator', {
    fg = '#49483E',
    bg = editor_background,
  })
  vim.api.nvim_set_hl(0, 'TranslationSection', {
    fg = '#66D9EF',
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
    fg = '#75715E',
    bg = editor_background,
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationError', {
    fg = '#F92672',
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
    'DiffviewWinSeparator',
  }) do
    vim.api.nvim_set_hl(0, group_name, {
      bg = history_colors.background,
      fg = history_colors.border,
    })
  end
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

  for kind, color in pairs(completion_kind_colors) do
    vim.api.nvim_set_hl(0, 'CmpItemKind' .. kind, { fg = color })
  end
end

function M.apply()
  apply()
end

function M.setup()
  local group = vim.api.nvim_create_augroup('user_interface_highlights', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    pattern = '*',
    callback = M.apply,
  })
  M.apply()
end

return M
