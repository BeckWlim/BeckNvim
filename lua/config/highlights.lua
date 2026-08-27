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

local function apply()
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
