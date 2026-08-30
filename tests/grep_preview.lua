local grep_preview = require('config.search.grep_preview')

assert(grep_preview.context_winbar({}) == '', 'empty grep context consumed preview space')
assert(
  grep_preview.context_winbar({ 'Service', 'run' })
    == '%#TreesitterContextPreview#  Service'
      .. '%#TreesitterContextPreviewSeparator#  ›  '
      .. '%#TreesitterContextPreview#run ',
  'grep context did not render an outer-to-inner structural breadcrumb'
)
assert(
  grep_preview.context_winbar({ 'load%config' }):match('load%%%%config') ~= nil,
  'grep context did not escape statusline percent characters'
)

local preview_winhighlight = grep_preview.context_winhighlight(
  'Normal:TelescopePreviewNormal,WinBar:OldStyle,CursorLine:Visual'
)
assert(
  preview_winhighlight
    == 'Normal:TelescopePreviewNormal,CursorLine:Visual,'
      .. 'WinBar:TreesitterContextPreview,WinBarNC:TreesitterContextPreview',
  'grep context did not preserve preview highlights while replacing winbar styles'
)
