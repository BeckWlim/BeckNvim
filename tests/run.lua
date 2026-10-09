vim.opt.runtimepath:prepend(vim.fn.getcwd())
dofile('tests/markdown_runtime.lua')
require('config.navigation.write_guard').setup()

local test_files = {
  'tests/state.lua',
  'tests/user.lua',
  'tests/project.lua',
  'tests/navigation.lua',
  'tests/navigation/write_guard.lua',
  'tests/keybindings.lua',
  'tests/audit/workflow.lua',
  'tests/git/diffview.lua',
  'tests/git/events.lua',
  'tests/git/footer_loader.lua',
  'tests/git/footer_search.lua',
  'tests/git/graph.lua',
  'tests/git/graph_search.lua',
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
  'tests/search/flash.lua',
  'tests/search/grep_preview.lua',
  'tests/search/lsp_locations.lua',
  'tests/search/telescope.lua',
  'tests/search/workspace_symbols.lua',
  'tests/startup/keybindings.lua',
  'tests/startup/jumps.lua',
  'tests/startup/logs.lua',
  'tests/startup/lazy.lua',
  'tests/startup/termaid.lua',
  'tests/syntax/folds.lua',
  'tests/syntax/highlights.lua',
  'tests/syntax/markdown/configuration.lua',
  'tests/syntax/markdown/contexts.lua',
  'tests/syntax/markdown/links.lua',
  'tests/syntax/treesitter.lua',
  'tests/syntax/treesitter_context.lua',
  'tests/syntax/visuals.lua',
  'tests/translation/init.lua',
  'tests/type_hierarchy/init.lua',
  'tests/ui/dashboard.lua',
  'tests/ui/filetree.lua',
  'tests/ui/file_operations.lua',
  'tests/ui/file_operations_markdown.lua',
  'tests/ui/tree_search.lua',
  'tests/ui/float.lua',
  'tests/ui/folder_picker.lua',
  'tests/ui/open_target.lua',
  'tests/ui/statusline.lua',
  'tests/ui/terminal.lua',
  'tests/ui/window_state.lua',
  'tests/ui/window_context.lua',
  'tests/ui/theme.lua',
  'tests/ui/tmux.lua',
}

-- Optional module/family filters keep focused changes from requiring every case.
local selected, matched = {}, {}
for _, test_file in ipairs(test_files) do
  local relative = test_file:sub(7, -5)
  local included = #arg == 0
  for index, filter in ipairs(arg) do
    local name = filter:gsub('^tests/', ''):gsub('%.lua$', ''):gsub('/+$', '')
    if relative == name or relative:sub(1, #name + 1) == name .. '/' then
      included, matched[index] = true, true
    end
  end
  if included then selected[#selected + 1] = test_file end
end
for index, filter in ipairs(arg) do
  assert(matched[index], 'No test matches: ' .. filter)
end

for _, test_file in ipairs(selected) do
  local test_chunk, load_error = loadfile(test_file)
  assert(test_chunk, load_error)
  test_chunk()
end

print(('All %d selected tests passed'):format(#selected))
