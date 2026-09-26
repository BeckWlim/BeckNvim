-- Focused tests for config.startup.keybindings.
local original_buffer = vim.api.nvim_get_current_buf()
local keybinding_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(keybinding_buffer)

local replaced_modules = {
  'config.audit.diagnostic',
  'config.audit.project',
  'config.ui.dashboard',
  'config.lsp.diagnostics',
  'config.syntax.folds',
  'config.startup.keybindings',
  'config.lsp',
  'config.search.lsp_locations',
  'config.git',
  'config.search.navigation',
  'config.syntax.selection',
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
local git_search_calls = 0

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
package.loaded['config.git'] = {
  history_file = no_op,
  history_repository = no_op,
  history_symbol = no_op,
  search_repository = function()
    git_search_calls = git_search_calls + 1
  end,
}
package.loaded['config.search.navigation'] = {
  goto_referenced_file = no_op,
  goto_referenced_file_in_split = no_op,
}
package.loaded['config.syntax.selection'] = {
  move_next = no_op,
  move_previous = no_op,
  select_next = no_op,
  select_previous = no_op,
  setup = no_op,
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
  '<Space>wh', '<Space>wj', '<Space>wk', '<Space>wl',
  '<Space>wv', '<Space>ws', '<Space>wq', '<Space>wo',
  '<Space>rh', '<Space>rj', '<Space>rk', '<Space>rl', '<Space>r=',
  '<Tab>', '<S-Tab>', '<Space>o', '<Space>p',
  'a', '<Space>zz', '<Space>zc', '<Space>zo', '<Space>cc',
  '<C-a>', '<C-e>', '<C-Left>', '<C-Right>', '<Space>s',
  '<C-h>', '<C-j>', '<C-k>', '<C-l>',
  '<Space>gf', '<Space>gv', '<Space>gx', 'gx',
  '<Space>bt', '<Space>h', '<Space>mp', '<Space>t',
  '<Space>ff', '<Space>fv', '<Space>fg', '<Space>fb', '<Space>fr',
  '<Space>bv', '<Space>fh', '<Space>fk', '<Space>fs', '<Space>fw', '<Space>ft', '<Space>fp',
  '<Space>de', '<Space>df', '<Space>ds', '<Space>dr',
  '<Space>e', '[d', ']d', '<Space>q', '<Space>gq', '<Space>gs',
  'gd', 'gD', 'gr', 'gI', '<Space>i', '<Space>D',
  '<Space>cd', '<Space>cb', '<Space>ci',
  '<Space>rn', 'K', '<Space>k', '<Space>lp',
}

for _, lhs in ipairs(expected_mappings) do
  local mapping = vim.fn.maparg(lhs, 'n', false, true)
  assert(
    type(mapping) == 'table' and mapping.lhs:lower() == lhs:lower(),
    'Expected normal-mode mapping is missing: ' .. lhs
  )
  assert(mapping.desc and mapping.desc ~= '', 'Mapping has no description: ' .. lhs)
end

local visual_gx_mapping = vim.fn.maparg('gx', 'x', false, true)
assert(
  type(visual_gx_mapping) == 'table'
    and visual_gx_mapping.lhs == 'gx'
    and visual_gx_mapping.callback,
  'Expected visual-mode gx mapping is missing'
)

local visual_quit_mapping = vim.fn.maparg('q', 'x', false, true)
assert(
  type(visual_quit_mapping) == 'table'
    and visual_quit_mapping.lhs == 'q'
    and visual_quit_mapping.rhs == '<Esc>',
  'Visual-mode q does not exit Visual mode'
)
assert(visual_quit_mapping.desc == 'Exit Visual mode', 'Visual-mode q has no description')

for _, lhs in ipairs({ '<C-Left>', '<C-Right>' }) do
  local mapping = vim.fn.maparg(lhs, 'x', false, true)
  assert(
    type(mapping) == 'table' and mapping.lhs:lower() == lhs:lower() and mapping.callback,
    'Expected semantic visual mapping is missing: ' .. lhs
  )
  assert(mapping.desc and mapping.desc ~= '', 'Visual mapping has no description: ' .. lhs)
end
for _, lhs in ipairs({ '<Space>vj', '<Space>vl', '<Space>vs', '<Space>vc', '<Space>vS' }) do
  for _, mode in ipairs({ 'n', 'x' }) do
    assert(
      vim.tbl_isempty(vim.fn.maparg(lhs, mode, false, true)),
      'Obsolete semantic-selection mapping is still present: ' .. lhs
    )
  end
end

vim.fn.maparg('<Space>de', 'n', false, true).callback()
assert(git_search_calls == 1, 'Space-de did not open standalone repository Git search')

local jump_back_mapping = vim.fn.maparg('<Space>o', 'n', false, true)
assert(jump_back_mapping.rhs == '<C-o>', 'Space-o is not a pure jump-back mapping')

local append_mapping = vim.fn.maparg('a', 'n', false, true)
assert(append_mapping.rhs == '<Nop>', 'Normal-mode a still enters append mode')

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end

vim.api.nvim_buf_set_lines(keybinding_buffer, 0, -1, false, { 'first', 'second', 'third' })
vim.api.nvim_win_set_cursor(0, { 2, 2 })
press('<C-h><C-k>')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 1 }), 'Normal Ctrl-h/k did not move left/up')
press('<C-j><C-l>')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), 'Normal Ctrl-j/l did not move down/right')

