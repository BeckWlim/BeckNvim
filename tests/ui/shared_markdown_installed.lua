-- Real input through two views of one Markdown source, including copied previews.
-- nvim --headless -u NONE -i NONE -l tests/ui/shared_markdown_installed.lua
local root = vim.fn.tempname()
local project = root .. '/project'
vim.fn.mkdir(project .. '/.git', 'p')
vim.fn.writefile({ '# Shared file', '', '| Link | Details |', '|---|---|',
  '| [Target](target.txt#L2) | ' .. string.rep('wrapped content ', 40) .. ' |', '',
  '[Target](target.txt#L2)',
}, project .. '/shared.md')
vim.fn.writefile({ 'target', 'anchor' }, project .. '/target.txt')
local init_path = root .. '/init.lua'
vim.fn.writefile({
  ('vim.opt.runtimepath:prepend(%q)'):format(vim.fn.getcwd()),
  [[local lazy = vim.fn.stdpath('data') .. '/lazy/']],
  [[for _, plugin in ipairs({ 'nvim-treesitter', 'telescope.nvim', 'plenary.nvim', 'telescope-ui-select.nvim', 'nvim-web-devicons' }) do vim.opt.runtimepath:append(lazy .. plugin) end]],
  [[dofile('tests/markdown_runtime.lua')]],
  [[require('config.startup.options')]],
  [[require('config.ui.window_state').setup()]],
  [[require('config.ui.float').setup()]],
  [[require('config.navigation.write_guard').setup()]],
  [[require('config.startup.autocmds').setup()]],
  [[require('config.startup.keybindings').setup()]],
  [[require('config.search.telescope').setup()]],
  [[require('render-markdown').setup({ preview = { enabled = true } })]],
}, init_path)
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', vim.env.NVIM_TEST_INIT or init_path, '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = root .. '/cache', XDG_STATE_HOME = root .. '/state',
    NVIM_LOG_FILE = root .. '/nvim.log' },
})
local function evaluate(source, ...)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected blocking editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { project, ... })
end
local function wait_for(source, message)
  assert(vim.wait(3000, function() return evaluate(source) end, 20), message)
