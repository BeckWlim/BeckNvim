-- Resolve one project palette from the active colorscheme. Feature renderers
-- consume named highlights; only this boundary interprets theme colors.
local M = {}

local fallback = {
  dark = {
    background = 0x272822, foreground = 0xF8F8F2,
    red = 0xF92672, green = 0xA6E22E, yellow = 0xE6DB74,
    blue = 0x66D9EF, purple = 0xAE81FF, orange = 0xFD971F,
  },
  light = {
    background = 0xFAFAF7, foreground = 0x242424,
    red = 0xA51D45, green = 0x3D6815, yellow = 0x756000,
    blue = 0x006B80, purple = 0x7040A0, orange = 0x995000,
  },
}

function M.blend(background, foreground, amount)
  local color = 0
  for _, divisor in ipairs({ 65536, 256, 1 }) do
    local base_channel = math.floor(background / divisor) % 256
    local accent_channel = math.floor(foreground / divisor) % 256
    color = color + math.floor(base_channel + (accent_channel - base_channel) * amount + 0.5) * divisor
  end
  return color
end

local function luminance(color)
  local result = 0
  for index, divisor in ipairs({ 65536, 256, 1 }) do
    local channel = (math.floor(color / divisor) % 256) / 255
    local linear = channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
    result = result + linear * ({ 0.2126, 0.7152, 0.0722 })[index]
  end
  return result
end

function M.contrast(first, second)
  local first_light = luminance(first)
  local second_light = luminance(second)
  return (math.max(first_light, second_light) + 0.05) / (math.min(first_light, second_light) + 0.05)
end

local function readable(color, background, minimum)
  if M.contrast(color, background) >= minimum then return color end
  local target = M.contrast(0xFFFFFF, background) > M.contrast(0, background) and 0xFFFFFF or 0
  for step = 1, 20 do
    local adjusted = M.blend(color, target, step / 20)
    if M.contrast(adjusted, background) >= minimum then return adjusted end
  end
  return target
end

local function highlight(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local function foreground(names, default_color)
  for _, name in ipairs(names) do
    local color = highlight(name).fg
    if color then return color end
  end
  return default_color
end

function M.resolve()
  local defaults = fallback[vim.o.background]
  local normal = highlight('Normal')
  local background = normal.bg or defaults.background
  local text = normal.fg or defaults.foreground
  local neutral = math.floor((math.floor(text / 65536) + math.floor(text / 256) % 256 + text % 256) / 3)
    * 0x010101
  local muted = readable(M.blend(background, neutral, 0.65), background, 4.5)
  local border = readable(M.blend(background, neutral, 0.40), background, 3)
  local selection_candidate = highlight('CursorLine').bg or M.blend(background, neutral, 0.12)
  local selection = readable(selection_candidate, text, 4.5)
  local block_candidate = highlight('ColorColumn').bg or M.blend(background, neutral, 0.06)
  local block = M.contrast(text, block_candidate) >= 4.5 and block_candidate or background
  local function accent(names, default_color)
    return readable(foreground(names, default_color), background, 4.5)
  end
  local syntax = {
    func = accent({ 'Function' }, defaults.green),
    type = accent({ 'Type' }, defaults.blue),
    keyword = accent({ 'Statement' }, defaults.red),
    string = accent({ 'String' }, defaults.yellow),
    constant = accent({ 'Constant', 'Number' }, defaults.purple),
    number = accent({ 'Number' }, defaults.purple),
    special = accent({ 'Special' }, defaults.orange),
  }
  local added = accent({ 'GitSignsAdd', 'Added', 'DiagnosticOk' }, defaults.green)
  local changed = accent({ 'GitSignsChange', 'Changed', 'DiagnosticWarn' }, defaults.yellow)
  local deleted = accent({ 'GitSignsDelete', 'Removed', 'DiagnosticError' }, defaults.red)
  -- A neutral filter retains the editor's warmth/coolness without adding hue.
  local context_strength = vim.o.background == 'light' and 0.06 or 0.10
  local context_background = M.blend(background, neutral, context_strength)
  local context_border = M.blend(background, neutral, 0.40)
  local statusline_background = M.blend(background, neutral, vim.o.background == 'light' and 0.06 or 0.08)
  local inactive_statusline_background = M.blend(background, neutral, vim.o.background == 'light' and 0.03 or 0.04)
  local function diagram_accent(color, strength)
    return readable(M.blend(muted, color, strength), block, 3)
  end
  local table_accent = readable(syntax.func, block, 4.5)
  local mermaid_accent = readable(syntax.number, block, 4.5)
  return {
    background = background, foreground = text, muted = muted, border = border,
    selection = selection, focus = readable(neutral, selection, 4.5), block = block,
    scope = M.blend(background, neutral, 0.04),
    inline_code = readable(foreground({ '@markup.raw.markdown_inline' }, syntax.constant), selection, 4.5),
    syntax = syntax,
    context = {
      background = context_background, foreground = readable(text, context_background, 4.5),
      border = readable(context_border, context_background, 3),
      muted_foreground = readable(muted, context_background, 4.5),
    },
    statusline = {
      background = statusline_background,
      foreground = readable(text, statusline_background, 4.5),
      inactive_background = inactive_statusline_background,
      inactive_foreground = readable(muted, inactive_statusline_background, 4.5),
    },
    heading = {
      background = M.blend(background, syntax.special, 0.10),
      foreground = text, accent = syntax.special,
    },
    table = { icon = table_accent, label = table_accent, rule = readable(border, block, 3) },
    history = {
      background = background, foreground = text, title = text, border = border, muted = muted,
      selected = selection, selected_foreground = text, focus = readable(neutral, selection, 4.5),
      added = added, changed = changed, deleted = deleted,
      added_background = M.blend(background, added, 0.12),
      changed_background = M.blend(background, changed, 0.12),
      deleted_background = M.blend(background, deleted, 0.12),
      hash = syntax.constant, information = syntax.type,
    },
    mermaid = {
      foreground = text, node_label = text, edge_label = text,
      edge = diagram_accent(syntax.type, 0.30), arrow = diagram_accent(syntax.type, 0.65),
      node = diagram_accent(syntax.string, 0.45), icon = mermaid_accent,
      active = diagram_accent(added, 0.55), critical = diagram_accent(deleted, 0.65),
      milestone = diagram_accent(syntax.special, 0.55),
      done = readable(muted, block, 4.5), label = mermaid_accent,
      subgraph = readable(border, block, 3), subgraph_label = readable(muted, block, 4.5),
      sections = {
        diagram_accent(syntax.keyword, 0.45), diagram_accent(syntax.type, 0.45),
        diagram_accent(syntax.func, 0.45), diagram_accent(syntax.string, 0.45),
        diagram_accent(syntax.number, 0.45), diagram_accent(syntax.special, 0.45),
        diagram_accent(syntax.constant, 0.45), diagram_accent(added, 0.45),
      },
    },
    rainbow = {
      RainbowDelimiterBase = muted,
      RainbowDelimiterRed = accent({ 'DiagnosticError' }, defaults.red),
      RainbowDelimiterYellow = accent({ 'DiagnosticWarn' }, defaults.yellow),
      RainbowDelimiterBlue = syntax.type,
      RainbowDelimiterOrange = syntax.special,
      RainbowDelimiterGreen = added,
      RainbowDelimiterViolet = syntax.number,
      RainbowDelimiterCyan = accent({ 'DiagnosticInfo' }, defaults.blue),
    },
  }
end

return M
