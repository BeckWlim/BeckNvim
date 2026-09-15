-- Focused tests for config.search.telescope.
local replaced_modules = {
  'config.search.grep_preview',
  'config.python.hierarchy_index',
  'config.search.telescope',
  'config.search.workspace_symbols',
  'telescope',
  'telescope.actions',
  'telescope.actions.state',
  'telescope.themes',
  'telescope.previewers',
  'telescope.previewers.utils',
  'telescope.pickers',
  'telescope.finders',
  'telescope.config',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local closed_prompt_buffer
local close_action = function(prompt_buffer)
  closed_prompt_buffer = prompt_buffer
end
local selected_prompt_buffer
local select_default_action = function(prompt_buffer)
  selected_prompt_buffer = prompt_buffer
end
local telescope_options
local current_picker = {}
package.loaded['telescope'] = {
  load_extension = function() end,
  setup = function(options)
    telescope_options = options
  end,
}
package.loaded['telescope.actions'] = {
  close = close_action,
  select_default = select_default_action,
}
package.loaded['telescope.actions.state'] = {
  get_current_picker = function()
    return current_picker
  end,
}
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

local telescope_config = require('config.search.telescope')
telescope_config.setup()

assert(telescope_options, 'Telescope was not configured')
local mappings = telescope_options.defaults.mappings
assert(mappings.i['<C-q>'] == close_action, 'insert-mode <C-q> did not close Telescope')
assert(mappings.n['<C-q>'] == close_action, 'normal-mode <C-q> did not close Telescope')
assert(mappings.i.q == nil, 'insert-mode q was consumed by Telescope')
assert(mappings.n.q == false, 'normal-mode q still closes Telescope')
assert(mappings.n['<Esc>'] == false and mappings.i['<C-c>'] == false,
  'Alternate close shortcuts remain enabled')
assert(
  mappings.i['<Tab>'] == telescope_config.focus_preview,
  'insert-mode Tab retained Telescope result selection'
)
assert(
  mappings.n['<Tab>'] == telescope_config.focus_preview,
  'normal-mode Tab retained Telescope result selection'
)

local prompt_window = vim.api.nvim_get_current_win()
local preview_buffer = vim.api.nvim_create_buf(false, true)
local preview_window = vim.api.nvim_open_win(preview_buffer, false, {
  relative = 'editor',
  row = 1,
  col = 1,
  width = 20,
  height = 5,
  style = 'minimal',
})
local picker_layout_updates = 0
current_picker.layout_config = vim.deepcopy(telescope_options.defaults.layout_config)
current_picker.previewer = { state = { winid = preview_window } }
current_picker.prompt_win = prompt_window
function current_picker:full_layout_update()
  picker_layout_updates = picker_layout_updates + 1
end

telescope_config.focus_preview(vim.api.nvim_win_get_buf(prompt_window))
assert(vim.api.nvim_get_current_win() == preview_window, 'Tab did not focus the grep preview')
assert(
  vim.wo[preview_window].cursorline and vim.wo[preview_window].cursorlineopt == 'line',
  'Focused Telescope preview did not use the editor CursorLine background hint'
)
assert(
  current_picker.layout_config.horizontal.preview_width == 0.65,
  'focused grep preview did not expand horizontally'
)
assert(
  current_picker.layout_config.vertical.preview_height == 0.58,
  'focused grep preview did not expand vertically'
)
local preview_tab_mapping = vim.iter(vim.api.nvim_buf_get_keymap(preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<Tab>'
  end
)
assert(preview_tab_mapping and preview_tab_mapping.callback, 'grep preview had no return Tab mapping')
local preview_close_mapping = vim.iter(vim.api.nvim_buf_get_keymap(preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == 'q'
  end
)
assert(preview_close_mapping and preview_close_mapping.rhs == '', 'grep preview still closes with q')
local preview_ctrl_q_mapping = vim.iter(vim.api.nvim_buf_get_keymap(preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<C-Q>'
  end
)
assert(preview_ctrl_q_mapping and preview_ctrl_q_mapping.callback, 'focused grep preview lost Ctrl-Q')
assert(not vim.bo[preview_buffer].modifiable and not vim.bo[preview_buffer].readonly,
  'Focused preview is editable')
local quit_ok = pcall(vim.cmd, 'q')
assert(not quit_ok and vim.api.nvim_win_is_valid(preview_window), ':q closed an individual preview pane')
local preview_enter_mapping = vim.iter(vim.api.nvim_buf_get_keymap(preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<CR>'
  end
)
assert(preview_enter_mapping and preview_enter_mapping.callback, 'grep preview had no jump mapping')
preview_enter_mapping.callback()
assert(
  selected_prompt_buffer == vim.api.nvim_win_get_buf(prompt_window),
  'preview Enter did not jump through the active Telescope selection'
)
preview_tab_mapping.callback()
assert(vim.api.nvim_get_current_win() == prompt_window, 'preview Tab did not return to results')
assert(vim.bo[preview_buffer].modifiable, 'Returning to results did not unlock native preview rendering')
assert(
  current_picker.layout_config.horizontal.preview_width == 0.55,
  'results and preview did not restore their balanced widths'
)
assert(
  current_picker.layout_config.vertical.preview_height == 0.36,
  'results did not reclaim vertical space after leaving the preview'
)

current_picker.close_preview_with_ctrl_q = true
current_picker.focus_layout = {
  preview_height = 0.68,
  preview_width = 0.72,
  results_height = 0.32,
  results_width = 0.42,
}
telescope_config.focus_preview(vim.api.nvim_win_get_buf(prompt_window))
assert(
  current_picker.layout_config.horizontal.preview_width == 0.72,
  'Git preview focus did not claim its configured horizontal width'
)
assert(
  current_picker.layout_config.vertical.preview_height == 0.68,
  'Git preview focus did not claim its configured vertical height'
)
local git_preview_buffer = vim.api.nvim_get_current_buf()
local git_preview_close_mapping = vim.iter(vim.api.nvim_buf_get_keymap(git_preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<C-Q>'
  end
)
assert(
  git_preview_close_mapping and git_preview_close_mapping.callback,
  'Git preview did not isolate Ctrl-Q as a close action'
)
git_preview_close_mapping.callback()
assert(
  closed_prompt_buffer == vim.api.nvim_win_get_buf(prompt_window),
  'Git preview Ctrl-Q did not close its owning picker'
)
local git_preview_tab_mapping = vim.iter(vim.api.nvim_buf_get_keymap(git_preview_buffer, 'n')):find(
  function(keymap)
    return keymap.lhs == '<Tab>'
  end
)
assert(git_preview_tab_mapping and git_preview_tab_mapping.callback, 'Git preview lost isolated Tab')
git_preview_tab_mapping.callback()
assert(vim.api.nvim_get_current_win() == prompt_window, 'Git preview Tab escaped its picker')
assert(
  current_picker.layout_config.horizontal.preview_width == 0.42,
  'Git results focus did not reclaim its configured horizontal width'
)
assert(
  current_picker.layout_config.vertical.preview_height == 0.32,
  'Git results focus did not reclaim its configured vertical height'
)
assert(picker_layout_updates == 4, 'focus changes did not refresh every Telescope layout')
vim.api.nvim_win_close(preview_window, true)

assert(
  telescope_options.defaults.layout_strategy == 'flex',
  'Telescope did not use an adaptive layout strategy'
)
local layout_config = telescope_options.defaults.layout_config
assert(layout_config.flex.flip_columns == 150, 'Telescope did not adapt at laptop width')
assert(layout_config.flex.flip_lines == 24, 'Telescope did not account for short displays')
assert(layout_config.horizontal.width == 0.82, 'Wide Telescope dialog occupied too much screen width')
assert(
  layout_config.horizontal.preview_width == 0.55,
  'Wide Telescope layout did not keep a compact results list'
)
assert(layout_config.vertical.width == 0.82, 'Narrow Telescope dialog occupied too much screen width')
assert(
  layout_config.vertical.preview_height == 0.36,
  'Narrow Telescope layout did not initially favor search results'
)

-- Live themes must leave the picker callback's suppressed-autocmd context.
local theme_previewer
package.loaded['telescope.previewers'] = {
  new_buffer_previewer = function(options) theme_previewer = options; return options end,
}
package.loaded['telescope.previewers.utils'] = { highlighter = function() end }
package.loaded['telescope.pickers'] = { new = function() return { find = function() end } end }
package.loaded['telescope.finders'] = { new_table = function(options) return options end }
package.loaded['telescope.config'] = { values = { generic_sorter = function() end } }
local previewed_names = {}
local scheme_events = 0
local theme_group = vim.api.nvim_create_augroup('theme_preview_event_test', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', {
  group = theme_group, callback = function() scheme_events = scheme_events + 1 end,
})
local function open_theme_preview()
  telescope_config.theme_picker({
    names = { 'habamax', 'morning' },
    preview = function(name)
      previewed_names[#previewed_names + 1] = name
      vim.api.nvim_cmd({ cmd = 'colorscheme', args = { name } }, {})
    end,
    close = function() end,
  })
end
local previous_theme = vim.g.colors_name or 'default'
open_theme_preview()
local theme_buffer = vim.api.nvim_create_buf(false, true)
local theme_instance = { state = { bufnr = theme_buffer } }
vim.api.nvim_create_autocmd('User', {
  group = theme_group, pattern = 'SuppressedThemePreview',
  callback = function()
    theme_previewer.define_preview(theme_instance, { value = 'habamax' })
    theme_previewer.define_preview(theme_instance, { value = 'morning' })
    assert(#previewed_names == 0, 'Theme application ran inside the picker autocmd')
  end,
})
vim.api.nvim_exec_autocmds('User', { pattern = 'SuppressedThemePreview' })
assert(vim.wait(500, function() return #previewed_names == 1 end))
assert(previewed_names[1] == 'morning' and scheme_events == 1,
  'Latest preview did not notify colorscheme consumers')
theme_previewer.define_preview(theme_instance, { value = 'habamax' })
theme_previewer.teardown()
vim.wait(30)
assert(#previewed_names == 1, 'Closed picker applied a queued theme')
open_theme_preview()
theme_previewer.define_preview(theme_instance, { value = 'habamax' })
vim.api.nvim_buf_delete(theme_buffer, { force = true })
vim.wait(30)
assert(#previewed_names == 1, 'Deleted preview buffer applied a queued theme')
theme_previewer.teardown()
vim.api.nvim_del_augroup_by_id(theme_group)
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { previous_theme } }, {})

for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
