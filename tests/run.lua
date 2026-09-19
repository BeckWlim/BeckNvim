vim.opt.runtimepath:prepend(vim.fn.getcwd())
dofile('tests/markdown_runtime.lua')

for _, test_file in ipairs({
  'tests/user.lua',
  'tests/project.lua',
  'tests/audit/workflow.lua',
  'tests/git/diffview.lua',
  'tests/git/events.lua',
  'tests/git/footer_loader.lua',
  'tests/git/github.lua',
  'tests/git/init.lua',
  'tests/git/issue.lua',
  'tests/git/lifecycle.lua',
  'tests/git/reference.lua',
  'tests/git/search.lua',
  'tests/git/settings.lua',
  'tests/lsp/diagnostics.lua',
  'tests/lsp/init.lua',
  'tests/lsp/type_information.lua',
  'tests/network/proxy.lua',
  'tests/python/environment.lua',
  'tests/python/missing_runtime.lua',
  'tests/search/grep_preview.lua',
  'tests/search/lsp_locations.lua',
  'tests/search/telescope.lua',
  'tests/search/workspace_symbols.lua',
  'tests/startup/keybindings.lua',
  'tests/startup/jumps.lua',
  'tests/startup/lazy.lua',
  'tests/startup/termaid.lua',
  'tests/syntax/folds.lua',
  'tests/syntax/highlights.lua',
  'tests/syntax/markdown/configuration.lua',
  'tests/syntax/markdown/links.lua',
  'tests/syntax/selection.lua',
  'tests/syntax/treesitter.lua',
  'tests/syntax/treesitter_context.lua',
  'tests/syntax/visuals.lua',
  'tests/translation/init.lua',
  'tests/type_hierarchy/init.lua',
  'tests/ui/dashboard.lua',
  'tests/ui/filetree.lua',
  'tests/ui/float.lua',
  'tests/ui/folder_picker.lua',
  'tests/ui/open_target.lua',
  'tests/ui/statusline.lua',
  'tests/ui/terminal.lua',
  'tests/ui/window_state.lua',
  'tests/ui/theme.lua',
  'tests/ui/tmux.lua',
}) do
  local test_chunk, load_error = loadfile(test_file)
  assert(test_chunk, load_error)
  test_chunk()
end

print('All tests passed')
