local policy = require('config.ui.window_state').markdown_preview_allowed
local previous_diffview = package.loaded['diffview.lib']
vim.cmd('tabnew')
local window = vim.api.nvim_get_current_win()
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source, vim.fn.tempname() .. '.md')
vim.bo[source].filetype = 'markdown'
assert(policy(source, window), 'Ordinary Markdown editor did not opt in')
vim.bo[source].buflisted = false
assert(policy(source, window), 'Source restored through history lost manual preview permission')
local hidden_source = vim.api.nvim_create_buf(false, false)
vim.api.nvim_buf_set_name(hidden_source, vim.fn.tempname() .. '.md')
vim.bo[hidden_source].filetype = 'markdown'
assert(not policy(hidden_source, window), 'Hidden unlisted file implicitly opted in')
vim.api.nvim_buf_delete(hidden_source, { force = true })
vim.w[window].render_markdown_preview = false
assert(not policy(source, window), 'Plugin window could not opt out')
vim.w[window].render_markdown_preview = nil
vim.wo[window].previewwindow = true
assert(not policy(source, window), 'Native preview window implicitly opted in')
vim.wo[window].previewwindow = false
vim.wo[window].winfixbuf = true
assert(not policy(source, window), 'Protected plugin window implicitly opted in')
vim.wo[window].winfixbuf = false
local plugin_window = vim.api.nvim_open_win(source, false, {
  relative = 'editor', row = 1, col = 1, width = 30, height = 5,
})
assert(not policy(source, plugin_window), 'Plugin float implicitly opted in')
assert(policy(source, window), 'Plugin ownership leaked into the ordinary editor')
vim.w[plugin_window].render_markdown_preview = true
assert(policy(source, plugin_window), 'Plugin float could not explicitly opt in')
vim.api.nvim_win_close(plugin_window, true)
package.loaded['diffview.lib'] = {
  tabpage_to_view = function(tabpage)
    if tabpage == vim.api.nvim_win_get_tabpage(window) then return {} end
  end,
}
assert(not policy(source, window), 'Diffview tab opted in before diff options were set')
package.loaded['diffview.lib'] = previous_diffview
vim.api.nvim_buf_set_name(source, 'plugin-document://preview/markdown')
assert(not policy(source, window), 'Virtual document implicitly opted in')
vim.cmd('tabclose!')
vim.api.nvim_buf_delete(source, { force = true })
