-- Full startup wiring: run with -u init.lua '+luafile tests/search/flash_markdown_startup.lua'.
local flash_spec = require('lazy.core.config').plugins['flash.nvim']
assert(flash_spec and #flash_spec.keys == 2, 'Lazy cannot inspect the Flash shortcuts')
assert(not flash_spec._.loaded, 'Flash loaded before its first shortcut')
vim.cmd('enew!')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'needle' })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(' sneedle<C-q>', true, false, true), 'xt', false)
assert(flash_spec._.loaded, 'The first Flash shortcut did not load the plugin')
assert(not require('flash.repeat')._states.jump.visible, 'First-use Flash prompt did not cancel')
require('lazy').load({ plugins = { 'render-markdown.nvim' } })
local renderer = require('render-markdown')
assert(not require('flash.config').modes.search.enabled, 'Flash took over native search')
assert(not require('flash.config').label.uppercase, 'Flash uses uppercase labels')
vim.cmd('enew!')
for _, mode in ipairs({ 'n', 'x', 'o' }) do
  assert(vim.tbl_isempty(vim.fn.maparg('<Space>fj', mode, false, true)),
    'Removed Flash alias is still mapped: ' .. mode)
  for _, key in ipairs({ '<Space>s', '<Space>fn' }) do
    assert(vim.fn.maparg(key, mode, false, true).callback, 'Flash shortcut is missing: ' .. key)
  end
end
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '# Markdown', '', '[github](https://github.com)' })
vim.bo[source].filetype = 'markdown'
local toggle = vim.fn.maparg('<Space>mp', 'n', false, true)
assert(toggle.callback and toggle.buffer == 0, 'Host preview shortcut is missing')
toggle.callback()
assert(vim.api.nvim_get_current_buf() ~= source and renderer.source_buffer() == source,
  'Preview lost its source identity')
for _, key in ipairs({ 'h', 'l', 'w', 'b', 'e' }) do
  for _, mode in ipairs({ 'n', 'x' }) do
    local motion = vim.fn.maparg(key, mode, false, true)
    assert(motion.callback and motion.buffer == 1, 'Preview motion is missing: ' .. key)
  end
end
for _, key in ipairs({ '/', '?', 'n', 'N' }) do
  for _, mode in ipairs({ 'n', 'x', 'o' }) do
    assert(vim.tbl_isempty(vim.fn.maparg(key, mode, false, true)),
      'Renderer replaced native preview search: ' .. key)
  end
end
assert(vim.fn.maparg('<Space>mp', 'n', false, true).buffer == 0,
  'Renderer shadows the host-owned toggle')
toggle.callback()
assert(vim.api.nvim_get_current_buf() == source, 'Preview failed to return to source')
for _, key in ipairs({ 'h', 'l', 'w', 'b', 'e', '/', '?', 'n', 'N' }) do
  assert(vim.tbl_isempty(vim.fn.maparg(key, 'n', false, true)),
    'Source inherited a renderer mapping: ' .. key)
end
print('Full startup Markdown preview, native search, motions, and Flash bindings passed')
vim.cmd('qa!')
