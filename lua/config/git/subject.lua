local M = {}

local groups = {
  feat = 'DiagnosticOk', feature = 'DiagnosticOk',
  fix = 'DiagnosticError', bugfix = 'DiagnosticError', hotfix = 'DiagnosticError',
  docs = 'DiagnosticInfo', refactor = 'DiagnosticHint', test = 'DiagnosticWarn',
  perf = 'DiagnosticOk', chore = 'Comment', build = 'DiagnosticHint',
  ci = 'DiagnosticInfo', style = 'Comment', revert = 'DiagnosticWarn',
}

-- Byte ranges relative to the unchanged subject, shared by both history layouts.
function M.spans(subject)
  local spans = {}
  local offset = 0
  while true do
    local tag = subject:sub(offset + 1):match('^%[([^%[%]]+)%]')
    if not tag then break end
    spans[#spans + 1] = {
      start_col = offset,
      end_col = offset + #tag + 2,
      group = groups[vim.trim(tag):lower()] or 'Identifier',
    }
    offset = offset + #tag + 2
    local whitespace = subject:sub(offset + 1):match('^%s*') or ''
    offset = offset + #whitespace
  end
  local remainder = subject:sub(offset + 1)
  local kind, scope, breaking = remainder:match('^([%a][%w%-]*)(%b())(!?):%s*.+$')
  if not kind then
    kind, breaking = remainder:match('^([%a][%w%-]*)(!?):%s*.+$')
  end
  if kind then
    spans[#spans + 1] = {
      start_col = offset,
      end_col = offset + #kind + #(scope or '') + #(breaking or '') + 1,
      group = groups[kind:lower()] or 'Identifier',
    }
  end
  return spans
end

return M
