-- nvim --headless -u init.lua -i NONE -l tests/ui/theme_git_installed.lua
-- Exercise repository history and real theme actions in the editor event loop.
local directory = vim.fn.tempname()
local original_directory = vim.fn.getcwd()
vim.fn.mkdir(directory, 'p')
local function git(arguments)
  local command = { 'git', '-C', directory }
  vim.list_extend(command, arguments)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
end
local function settle()
  vim.wait(40)
  vim.cmd('redraw')
end
local function input(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
  settle()
end
local function global_highlight(name)
  local definition = vim.api.nvim_get_hl(0, { name = name, link = true })
  return definition.link and global_highlight(definition.link) or definition
end
local function snapshot()
  local groups = {}
  for _, name in ipairs({ 'Normal', 'Function', 'String', 'Statement', 'CursorLine',
    'StatusLine', 'StatusLineNC', 'lualine_c_normal', 'lualine_c_inactive',
    'DiffviewNormal', 'DiffviewFilePanelTitle', 'DiffviewFilePanelSelected',
    'DiffviewCursorLine', 'DiffviewWinSeparator', 'DiffviewHash', 'DiffviewDiffAdd',
    'DiffviewDiffAddAsDelete', 'DiffviewDiffChange', 'DiffviewDiffText', 'DiffviewDiffDeleteDim' }) do
    groups[name] = global_highlight(name)
    groups[name].cterm = nil
    groups[name].ctermfg = nil
    groups[name].ctermbg = nil
  end
  return groups
end
local function expect_colors(expected, context)
  local actual = snapshot()
  for name, definition in pairs(expected) do
    assert(vim.deep_equal(actual[name], definition), context .. ': stale ' .. name .. ': '
      .. vim.inspect({ expected = definition, actual = actual[name] }))
  end
end
local function check()
  git({ 'init', '-q' })
  vim.fn.writefile({ 'local value = 1', 'print(value)' }, directory .. '/sample.lua')
  git({ 'add', 'sample.lua' })
  git({ '-c', 'user.name=Theme Test', '-c', 'user.email=theme@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture' })
  vim.fn.writefile({ 'local value = 2', 'print(value)' }, directory .. '/sample.lua')
  vim.api.nvim_set_current_dir(directory)
  vim.cmd.edit(directory .. '/sample.lua')
  local theme = require('config.ui.theme')
  theme.setup({ state_file = directory .. '/theme.json' })
  local telescope = require('telescope') --[[@as { setup: fun(options: table) }]]
  telescope.setup({ defaults = { history = { path = directory .. '/telescope_history' } } })
  require('diffview')
  local variants = { 'monokai', 'vscode-dark', 'darcula-dark', 'tokyonight-night',
    'catppuccin-mocha', 'catppuccin-latte', 'gruvbox-dark', 'paper-light' }
  local expected = {}
  for _, name in ipairs(variants) do
    assert(theme.select(name))
    settle()
    expected[name] = snapshot()
  end
  input(' dr')
  assert(vim.wait(5000, function()
    local view = require('diffview.lib').get_current_view()
    return view and require('config.git.lifecycle').is_ready(view)
  end, 10), 'Space-dr did not load repository history')
  local view = require('diffview.lib').get_current_view()
  local entry = view.panel.entries[1]
  local details_loaded = false
  require('config.git.footer_loader').ensure_entry(view, entry, function(loaded) details_loaded = loaded end)
  assert(vim.wait(5000, function() return details_loaded end, 10), 'History file details did not load')
  local file = vim.iter(entry.files):find(function(candidate) return candidate.path == 'sample.lua' end)
  assert(file, 'History omitted the code fixture')
  vim.api.nvim_set_current_win(view.panel.winid)
  view.panel:highlight_item(file)
  assert(view.panel:get_item_at_cursor() == file, 'History did not focus the fixture file row')
  input('<CR>')
  assert(vim.wait(5000, function()
    return view.cur_entry == file and require('config.git.lifecycle').render_is_ready(view)
  end, 10), 'History Enter did not render the code panes')
  local windows = vim.api.nvim_tabpage_list_wins(0)
  for _, pane in ipairs({ 'footer', 'code' }) do
    local source_window = pane == 'footer' and view.panel.winid or view.cur_layout:get_main_win().id
    vim.api.nvim_set_current_win(source_window)
    settle()
    for _, name in ipairs(variants) do
      assert(theme.select(name))
      settle()
      expect_colors(expected[name], pane .. ' direct ' .. name)
      local previous_name = vim.o.background == 'light' and 'monokai' or 'paper-light'
      assert(theme.select(previous_name))
      settle()
      local function preview()
        vim.cmd('Theme')
        local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
        picker:set_prompt(name)
        assert(vim.wait(3000, function() return theme.current().name == name end, 10), 'Theme preview did not load')
        settle()
        expect_colors(expected[name], pane .. ' preview ' .. name)
      end
      preview()
      input('<C-q>')
      assert(vim.api.nvim_get_current_win() == source_window, 'Theme cancellation lost the Git pane')
      expect_colors(expected[previous_name], pane .. ' rollback ' .. name)
      preview()
      input('<CR>')
      assert(vim.api.nvim_get_current_win() == source_window, 'Theme confirmation lost the Git pane')
      expect_colors(expected[name], pane .. ' confirmed ' .. name)
      assert(require('diffview.lib').get_current_view() == view and view.cur_entry == file,
        'Theme switch changed Git file selection')
      assert(vim.deep_equal(windows, vim.api.nvim_tabpage_list_wins(0)), 'Theme switch rebuilt Git panes')
    end
  end
  input('<C-q>')
  assert(vim.wait(3000, function() return not require('config.git.diffview').is_active() end, 10),
    'Git mode did not close')
end
local passed, failure = xpcall(check, debug.traceback)
vim.api.nvim_set_current_dir(original_directory)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Repository history code/footer themes, live preview, confirmation, and rollback passed')
