-- UI-ready lazy loading + Flash text jumps + preview highlighter restarts.
-- Run separately: nvim --headless -u NONE -i NONE -l tests/search/flash_markdown_labels_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.fn.system({ 'git', 'init', '-q', directory })
assert(vim.v.shell_error == 0, 'Could not create the disposable Markdown project')
local child = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n',
  '-u', vim.env.NVIM_TEST_INIT or 'init.lua', '-i', 'NONE' }, { rpc = true })
local function evaluate(code, args)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, args or {})
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
end
local function wait_for(code, message, args)
  assert(vim.wait(2500, function() return evaluate(code, args) == true end, 10), message)
end
local function labels_visible()
  return evaluate([[
    if vim.b.markdown_preview_source ~= vim.g.flash_label_source then return false end
    vim.cmd('redraw!')
    for _, item in ipairs({ { 3, 'text' }, { 9, 'lua' } }) do
      local row = require('render-markdown').display_position(0, { item[1], 0 })[1]
      local position = vim.fn.screenpos(0, row, 1)
      if position.row == 0 then return false end
      local text = ''
      for column = 1, 100 do text = text .. vim.fn.screenstring(position.row, column) end
      if not text:find(item[2], 1, true) then return false end
    end
    return true
  ]]) == true
end
local function check_labels(message)
  assert(vim.wait(2500, labels_visible, 10), message)
end
local function edit(keys)
  local tick = evaluate([[return vim.api.nvim_buf_get_changedtick(vim.g.flash_label_source)]])
  input(keys or 'iEdited <Esc>')
  wait_for([[return vim.api.nvim_get_current_buf() == vim.g.flash_label_source and vim.fn.mode() == 'n']],
    'Native edit did not stay in source')
  input(' mp')
  wait_for([[
    return vim.b.markdown_preview_source == vim.g.flash_label_source
      and vim.fn.mode() == 'n'
      and vim.api.nvim_buf_get_changedtick(vim.g.flash_label_source) > ...
  ]], 'Manual render did not reopen its preview', { tick })
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 30, { rgb = true })
  wait_for([[return require('lazy.core.config').plugins['flash.nvim']._.loaded ~= nil]],
    'UI readiness did not load Flash')
  evaluate([[
    vim.cmd('enew!')
    assert(vim.api.nvim_buf_get_name(0) == '', 'Flash fixture should start in an unnamed buffer')
    for _, mode in ipairs({ 'n', 'x', 'o' }) do
      for _, key in ipairs({ '<Space>s', '<Space>fn' }) do
        assert(vim.fn.maparg(key, mode, false, true).callback,
          'UI readiness did not register Flash shortcuts in an unnamed buffer')
      end
    end
    vim.cmd.edit(vim.fn.fnameescape(... .. '/labels.md'))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# Flash labels', '', '```text', 'payload', '```', '',
      'needle target ordinary prose', '', '```lua', 'local value = 1', '```', '',
      '```mermaid', 'graph LR', 'A[Input] --> B[Output]', '```', '', 'end',
    })
    vim.g.flash_label_source = vim.api.nvim_get_current_buf()
    vim.bo.filetype = 'markdown'
  ]], { directory })
  wait_for([[return vim.b.markdown_preview_source == vim.g.flash_label_source]],
    'Fixture did not open its Markdown preview')
  check_labels('Initial code language labels are not visible')

  -- Native search is the control: it does not activate Flash search integration.
  input('/needle<CR>')
  wait_for([[
    local _, position = require('render-markdown').source_location()
    return position[1] == 7 and vim.fn.mode() == 'n'
  ]], 'Native search did not reach the prose target')
  edit('iNative <Esc>')
  check_labels('Native search/edit lost language labels')
  evaluate([[
    assert(require('flash.plugins.search').state == nil, 'Flash took over native search')
  ]])

  for iteration = 1, 3 do
    evaluate([[vim.api.nvim_win_set_cursor(0, { 1, 0 }); vim.cmd('normal! zt')]])
    input(' sneedle')
    wait_for([[
      local state = require('flash.repeat')._states.jump
      return state ~= nil and state.visible and #state.results > 0
    ]], 'Flash text jump did not activate')
    local label = evaluate([[
      local row = require('render-markdown').display_position(0, { 7, 0 })[1]
      for _, match in ipairs(require('flash.repeat')._states.jump.results) do
        if match.pos[1] == row then return assert(match.label) end
      end
      error('Flash did not label the prose target')
    ]])
    input(label)
    wait_for([[return not require('flash.repeat')._states.jump.visible]],
      'Flash label selection did not complete')
    edit()
    check_labels('Flash jump/edit hid the ordinary code language labels')
    evaluate([[
      assert(vim.bo[vim.g.flash_label_source].modified and vim.bo.modified,
        'Flash edit lost its unsaved state')
    ]])
    if iteration == 2 then
      input(':write<CR>')
      wait_for([[return not vim.bo[vim.g.flash_label_source].modified]],
        'Saving the Flash edit did not save its source')
      check_labels('Saving a Flash edit hid code language labels')
      evaluate([[
        local source = vim.g.flash_label_source
        assert(vim.deep_equal(vim.fn.readfile(vim.api.nvim_buf_get_name(source)),
          vim.api.nvim_buf_get_lines(source, 0, -1, false)), 'Preview save wrote generated rows')
      ]])
    end
    input(' mp')
    wait_for([[return vim.api.nvim_get_current_buf() == vim.g.flash_label_source]],
      'Toggle did not restore the source after a Flash edit')
    input(' mp')
    wait_for([[return vim.b.markdown_preview_source == vim.g.flash_label_source]],
      'Toggle did not reopen the edited preview')
    check_labels('Toggling after a Flash edit hid code labels')
  end
  -- A later plugin load must be handled too, while Flash remains loaded.
  evaluate([[
    vim.fn.mkdir(... .. '/late-plugin/queries/markdown', 'p')
    vim.fn.writefile({ '; extends', '; late plugin query extension' },
      ... .. '/late-plugin/queries/markdown/highlights.scm')
    local previous = vim.treesitter.query.get('markdown', 'highlights')
    vim.opt.runtimepath:append(... .. '/late-plugin')
    assert(vim.treesitter.query.get('markdown', 'highlights') ~= previous,
      'Later runtime-path change did not replace the query')
    vim.api.nvim_win_set_cursor(0, require('render-markdown').display_position(0, { 7, 0 }))
  ]], { directory })
  edit()
  check_labels('Later query replacement hid labels after editing')
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Flash UI-ready loading, unsaved/saved labels, native search, and query replacement passed')
