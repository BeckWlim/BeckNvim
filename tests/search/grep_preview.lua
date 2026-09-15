-- Focused tests for config.search.grep_preview.
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

-- Native preview text/cursor is usable before optional context resolves.
local replaced_modules = { 'telescope.previewers', 'telescope.config', 'telescope.from_entry', 'plenary.path' }
local original_modules = {}
for _, name in ipairs(replaced_modules) do original_modules[name] = package.loaded[name] end
package.loaded['telescope.previewers'] = { new_buffer_previewer = function(options) return options end }
package.loaded['telescope.config'] = { values = {} }
package.loaded['telescope.from_entry'] = {}
package.loaded['plenary.path'] = {}
local original_context = package.loaded['config.syntax.treesitter_context']
local requests = {}
package.loaded['config.syntax.treesitter_context'] = {
  enclosing_structure_async = function(_, row, _, callback)
    requests[#requests + 1] = { row = row, callback = callback }
  end,
}
local original_buffer = vim.api.nvim_get_current_buf()
local original_winbar = vim.wo.winbar
local original_winhighlight = vim.wo.winhighlight
local source_buffer = vim.api.nvim_create_buf(false, true)
local preview_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, { 'first', 'second', 'third' })
vim.api.nvim_set_current_buf(preview_buffer)
local preview_spec = grep_preview.new({ source_buffer = source_buffer })
local previewer = { state = { bufnr = preview_buffer, winid = vim.api.nvim_get_current_win() } }
preview_spec.define_preview(previewer, { lnum = 1 })
assert(vim.wait(500, function() return #requests == 1 end))
preview_spec.define_preview(previewer, { lnum = 2 })
assert(vim.wait(500, function() return #requests == 2 end))
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'Preview cursor waited for context parsing')
requests[1].callback({ label = 'old' })
assert(vim.wo.winbar == '', 'Old selection context replaced the active preview')
requests[2].callback({ label = 'current' })
assert(vim.wo.winbar:find('current', 1, true), 'Active context was not rendered')
preview_spec.define_preview(previewer, { lnum = 3 })
assert(vim.wait(500, function() return #requests == 3 end))
preview_spec.teardown()
requests[3].callback({ label = 'retired' })
assert(vim.wo.winbar == '', 'Closed preview accepted pending context')
vim.api.nvim_set_current_buf(original_buffer)
vim.wo.winbar = original_winbar
vim.wo.winhighlight = original_winhighlight
vim.api.nvim_buf_delete(source_buffer, { force = true })
vim.api.nvim_buf_delete(preview_buffer, { force = true })
package.loaded['config.syntax.treesitter_context'] = original_context
for _, name in ipairs(replaced_modules) do package.loaded[name] = original_modules[name] end