end
local function fixture(command)
  evaluate([[
    vim.cmd.tabnew((...) .. '/shared.md')
    _G.first = vim.api.nvim_get_current_win()
    if not vim.b.markdown_preview_source then
      vim.b.markdown_preview_disabled = false
      require('render-markdown').preview()
    end
  ]])
  wait_for([[return vim.b.markdown_preview_source ~= nil]], 'First Markdown preview did not open')
  evaluate([[
    local _, command = ...
    _G.source = vim.b.markdown_preview_source
    vim.cmd(command)
    _G.second = vim.api.nvim_get_current_win()
  ]], command)
  wait_for([[
    local renderer = require('render-markdown')
    return renderer.source_location(first) == source and renderer.source_location(second) == source
  ]], 'Splitting Markdown lost the new window source mapping')
  evaluate([[
    assert(vim.api.nvim_win_get_buf(first) ~= vim.api.nvim_win_get_buf(second),
      'Different-width panes share one generated projection')
    _G.layout = vim.fn.winlayout()
    assert(require('config.project').for_buffer(vim.api.nvim_win_get_buf(first)) == (...),
      'Rendered file search scope uses the preview name instead of its source project')
    _G.sizes = {}
    for _, window in ipairs({ first, second }) do
      sizes[window] = { vim.api.nvim_win_get_width(window), vim.api.nvim_win_get_height(window) }
    end
    local renderer = require('render-markdown')
    vim.api.nvim_win_set_cursor(first, assert(renderer.display_position(first, { 7, 2 })))
    vim.api.nvim_win_set_cursor(second, assert(renderer.display_position(second, { 5, 4 })))
    local _, first_position = renderer.source_location(first)
    local _, second_position = renderer.source_location(second)
    assert(first_position[1] == 7 and second_position[1] == 5, 'Source cursors are shared across panes')
  ]])
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 160, 50, { rgb = true })
  if vim.env.NVIM_TEST_INIT then
    wait_for([[return vim.bo.filetype == 'dashboard']], 'Startup dashboard did not open')
  end
  for _, command in ipairs({ 'vsplit', 'split', 'vsplit ' .. project .. '/shared.md' }) do
    for _, destination in ipairs({ 'first', 'second' }) do
      fixture(command)
      evaluate([[vim.api.nvim_set_current_win(second)]])
      vim.rpcrequest(child, 'nvim_input', 'gx')
      wait_for([[return vim.bo.filetype == 'FilePanePicker']], 'Shared Markdown gx did not offer destination windows')
      local letter = evaluate([[
        local _, destination = ...
        local index = 0
        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_get_config(window).relative == '' then
            index = index + 1
            if window == _G[destination] then return string.char(96 + index) end
          end
        end
      ]], destination)
      vim.rpcrequest(child, 'nvim_input', letter)
      wait_for([[return vim.api.nvim_buf_get_name(0) == (...) .. '/target.txt']], 'Shared Markdown gx failed to replace its chosen pane')
      evaluate([[
        local _, destination = ...
        local target = _G[destination]
        local sibling = destination == 'first' and second or first
        assert(vim.api.nvim_get_current_win() == target and vim.fn.line('.') == 2,
          'gx lost the chosen window or line anchor')
        assert(require('render-markdown').source_location(sibling) == source,
          'gx retired the other Markdown view')
        assert(vim.deep_equal(vim.fn.winlayout(), layout), 'gx changed the split combination')
        for window, size in pairs(sizes) do
          assert(vim.api.nvim_win_get_width(window) == size[1]
            and vim.api.nvim_win_get_height(window) == size[2], 'gx resized a split')
        end
      ]], destination)
      vim.rpcrequest(child, 'nvim_input', ' o')
      wait_for([[return vim.b.markdown_preview_source == source]], 'gx back navigation lost the shared preview')
      evaluate([[vim.cmd.tabclose()]])
    end
    for _, closing in ipairs({ 'first', 'second' }) do
      for _, quit in ipairs({ 'q', 'wq' }) do
        fixture(command)
        evaluate([[local _, closing = ...; vim.api.nvim_set_current_win(_G[closing])]], closing)
        vim.rpcrequest(child, 'nvim_input', ':' .. quit .. '<CR>')
        assert(vim.wait(3000, function()
          return evaluate([[local _, closing = ...; return not vim.api.nvim_win_is_valid(_G[closing])]], closing)
        end, 20), 'Quit did not close the focused Markdown window')
        evaluate([[
          local _, closing = ...
          local sibling = closing == 'first' and second or first
          assert(vim.api.nvim_win_is_valid(sibling), 'Quit closed both views of the Markdown file')
          assert(vim.deep_equal(vim.fn.winlayout(), { 'leaf', sibling }), 'Quit changed another window')
          assert(require('render-markdown').source_location(sibling) == source,
            'Quit retired the surviving Markdown view')
          vim.cmd.tabclose()
        ]], closing)
      end
    end
  end
  local sample = vim.env.NVIM_TEST_MARKDOWN_SAMPLE
  if sample then
    evaluate([[
      local _, sample = ...
      vim.cmd.tabnew(sample)
      _G.first = vim.api.nvim_get_current_win()
      _G.sample_path = sample
    ]], sample)
    wait_for([[return vim.b.markdown_preview_source ~= nil]], 'Sample Markdown preview did not open')
    evaluate([[
      _G.source = vim.b.markdown_preview_source
      vim.cmd.vsplit()
      _G.second = vim.api.nvim_get_current_win()
    ]])
    wait_for([[return require('render-markdown').source_location(second) == source]],
      'Sample split lost its source mapping')
    evaluate([[
      local lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
      for row, line in ipairs(lines) do
        local column = line:find('[README]', 1, true)
        if column then
          vim.api.nvim_win_set_cursor(second,
            assert(require('render-markdown').display_position(second, { row, column })))
          return
        end
      end
      error('Sample has no README link')
    ]])
    vim.rpcrequest(child, 'nvim_input', 'gx')
    wait_for([[return vim.bo.filetype == 'FilePanePicker']], 'Sample gx did not offer its shared windows')
    local letter = evaluate([[
      local index = 0
      for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(window).relative == '' then
          index = index + 1
          if window == second then return string.char(96 + index) end
        end
      end
    ]])
    vim.rpcrequest(child, 'nvim_input', letter)
    wait_for([[
      local buffer = require('config.ui.window_state').file_buffer(second)
      return vim.api.nvim_buf_get_name(buffer) == vim.fs.dirname(vim.fs.dirname(sample_path)) .. '/README.md'
    ]], 'Sample gx did not resolve the source-relative README')
    vim.rpcrequest(child, 'nvim_input', ':q<CR>')
    wait_for([[return not vim.api.nvim_win_is_valid(second)]], 'Sample quit did not close the chosen window')
    evaluate([[
      assert(vim.api.nvim_win_is_valid(first) and require('render-markdown').source_location(first) == source,
        'Sample navigation or quit retired the original window')
      vim.cmd.tabclose()
    ]])
  end
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, 'rf')
assert(passed, failure)
print('Shared Markdown windows: gx destination/history and focused :q/:wq preserve the sibling view')
