local replaced_modules = {
  'config.grep_preview',
  'config.lsp_locations',
  'config.python.hierarchy_index',
  'config.telescope',
  'config.type_hierarchy',
  'config.workspace_symbols',
  'telescope',
  'telescope.actions',
  'telescope.builtin',
  'telescope.themes',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local function no_op() end

local close_action = function() end
local telescope_options
package.loaded['telescope'] = {
  load_extension = function() end,
  setup = function(options)
    telescope_options = options
  end,
}
package.loaded['telescope.actions'] = { close = close_action }
package.loaded['telescope.builtin'] = {
  buffers = no_op,
  find_files = no_op,
  help_tags = no_op,
  keymaps = no_op,
  live_grep = no_op,
  lsp_document_symbols = no_op,
  oldfiles = no_op,
}
package.loaded['telescope.themes'] = {
  get_dropdown = function(options)
    return options
  end,
}
package.loaded['config.grep_preview'] = { new = function() end }
package.loaded['config.lsp_locations'] = {
  implementations = no_op,
  references = no_op,
}
package.loaded['config.python.hierarchy_index'] = { setup = function() end }
package.loaded['config.type_hierarchy'] = {
  open_implementations = no_op,
  open_subtypes = no_op,
  open_supertypes = no_op,
}
package.loaded['config.workspace_symbols'] = {
  open = function() end,
  open_for_cursor = function() end,
  setup = function() end,
}
package.loaded['config.telescope'] = nil

require('config.telescope').setup()

assert(telescope_options, 'Telescope was not configured')
local mappings = telescope_options.defaults.mappings
assert(mappings.i['<C-q>'] == close_action, 'insert-mode <C-q> did not close Telescope')
assert(mappings.n['<C-q>'] == close_action, 'normal-mode <C-q> did not close Telescope')

for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
