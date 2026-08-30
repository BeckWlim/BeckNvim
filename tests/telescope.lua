local replaced_modules = {
  'config.search.grep_preview',
  'config.python.hierarchy_index',
  'config.search.telescope',
  'config.search.workspace_symbols',
  'telescope',
  'telescope.actions',
  'telescope.themes',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local close_action = function() end
local telescope_options
package.loaded['telescope'] = {
  load_extension = function() end,
  setup = function(options)
    telescope_options = options
  end,
}
package.loaded['telescope.actions'] = { close = close_action }
package.loaded['telescope.themes'] = {
  get_dropdown = function(options)
    return options
  end,
}
package.loaded['config.search.grep_preview'] = { new = function() end }
package.loaded['config.python.hierarchy_index'] = { setup = function() end }
package.loaded['config.search.workspace_symbols'] = {
  setup = function() end,
}
package.loaded['config.search.telescope'] = nil

require('config.search.telescope').setup()

assert(telescope_options, 'Telescope was not configured')
local mappings = telescope_options.defaults.mappings
assert(mappings.i['<C-q>'] == close_action, 'insert-mode <C-q> did not close Telescope')
assert(mappings.n['<C-q>'] == close_action, 'normal-mode <C-q> did not close Telescope')

for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
