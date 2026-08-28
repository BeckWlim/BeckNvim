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

local current_scope_background = require('config.syntax_visuals').current_scope_color()

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

  for kind, color in pairs(completion_kind_colors) do
    vim.api.nvim_set_hl(0, 'CmpItemKind' .. kind, { fg = color })
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('user_interface_highlights', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    pattern = '*',
    callback = apply,
  })
  apply()
end

return M
