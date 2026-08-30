local replaced_modules = {
  'config.audit.diagnostic',
  'config.audit.project',
  'config.ui.dashboard',
  'config.lsp.diagnostics',
  'config.syntax.folds',
  'config.startup.keybindings',
  'config.lsp',
  'config.search.lsp_locations',
  'config.search.navigation',
  'config.translation',
  'config.syntax.treesitter_context',
  'config.type_hierarchy',
  'config.lsp.type_information',
  'config.search.workspace_symbols',
  'telescope.builtin',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local function no_op() end

package.loaded['config.audit.diagnostic'] = { open = no_op }
package.loaded['config.audit.project'] = { run_or_open = no_op }
package.loaded['config.ui.dashboard'] = { open = no_op }
package.loaded['config.lsp.diagnostics'] = {
  open_float = no_op,
  open_picker = no_op,
  setup = no_op,
}
package.loaded['config.syntax.folds'] = { toggle = no_op }
package.loaded['config.lsp'] = { toggle_third_party_checks = no_op }
package.loaded['config.search.lsp_locations'] = {
  declarations = no_op,
  definitions = no_op,
  implementations = no_op,
  references = no_op,
  type_definitions = no_op,
}
package.loaded['config.search.navigation'] = {
  goto_referenced_file = no_op,
  goto_referenced_file_in_split = no_op,
}
package.loaded['config.translation'] = { open = no_op }
package.loaded['config.syntax.treesitter_context'] = { go_to_nearest_context = no_op }
package.loaded['config.type_hierarchy'] = {
  open_implementations = no_op,
  open_subtypes = no_op,
  open_supertypes = no_op,
}
package.loaded['config.lsp.type_information'] = { toggle = no_op }
package.loaded['config.search.workspace_symbols'] = {
  open = no_op,
  open_for_cursor = no_op,
}
package.loaded['telescope.builtin'] = setmetatable({}, {
  __index = function()
    return no_op
  end,
})
package.loaded['config.startup.keybindings'] = nil

require('config.startup.keybindings').setup()

local expected_mappings = {
  '<Space>wi', '<Space>wj', '<Space>wk', '<Space>wl',
  '<Space>wv', '<Space>ws', '<Space>wq', '<Space>wo',
  '<Space>ri', '<Space>rk', '<Space>rj', '<Space>rl', '<Space>r=',
  '<Tab>', '<S-Tab>', '<Space>o', '<Space>p',
  '<Space>zz', '<Space>zc', '<Space>zo', '<Space>cc',
  '<Space>gf', '<Space>gv', '<Space>gx',
  '<F3>', '<Space>h', '<Space>mp', '<Space>t',
  '<Space>ff', '<Space>fv', '<Space>fg', '<Space>fb', '<Space>fr',
  '<Space>bv', '<Space>fh', '<Space>fk', '<Space>fs', '<Space>fw', '<Space>ft',
  '<Space>e', '[d', ']d', '<Space>q', '<Space>gq', '<Space>gs',
  'gd', 'gD', 'gr', 'gI', '<Space>i', '<Space>D',
  '<Space>cd', '<Space>cb', '<Space>ci',
  '<Space>rn', 'K', '<Space>k', '<Space>lp',
}

for _, lhs in ipairs(expected_mappings) do
  local mapping = vim.fn.maparg(lhs, 'n', false, true)
  assert(
    type(mapping) == 'table' and mapping.lhs == lhs,
    'Expected normal-mode mapping is missing: ' .. lhs
  )
  assert(mapping.desc and mapping.desc ~= '', 'Mapping has no description: ' .. lhs)
end

assert(
  vim.fn.maparg('gr', 'n', false, true).nowait == 1,
  'gr did not keep its nowait behavior'
)

for _, lhs in ipairs(expected_mappings) do
  vim.keymap.del('n', lhs)
end
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
