-- Run with: nvim --headless -u init.lua -i NONE '+luafile tests/ui/filetree_navigation_installed.lua'
-- Advance on native picker completion; keep Neovim's event loop running.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/folder', 'p')
vim.fn.mkdir(directory .. '/.git', 'p')
vim.fn.writefile({ '-- fixture', 'local function navigation_target() end' }, directory .. '/target.lua')
vim.fn.writefile({ 'return true' }, directory .. '/other.lua')
local finished = false
local editor_window
local tree_window

local function finish(failure)
  if finished then return end
  finished = true
  vim.api.nvim_create_autocmd('VimLeave', {
    once = true,
    callback = function() vim.fn.delete(directory, 'rf') end,
  })
  if failure then
    vim.api.nvim_err_writeln(failure)
    vim.cmd('cquit 1')
  else
    print('Installed file-tree focus and search navigation checks passed')
    vim.cmd('qa!')
  end
end

local function step(callback)
  vim.schedule(function()
    if finished then return end
    local succeeded, failure = xpcall(callback, debug.traceback)
    if not succeeded then finish(failure) end
  end)
end

local function search(on_complete, symbol)
  assert(vim.api.nvim_get_current_win() == tree_window, 'Search did not start in the tree')
  local mapping = vim.fn.maparg('<Space>fw', 'n', false, true)
  mapping.callback({ default_text = symbol or 'navigation_target' })
  local prompt_buffer = vim.api.nvim_get_current_buf()
  local picker = require('telescope.actions.state').get_current_picker(prompt_buffer)
  local completed = false
  picker:register_completion_callback(function()
    if completed then return end
    completed = true
    step(function()
      assert(picker.manager:num_results() == 1, 'Definition search did not find the fixture: '
        .. vim.inspect({ prompt = picker:_get_prompt(), cwd = picker.cwd, count = picker.manager:num_results() }))
      picker:set_selection(picker:get_row(1))
      assert(picker:get_selection().lnum == 2, 'Search selected the wrong definition')
      on_complete(prompt_buffer)
    end)
  end)
end

local function select(prompt_buffer, filename)
  require('telescope.actions').select_default(prompt_buffer)
  assert(vim.api.nvim_buf_get_name(0) == directory .. '/' .. (filename or 'target.lua'),
    'Selection did not open its file')
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'Search lost the definition line')
  assert(vim.bo[vim.api.nvim_win_get_buf(tree_window)].filetype == 'NvimTree', 'Search replaced the tree')
  assert(not vim.wo[tree_window].number, 'Search enabled line numbers in the tree')
end

local function check_tree_selection()
  local api = require('nvim-tree.api')
  for _, key in ipairs({ '<CR>', 'o' }) do
    api.tree.focus()
    api.tree.find_file({ buf = directory .. '/other.lua', focus = true })
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.fn.maparg(key, 'n', false, true).callback()
    assert(vim.api.nvim_get_current_win() == tree_window, 'Opening a file stole tree focus')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor), 'Tree selection moved')
    local buffer = vim.api.nvim_win_get_buf(editor_window)
    assert(vim.api.nvim_buf_get_name(buffer) == directory .. '/other.lua', 'Tree did not open selected file')
    assert(vim.bo[buffer].buflisted and vim.bo[buffer].bufhidden ~= 'delete', 'File became a temporary preview')
  end
  api.tree.find_file({ buf = directory .. '/folder', focus = true })
  vim.fn.maparg('<CR>', 'n', false, true).callback()
  assert(api.tree.get_node_under_cursor().open, 'Enter did not expand directory')
  vim.fn.maparg('o', 'n', false, true).callback()
  assert(not api.tree.get_node_under_cursor().open, 'o did not collapse directory')
end

local function check_tree_only()
  require('nvim-tree.api').tree.focus()
  vim.api.nvim_win_close(editor_window, true)
  vim.fn.writefile({ '-- fixture', 'local function fresh_target() end' }, directory .. '/fresh.lua')
  search(function(prompt_buffer)
    select(prompt_buffer, 'fresh.lua')
    assert(vim.wo.number == vim.go.number and vim.wo.relativenumber == vim.go.relativenumber,
      'New editor inherited tree line-number settings')
    assert(vim.api.nvim_get_current_win() ~= tree_window, 'Tree-only search replaced the tree')
    assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'Tree-only search left extra windows')
    finish()
  end, 'fresh_target')
end

local function check_editor_preferences()
  check_tree_selection()
  vim.api.nvim_win_call(editor_window, function()
    vim.cmd.edit(directory .. '/target.lua')
    vim.wo.number = false
  end)
  search(function(prompt_buffer)
    select(prompt_buffer)
    assert(vim.api.nvim_get_current_win() == editor_window, 'Search lost editor target')
    assert(not vim.wo.number and vim.wo.relativenumber, 'Search overwrote editor preferences')
    step(check_tree_only)
  end)
end

step(function()
  vim.o.columns, vim.o.lines = 120, 40
  vim.cmd('cd ' .. vim.fn.fnameescape(directory))
  vim.cmd('enew!')
  require('config.project').activate(directory)
  editor_window = vim.api.nvim_get_current_win()
  vim.wo.number, vim.wo.relativenumber = true, true
  require('telescope')
  require('nvim-tree.api').tree.open({ path = directory })
  tree_window = vim.api.nvim_get_current_win()
  step(function()
    search(function(prompt_buffer)
      require('telescope.actions').close(prompt_buffer)
      assert(vim.api.nvim_get_current_win() == tree_window, 'Cancelling search did not restore tree focus')
      step(function()
        search(function(selection_buffer)
          select(selection_buffer)
          assert(vim.wo.number and vim.wo.relativenumber, 'Tree search lost editor line numbers')
          assert(vim.api.nvim_get_current_win() == editor_window, 'Search did not reuse the editor')
          step(check_editor_preferences)
        end)
      end)
    end)
  end)
end)
vim.defer_fn(function() finish('File-tree navigation test timed out') end, 10000)
