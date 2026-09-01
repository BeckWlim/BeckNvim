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
  background = '#405A45',
  foreground = '#F8F8F2',
  muted_foreground = '#A6A69C',
}

local cursor_line_background = '#3A3D3F'

local history_ui_colors = {
  accent = '#A6E22E',
  added_background = '#29362D',
  background = '#232526',
  border = '#666666',
  changed = '#E6DB74',
  changed_background = '#34352B',
  deleted = '#F92672',
  deleted_background = '#382A2F',
  foreground = '#DCDCDC',
  information = '#66D9EF',
  muted = '#75715E',
  selected = '#3A3D3F',
  violet = '#AE81FF',
}

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
  local editor_background = normal_highlight.bg or 0x272822
  local editor_foreground = normal_highlight.fg or 0xF8F8F2
  vim.api.nvim_set_hl(0, 'Pmenu', { bg = '#232526', fg = '#DCDCDC' })
  vim.api.nvim_set_hl(0, 'PmenuSel', { bg = '#3A3D3F', fg = '#FFFFFF', bold = true })
  vim.api.nvim_set_hl(0, 'PmenuFloatBorder', { fg = '#666666' })
  vim.api.nvim_set_hl(0, 'CmpItemAbbr', { fg = '#DCDCDC' })
  vim.api.nvim_set_hl(0, 'CmpItemAbbrMatch', { fg = '#F92672', bold = true })
  vim.api.nvim_set_hl(0, 'CmpItemAbbrMatchFuzzy', { fg = '#F92672' })
  vim.api.nvim_set_hl(0, 'CmpItemMenu', { fg = '#75715E' })
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
    bg = context_colors.background,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextPreview', {
    bg = context_colors.background,
    fg = context_colors.foreground,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TreesitterContextPreviewSeparator', {
    bg = context_colors.background,
    fg = context_colors.muted_foreground,
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
  vim.api.nvim_set_hl(0, 'TranslationFloat', {
    bg = '#232526',
    fg = '#DCDCDC',
  })
  vim.api.nvim_set_hl(0, 'TranslationSeparator', {
    fg = '#49483E',
    bg = '#232526',
  })
  vim.api.nvim_set_hl(0, 'TranslationSection', {
    fg = '#66D9EF',
    bg = '#232526',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationContent', {
    fg = '#F8F8F2',
    bg = '#232526',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationDictionary', {
    fg = '#DCDCDC',
    bg = '#232526',
  })
  vim.api.nvim_set_hl(0, 'TranslationNotification', {
    fg = '#75715E',
    bg = '#232526',
    italic = true,
  })
  vim.api.nvim_set_hl(0, 'TranslationError', {
    fg = '#F92672',
    bg = '#232526',
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
      bg = history_ui_colors.background,
      fg = history_ui_colors.foreground,
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
      bg = history_ui_colors.background,
      fg = history_ui_colors.border,
    })
  end
  for _, group_name in ipairs({
    'TelescopePromptTitle',
    'TelescopeResultsTitle',
    'TelescopePreviewTitle',
    'DiffviewFilePanelTitle',
    'DiffviewFilePanelRootPath',
  }) do
    vim.api.nvim_set_hl(0, group_name, {
      bg = history_ui_colors.background,
      fg = history_ui_colors.accent,
      bold = true,
    })
  end
  vim.api.nvim_set_hl(0, 'TelescopeSelection', {
    bg = history_ui_colors.selected,
    fg = '#FFFFFF',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopeSelectionCaret', {
    bg = history_ui_colors.selected,
    fg = history_ui_colors.accent,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'TelescopeMatching', {
    fg = history_ui_colors.accent,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'DiffviewCursorLine', { bg = history_ui_colors.selected })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelSelected', {
    bg = history_ui_colors.selected,
    fg = '#FFFFFF',
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelFileName', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.foreground,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelPath', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelCounter', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.information,
  })
  vim.api.nvim_set_hl(0, 'DiffviewHash', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.violet,
  })
  vim.api.nvim_set_hl(0, 'GitHistoryMessageMatch', {
    fg = history_ui_colors.accent,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'GitHistoryLocalTag', {
    bg = history_ui_colors.selected,
    fg = history_ui_colors.accent,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'GitHistoryRemoteTag', {
    bg = history_ui_colors.selected,
    fg = history_ui_colors.information,
    bold = true,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelInsertions', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.accent,
  })
  vim.api.nvim_set_hl(0, 'DiffviewFilePanelDeletions', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.deleted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewStatusModified', { fg = history_ui_colors.changed })
  vim.api.nvim_set_hl(0, 'DiffviewStatusAdded', { fg = history_ui_colors.accent })
  vim.api.nvim_set_hl(0, 'DiffviewStatusDeleted', { fg = history_ui_colors.deleted })
  vim.api.nvim_set_hl(0, 'DiffviewDiffAdd', {
    bg = history_ui_colors.added_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffAddAsDelete', {
    bg = history_ui_colors.deleted_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffChange', {
    bg = history_ui_colors.changed_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffText', {
    bg = history_ui_colors.changed_background,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDiffDeleteDim', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewSecondary', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.muted,
  })
  vim.api.nvim_set_hl(0, 'DiffviewDim1', {
    bg = history_ui_colors.background,
    fg = history_ui_colors.muted,
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
