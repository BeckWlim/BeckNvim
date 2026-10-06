-- Flash loads with general UI tools; the adapter owns mappings and Markdown routing.
local original_buffer = vim.api.nvim_get_current_buf()
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buffer)
local original_flash = package.loaded.flash
local original_renderer = package.loaded['render-markdown']
local calls, source_routes = {}, 0
package.loaded.flash = {
  setup = function(_) end,
  jump = function() calls[#calls + 1] = 'jump' end,
  treesitter = function() calls[#calls + 1] = 'treesitter' end,
}
package.loaded['render-markdown'] = {
  dispatch = function(operation)
    assert(operation.target == 'source', 'Syntax action did not request source')
    source_routes = source_routes + 1
    operation.run()
  end,
}

local spec = dofile('lua/plugins/coding.lua')[1]
assert(spec[1] == 'folke/flash.nvim'
    and spec.event == 'VeryLazy' and spec.keys == nil,
  'Flash should use UI readiness as its sole loading entry')
assert(package.loaded['config.search.flash'] == nil,
  'Loading the plugin spec eagerly imported its adapter')
spec.config(nil, spec.opts)

local function invoke_shortcuts()
  for _, mode in ipairs({ 'n', 'x', 'o' }) do
    for _, lhs in ipairs({ '<Space>s', '<Space>fn' }) do
      local mapping = vim.fn.maparg(lhs, mode, false, true)
      assert(mapping.callback and mapping.desc, 'Missing Flash action: ' .. mode .. ' ' .. lhs)
      mapping.callback()
    end
  end
end

invoke_shortcuts()
assert(#calls == 0, 'Flash opened in a special buffer')
vim.bo[buffer].buftype = ''
invoke_shortcuts()
assert(vim.deep_equal(calls, {
  'jump', 'treesitter', 'jump', 'treesitter', 'jump', 'treesitter',
}), 'Flash shortcuts dispatched the wrong action')
assert(source_routes == 0, 'Ordinary syntax selection was routed through Markdown')
vim.bo[buffer].buftype = 'acwrite'
vim.b[buffer].markdown_preview_source = original_buffer
invoke_shortcuts()
assert(#calls == 12 and source_routes == 3,
  'Preview Flash actions did not use direct matching and source syntax routing')
vim.b[buffer].markdown_preview_source = 'invalid'
invoke_shortcuts()
assert(#calls == 12, 'Invalid preview marker bypassed the special-buffer guard')

for _, mode in ipairs({ 'n', 'x', 'o' }) do
  for _, lhs in ipairs({ 's', 'S', 'r', 'R', 'f', 'F', 't', 'T', ';', ',', '/', '?' }) do
    assert(vim.tbl_isempty(vim.fn.maparg(lhs, mode, false, true)),
      'Flash integration overrides an editing command: ' .. mode .. ' ' .. lhs)
  end
  for _, lhs in ipairs({ '<Space>s', '<Space>fn' }) do vim.keymap.del(mode, lhs) end
end
package.loaded.flash = original_flash
package.loaded['render-markdown'] = original_renderer
package.loaded['config.search.flash'] = nil
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(buffer, { force = true })
