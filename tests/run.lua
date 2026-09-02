vim.opt.runtimepath:prepend(vim.fn.getcwd())

for _, test_file in ipairs({
  'tests/project.lua',
  'tests/statusline.lua',
  'tests/folder_picker.lua',
  'tests/dashboard.lua',
  'tests/python.lua',
  'tests/network_proxy.lua',
  'tests/terminal.lua',
  'tests/ui_float.lua',
  'tests/filetree.lua',
  'tests/folds.lua',
  'tests/treesitter.lua',
  'tests/syntax_visuals.lua',
  'tests/highlights.lua',
  'tests/treesitter_context.lua',
  'tests/grep_preview.lua',
  'tests/git.lua',
  'tests/git_lifecycle.lua',
  'tests/git_events.lua',
  'tests/github.lua',
  'tests/git_issue.lua',
  'tests/git_search.lua',
  'tests/diffview.lua',
  'tests/diagnostics.lua',
  'tests/telescope.lua',
  'tests/keybindings.lua',
  'tests/lsp_locations.lua',
  'tests/type_information.lua',
  'tests/translation.lua',
  'tests/audit.lua',
  'tests/type_hierarchy.lua',
  'tests/workspace_symbols.lua',
}) do
  local test_chunk, load_error = loadfile(test_file)
  assert(test_chunk, load_error)
  test_chunk()
end

print('All tests passed')
