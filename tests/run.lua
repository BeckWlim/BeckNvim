vim.opt.runtimepath:prepend(vim.fn.getcwd())

for _, test_file in ipairs({
  'tests/project.lua',
  'tests/python.lua',
  'tests/folds.lua',
  'tests/lsp_locations.lua',
  'tests/translation.lua',
  'tests/type_hierarchy.lua',
  'tests/workspace_symbols.lua',
}) do
  local test_chunk, load_error = loadfile(test_file)
  assert(test_chunk, load_error)
  test_chunk()
end

print('All tests passed')