vim.api.nvim_buf_set_lines(keybinding_buffer, 0, -1, false, { '  alpha β' })
vim.api.nvim_win_set_cursor(0, { 1, 4 })
press('<C-a>')
assert(vim.api.nvim_win_get_cursor(0)[2] == 0, 'Ctrl-a did not move before indentation')
press('<C-e>')
assert(vim.api.nvim_win_get_cursor(0)[2] == 8, 'Ctrl-e did not reach the final Unicode character')
press('i<C-a>X<C-e>Y<Esc>')
assert(vim.api.nvim_get_current_line() == 'X  alpha βY', 'Insert line movement lost text or end position')
vim.api.nvim_win_set_cursor(0, { 1, 4 })
press('v<C-a>')
assert(vim.api.nvim_get_mode().mode == 'v', 'Ctrl-a left Visual mode')
assert(vim.fn.getpos('v')[3] == 5 and vim.api.nvim_win_get_cursor(0)[2] == 0,
  'Ctrl-a did not preserve the Visual anchor')
press('<C-e>')
assert(vim.api.nvim_win_get_cursor(0)[2] >= #vim.api.nvim_get_current_line() - 1,
  'Ctrl-e did not extend the selection to the end')
press('<Esc>')
press(':let g:line_motion_probe = "middle"<C-a><C-e><CR>')
assert(vim.g.line_motion_probe == 'middle', 'Command-line movement changed command text')
vim.g.line_motion_probe = nil

assert(
  vim.fn.maparg('gr', 'n', false, true).nowait == 1,
  'gr did not keep its nowait behavior'
)

for _, lhs in ipairs(expected_mappings) do
  vim.keymap.del('n', lhs)
end
vim.keymap.del('x', 'gx')
vim.keymap.del('x', 'q')
for _, lhs in ipairs({ '<C-Left>', '<C-Right>', '<C-a>', '<C-e>' }) do
  vim.keymap.del('x', lhs)
end
for _, mode in ipairs({ 'i', 'c' }) do
  vim.keymap.del(mode, '<C-a>')
  vim.keymap.del(mode, '<C-e>')
end
vim.keymap.del('i', '<C-Left>')
vim.keymap.del('i', '<C-Right>')
vim.keymap.del('i', '<C-p>')
vim.keymap.del('i', '<C-d>')
for _, mode in ipairs({ 'i', 'x', 's' }) do
  vim.keymap.del(mode, '<C-c>')
end
for _, key in ipairs({ '<C-h>', '<C-j>', '<C-k>', '<C-l>' }) do
  vim.keymap.del('x', key)
  vim.keymap.del('i', key)
end
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(keybinding_buffer, { force = true })
