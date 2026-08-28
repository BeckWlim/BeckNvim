vim.opt.runtimepath:prepend(vim.fn.getcwd())

for _, test_file in ipairs({
  'tests/project.lua',
  'tests/statusline.lua',
  'tests/dashboard.lua',
  'tests/python.lua',
  'tests/terminal.lua',
  'tests/filetree.lua',
  'tests/folds.lua',
  'tests/syntax_visuals.lua',
  'tests/highlights.lua',
  'tests/treesitter_context.lua',
  'tests/grep_preview.lua',
  'tests/diagnostics.lua',
  'tests/telescope.lua',
  'tests/lsp_locations.lua',
  'tests/type_information.lua',
  'tests/translation.lua',
  'tests/type_hierarchy.lua',
  'tests/workspace_symbols.lua',
}) do
  local test_chunk, load_error = loadfile(test_file)
  assert(test_chunk, load_error)
  test_chunk()
end

print('All tests passed')
