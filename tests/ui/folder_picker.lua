-- Focused tests for config.ui.folder_picker.
local replaced_modules = {
  'config.ui.folder_picker',
  'telescope.actions',
  'telescope.actions.state',
  'telescope.config',
  'telescope.finders',
  'telescope.pickers',
  'telescope.pickers.entry_display',
  'telescope.previewers',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local picker_options
local picker_spec
local picker_find_calls = 0
local picker_prompt
local closed_prompt_buffer
local selected_callback
local selected_entry
local current_line = ''
local refreshed_finder
local picker_layout_updates = 0
local fake_picker
local entry_display_configuration

package.loaded['telescope.finders'] = {
  new_dynamic = function(options)
    return options
  end,
}
package.loaded['telescope.config'] = {
  values = {
    generic_sorter = function()
      return 'folder-sorter'
    end,
  },
}
package.loaded['telescope.actions'] = {
  close = function(prompt_buffer)
    closed_prompt_buffer = prompt_buffer
  end,
  select_default = {
    replace = function(_, callback)
      selected_callback = callback
    end,
  },
}
package.loaded['telescope.actions.state'] = {
  get_current_line = function()
    return current_line
  end,
  get_selected_entry = function()
    return selected_entry
  end,
}
package.loaded['telescope.pickers'] = {
  new = function(options, spec)
    picker_options = options
    picker_spec = spec
    fake_picker = {
      layout_config = vim.deepcopy(options.layout_config),
      find = function()
        picker_find_calls = picker_find_calls + 1
      end,
      full_layout_update = function()
        picker_layout_updates = picker_layout_updates + 1
      end,
      refresh = function(_, finder)
        refreshed_finder = finder
      end,
      set_prompt = function(_, prompt)
        picker_prompt = prompt
      end,
    }
    return fake_picker
  end,
}
package.loaded['telescope.previewers'] = {
  new_buffer_previewer = function(options)
    return options
  end,
}
package.loaded['telescope.pickers.entry_display'] = {
  create = function(configuration)
    entry_display_configuration = configuration
    return function(parts)
      local text = {}
      for _, part in ipairs(parts) do
        text[#text + 1] = type(part) == 'table' and part[1] or part
      end
      return table.concat(text, ' ')
    end
  end,
}
package.loaded['config.ui.folder_picker'] = nil

local folder_picker = require('config.ui.folder_picker')
local temporary_root = vim.fn.tempname()
local alpha_folder = vim.fs.joinpath(temporary_root, 'alpha')
local beta_folder = vim.fs.joinpath(temporary_root, 'beta')
local plain_folder = vim.fs.joinpath(temporary_root, 'plain-folder')
vim.fn.mkdir(vim.fs.joinpath(temporary_root, '.git'), 'p')
vim.fn.mkdir(alpha_folder, 'p')
vim.fn.mkdir(beta_folder, 'p')
vim.fn.mkdir(plain_folder, 'p')

local folder_entries = folder_picker.entries(temporary_root)
assert(folder_entries[1].kind == 'current', 'folder picker omitted the current directory')
assert(folder_entries[2].kind == 'parent', 'folder picker omitted parent navigation')
local folder_paths = {}
for _, folder_entry in ipairs(folder_entries) do
  folder_paths[folder_entry.path] = true
end
for _, expected_folder in ipairs({ alpha_folder, beta_folder, plain_folder }) do
  assert(folder_paths[expected_folder], 'folder picker omitted an ordinary child directory')
end
assert(
  not folder_paths[vim.fs.joinpath(temporary_root, '.git')],
  'folder picker exposed internal Git metadata'
)

local compact_layout = folder_picker.layout(
  { { display = '󰉋  src/' }, { display = '󰉋  tests/' } },
  'Open Folder',
  120,
  40
)
local populated_entries = {}
for entry_index = 1, 100 do
  populated_entries[entry_index] = { display = ('󰉋  folder-%03d/'):format(entry_index) }
end
local populated_layout = folder_picker.layout(populated_entries, 'Open Folder', 120, 40)
assert(
  compact_layout.height == folder_picker.minimum_height,
  'limited folder content did not produce a compact panel'
)
assert(
  populated_layout.height == folder_picker.maximum_height,
  'large folder content exceeded the panel height cap'
)
assert(
  compact_layout.width <= folder_picker.maximum_width,
  'folder panel exceeded its width cap'
)

local absolute_query = folder_picker.query(
  vim.fs.joinpath(temporary_root, 'pla'),
  beta_folder
)
assert(
  absolute_query.directory == temporary_root
    and absolute_query.leaf == 'pla'
    and absolute_query.path_query,
  'folder picker did not resolve an external absolute prefix'
)
local relative_query = folder_picker.query('../alpha', beta_folder)
assert(
  relative_query.directory == temporary_root
    and relative_query.leaf == 'alpha'
    and relative_query.path_query,
  'folder picker did not resolve a parent-relative prefix'
)
assert(
  folder_picker.existing_path('../plain-folder', beta_folder) == plain_folder,
  'folder picker rejected an exact relative directory'
)
assert(
  folder_picker.completion_prefix('pla', plain_folder, temporary_root) == 'plain-folder/',
  'Tab completion did not produce a relative folder prefix'
)
assert(
  folder_picker.completion_prefix(plain_folder, plain_folder, beta_folder)
    == plain_folder .. '/',
  'Tab completion did not preserve an absolute prefix'
)
assert(
  folder_picker.completion_prefix('../pla', plain_folder, beta_folder)
    == '../plain-folder/',
  'Tab completion did not preserve parent-relative navigation'
)
local scoped_root, scoped_query, direct_children = folder_picker.search_scope(
  temporary_root,
  temporary_root .. '/'
)
assert(
  scoped_root == temporary_root and scoped_query == '' and direct_children,
  'folder picker did not expand an existing path prefix into a directory scope'
)
scoped_root, scoped_query, direct_children = folder_picker.search_scope(
  temporary_root,
  vim.fs.joinpath(temporary_root, 'pla')
)
assert(
  scoped_root == temporary_root and scoped_query == 'pla' and not direct_children,
  'folder picker did not split a partial path into its parent and leaf query'
)

local chosen_folder
local picker_closed = false
folder_picker.open({
  starting_directory = beta_folder,
  search_root = temporary_root,
  on_select = function(folder_path)
    chosen_folder = folder_path
  end,
  on_close = function()
    picker_closed = true
  end,
})
assert(picker_find_calls == 1, 'folder picker did not start Telescope')
assert(picker_options.cwd == temporary_root, 'folder picker did not use the search root')
assert(
  picker_spec.prompt_title == 'Switch Project',
  'folder picker did not use the project-switcher title'
)
assert(type(picker_spec.finder) == 'table', 'folder picker did not create an async directory finder')
assert(
  picker_spec.previewer and picker_spec.previewer.title == 'Project tree',
  'folder picker did not attach a project-tree previewer'
)
assert(
  entry_display_configuration.items[2].width == 0.30
    and entry_display_configuration.items[3].width == 0.18
    and entry_display_configuration.items[4].width == 0.50
    and not entry_display_configuration.items[2].right_justify
    and not entry_display_configuration.items[3].right_justify
    and not entry_display_configuration.items[4].right_justify,
  'project results did not use independent left-aligned name, branch, and path columns'
)
local initial_entries = {}
picker_spec.finder('', function(entry)
  initial_entries[#initial_entries + 1] = entry
end, function() end)
assert(
  initial_entries[1].shortcut == '.' and initial_entries[2].shortcut == '..',
  'folder picker did not expose current and parent path shortcuts'
)

local prompt_buffer = vim.api.nvim_create_buf(false, true)
local telescope_mapped_keys = { i = {}, n = {} }
local function telescope_map(modes, lhs, callback, options)
  local mapped_modes = type(modes) == 'table' and modes or { modes }
  for _, mode in ipairs(mapped_modes) do
    telescope_mapped_keys[mode][lhs] = true
  end
  local mapping_options = vim.tbl_extend('force', options or {}, {
    buffer = prompt_buffer,
    silent = true,
  })
  vim.keymap.set(modes, lhs, callback, mapping_options)
end
assert(
  picker_spec.attach_mappings(prompt_buffer, telescope_map),
  'folder picker discarded Telescope mappings'
)
assert(
  type(selected_callback) == 'function',
  'folder picker did not replace selection behavior'
)
selected_entry = initial_entries[1]
selected_callback()
assert(
  closed_prompt_buffer == nil
    and picker_prompt == vim.fn.fnamemodify(beta_folder, ':~'),
  'current-path shortcut did not update the search scope'
)
selected_entry = { value = plain_folder }
selected_callback()
assert(closed_prompt_buffer == prompt_buffer, 'folder selection did not close Telescope')
assert(chosen_folder == plain_folder, 'folder selection did not return the selected folder')

local tree_lines = folder_picker.project_tree_lines(beta_folder, {
  'd\tdocs',
  'f\tdocs/guide.md',
  'f\tREADME.md',
})
local tree_text = table.concat(tree_lines, '\n')
assert(tree_text:find('docs', 1, true), 'project preview omitted a directory')
assert(tree_text:find('guide.md', 1, true), 'project preview omitted a file')
assert(tree_text:find('README.md', 1, true), 'project preview omitted a root file')

vim.api.nvim_buf_delete(prompt_buffer, { force = true })
assert(vim.wait(100, function()
  return picker_closed
end, 10), 'folder picker did not release its caller boundary')
vim.fn.delete(temporary_root, 'rf')
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
