-- Real Flash + projected renderer + host keybindings; no browser handoff.
-- NVIM_TEST_RENDER_MARKDOWN selects a development checkout before linkage.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local renderer_path = vim.env.NVIM_TEST_RENDER_MARKDOWN
if not renderer_path then
  local dev = require('config.user').get().dev or {}
  local selected = false
  for _, pattern in ipairs(dev.enabled == true and dev.patterns or {}) do
    if ('BeckWlim/render-markdown.nvim'):find(pattern, 1, true) then selected = true end
  end
  local parent = selected and vim.fn.expand(dev.path or '~/.config')
    or vim.fn.stdpath('data') .. '/lazy'
  renderer_path = parent .. '/render-markdown.nvim'
end
local flash_path = vim.fn.stdpath('data') .. '/lazy/flash.nvim'
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local child = vim.fn.jobstart({ vim.v.progpath, '--headless', '--embed', '-n', '-u', 'NONE', '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = directory, XDG_STATE_HOME = directory },
})
local function evaluate(code, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, arguments or {})
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
  vim.wait(30)
end
local function wait_for(code, message)
  assert(vim.wait(2500, function() return evaluate(code) end, 10), message)
end
local function label_at(row)
  return evaluate([=[
    local row = ...
    for _, match in ipairs(require('flash.repeat')._states.jump.results) do
      if match.pos[1] == row then return assert(match.label) end
    end
    error('No visible match at row ' .. row)
  ]=], { row })
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 100, 30, { rgb = true })
  evaluate([=[
    local root, renderer, flash, directory = ...
    vim.opt.runtimepath:prepend(root)
    vim.opt.runtimepath:prepend(renderer)
    vim.opt.runtimepath:append(renderer .. '/after')
    vim.opt.runtimepath:append(flash)
    require('config.startup.options')
    require('config.syntax.highlights').setup()
    for _, spec in ipairs(dofile(root .. '/lua/plugins/coding.lua')) do
      if spec[1] == 'folke/flash.nvim' then
        spec.config(nil, spec.opts)
      end
    end
    require('config.startup.keybindings').setup()
    local renderer_options
    for _, spec in ipairs(dofile(root .. '/lua/plugins/extra.lua')) do
      if spec[1] == 'BeckWlim/render-markdown.nvim' then renderer_options = vim.deepcopy(spec.opts) end
    end
    renderer_options.preview.auto_open = false
    renderer_options.preview.mermaid = { enabled = false }
    require('render-markdown').setup(renderer_options)
    require('render-markdown.core.colors').init()
    require('render-markdown.core.manager').init()
    local source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, {
      '# Navigation', '',
      'alpha [github](https://example.com/a_(b)) omega', '',
      '| Name | Description |', '|---|---|',
      '| needle | ' .. string.rep('wrapped content ', 15) .. '|', '',
      'needle target', '', 'needle other',
    })
    vim.bo.filetype = 'markdown'
    vim.api.nvim_buf_set_name(source, directory .. '/navigation.md')
    vim.g.test_source = source
    vim.g.test_display = require('render-markdown.preview').open(source)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd('normal! zt')
    vim.cmd('redraw')
    vim.g.test_view = vim.fn.winsaveview()
    vim.g.test_tick = vim.api.nvim_buf_get_changedtick(source)
  ]=], { root, renderer_path, flash_path, directory })
  input(' sneedle')
  wait_for([=[
    local state = require('flash.repeat')._states.jump
    return state and state.visible and #state.results == 3
  ]=], 'Rendered text jump did not activate')
  local target = evaluate([=[return require('render-markdown').display_position(0, { 9, 0 })[1]]=])
  evaluate([=[
    local state = require('flash.repeat')._states.jump
    assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.test_view), 'Flash moved viewport while typing')
    for _, match in ipairs(state.results) do
      assert(match.label and match.label:match('^[a-z]$'), 'Rendered Flash label is uppercase or missing')
    end
  ]=])
  input(label_at(target))
  wait_for([=[local row = ...; return vim.api.nvim_win_get_cursor(0)[1] > 7]=], 'Rendered label did not jump')
  evaluate([=[
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Jump lost projection')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd('normal! zt')
    vim.g.test_view = vim.fn.winsaveview()
  ]=])
  input(' sneedle<C-q>')
  wait_for([=[return not require('flash.repeat')._states.jump.visible]=], 'Rendered jump did not cancel')
  evaluate([=[assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.test_view), 'Cancel lost rendered view')]=])
  input(' sgithub')
  wait_for([=[return require('flash.repeat')._states.jump.visible]=], 'Direct preview jump did not activate')
  input(label_at(3))
  evaluate([=[
    local source, position = require('render-markdown').source_location()
    assert(source == vim.g.test_source and vim.deep_equal(position, { 3, 7 }),
      'Direct Flash jump lost its source position')
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Text jump entered source')
  ]=])
  -- Source Markdown nodes, including the entire hidden link destination.
  evaluate([=[vim.api.nvim_win_set_cursor(0, { 3, 9 })]=])
  input(' fn')
  wait_for([=[
    local state = require('flash.repeat')._states.treesitter
    return state and state.visible and #state.results > 0
      and vim.api.nvim_get_current_buf() == vim.g.test_source
  ]=], 'Source syntax selection did not activate')
  local syntax_label = evaluate([=[
    for _, match in ipairs(require('flash.repeat')._states.treesitter.results) do
      if match.node:type() == 'inline_link' then
        assert(match.pos[2] == 6 and match.end_pos[2] > 12, 'Source selection lost the link destination')
        return assert(match.label)
      end
    end
    error('Original Markdown link node is missing')
  ]=])
  input(syntax_label)
  wait_for([=[return vim.api.nvim_get_mode().mode == 'v'
    and vim.api.nvim_get_current_buf() == vim.g.test_source]=], 'Syntax label did not select source range')
  input('"ay')
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_source and vim.fn.mode() == 'n']=],
    'Source selection did not remain in source')
  input(' mp')
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Manual render after syntax selection failed')
  evaluate([=[
    assert(vim.fn.getreg('a') == '[github](https://example.com/a_(b))', 'Yank lost original link syntax')
    assert(vim.api.nvim_buf_get_changedtick(vim.g.test_source) == vim.g.test_tick, 'Read-only actions changed source')
  ]=])
  evaluate([=[vim.api.nvim_win_set_cursor(0, { 3, 9 })]=])
  input('"ay fn')
  wait_for([=[
    local state = require('flash.repeat')._states.treesitter
    return state and state.visible and vim.api.nvim_get_current_buf() == vim.g.test_source
  ]=], 'Rendered syntax operator did not enter the native source context')
  local operator_label = evaluate([=[
    for _, match in ipairs(require('flash.repeat')._states.treesitter.results) do
      if match.node:type() == 'inline_link' then return assert(match.label) end
    end
    error('Native source link node missing')
  ]=])
  input(operator_label)
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_source and vim.fn.mode() == 'n']=],
    'Source selection did not remain in source')
  input(' mp')
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Manual render after syntax selection failed')
  evaluate([=[assert(vim.fn.getreg('a') == '[github](https://example.com/a_(b))', 'Syntax operator did not yank source')]=])
  -- Real host link opening uses the source adapter and leaves cursor/view intact.
  evaluate([=[
    vim.api.nvim_win_set_cursor(0, { 3, 9 })
    local before = vim.fn.winsaveview()
    local captured
    vim.ui.open = function(url) captured = url; return {} end
    package.loaded['config.git.issue'] = { open_url = function() return false end }
    require('config.ui.open_target').open_at_cursor()
    assert(captured == 'https://example.com/a_(b)', 'Host opener truncated nested URL')
    assert(vim.deep_equal(before, vim.fn.winsaveview()), 'Link handoff moved cursor/view')
  ]=])
  -- Selecting a source table uses source byte ranges despite wrapped display rows.
  evaluate([=[
    local destination = require('render-markdown').display_position(0, { 7, 12 })
    vim.api.nvim_win_set_cursor(0, destination)
  ]=])
  input(' fn')
  wait_for([=[return require('flash.repeat')._states.treesitter.visible
    and vim.api.nvim_get_current_buf() == vim.g.test_source]=], 'Wrapped table source syntax prompt failed')
  local table_label = evaluate([=[
    for _, match in ipairs(require('flash.repeat')._states.treesitter.results) do
      if match.node:type() == 'pipe_table' then return assert(match.label) end
    end
    error('Syntax matcher parsed rendered table instead of source')
  ]=])
  input(table_label)
  wait_for([=[return vim.fn.mode() == 'v']=], 'Source table node did not select')
  input('"ay')
  wait_for([=[return vim.fn.mode() == 'n' and vim.api.nvim_get_current_buf() == vim.g.test_source]=],
    'Source selection did not remain in source')
  input(' mp')
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Manual render after syntax selection failed')
  evaluate([=[
    local text = vim.fn.getreg('a')
    assert(text:find('| Name | Description |', 1, true) and text:find('|---|---|', 1, true),
      'Source table selection yanked manufactured rows')
  ]=])
  evaluate([=[
    local renderer = require('render-markdown')
    vim.api.nvim_win_set_cursor(0, renderer.display_position(0, { 7, 12 }))
    require('config.syntax.treesitter_context').go_to_nearest_context()
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display
      and vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }),
      'Tree-sitter context navigation lost the preview heading')
    assert(vim.api.nvim_buf_get_changedtick(vim.g.test_source) == vim.g.test_tick,
      'Source syntax/context actions changed Markdown')
    assert(vim.fn.maparg('<Space>mp', 'n', false, true).buffer == 0,
      'Renderer shadowed BeckNvim preview shortcut')
  ]=])
  -- Native search never enters source, including while the command line is active.
  evaluate([=[
    vim.g.test_source_entries = 0
    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = vim.g.test_source,
      callback = function() vim.g.test_source_entries = vim.g.test_source_entries + 1 end,
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]=])
  input('/needle')
  wait_for([=[return vim.fn.getcmdtype() == '/' and vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Native search did not keep the Markdown preview open during input')
  evaluate([=[assert(require('flash.plugins.search').state == nil, 'Flash labelled native Markdown search')]=])
  input('<CR>')
  evaluate([=[
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Accepted search left preview')
    assert(require('render-markdown').interaction().position[1] == 7, 'Search missed generated table text')
    assert(vim.fn.getreg('/') == 'needle', 'Native search pattern was changed')
  ]=])
  input('n')
  evaluate([=[assert(require('render-markdown').interaction().position[1] == 9, 'Preview repeat missed the next match')]=])
  input('N')
  evaluate([=[
    assert(require('render-markdown').interaction().position[1] == 7, 'Reverse repeat missed the table match')
    vim.g.test_search_view = vim.fn.winsaveview()
  ]=])
  input('/omega<Esc>')
  evaluate([=[
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Cancelled search left preview')
    assert(vim.deep_equal(vim.fn.winsaveview(), vim.g.test_search_view), 'Search cancellation lost the display view')
  ]=])
  -- A generated border exists only in the preview: source routing cannot find it.
  evaluate([=[vim.api.nvim_win_set_cursor(0, { 1, 0 })]=])
  input('/─<CR>')
  evaluate([=[
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    assert(line:sub(cursor[2] + 1, cursor[2] + #'─') == '─',
      'Search missed the generated table border')
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Generated text search left preview')
    assert(vim.g.test_source_entries == 0, 'Search temporarily entered source')
    assert(vim.api.nvim_buf_get_changedtick(vim.g.test_source) == vim.g.test_tick, 'Search modified Markdown source')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local count = vim.api.nvim_buf_line_count(vim.g.test_source)
    local extra = {}
    for index = 1, 70 do extra[index] = 'filler ' .. index end
    extra[70] = 'wholefile_target'
    vim.api.nvim_buf_set_lines(vim.g.test_source, count, count, false, extra)
    require('render-markdown.preview').refresh(vim.g.test_source)
    vim.g.test_distant_row = require('render-markdown').display_position(0, { count + 70, 0 })[1]
  ]=])
  input('/wholefile_target')
  wait_for([=[return vim.fn.getcmdtype() == '/' and vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Off-screen search input left preview')
  input('<CR>')
  wait_for([=[
    return vim.api.nvim_get_current_buf() == vim.g.test_display
      and vim.api.nvim_win_get_cursor(0)[1] == vim.g.test_distant_row
  ]=], 'Native Markdown search could not reach an off-screen preview match')
  input('?github')
  wait_for([=[return vim.fn.getcmdtype() == '?' and vim.api.nvim_get_current_buf() == vim.g.test_display]=],
    'Backward search input left preview')
  input('<CR>')
  evaluate([=[
    assert(vim.api.nvim_get_current_buf() == vim.g.test_display, 'Backward search left preview')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 7 }), 'Backward preview search missed the label')
    assert(vim.g.test_source_entries == 0, 'Native preview search switched to source')
  ]=])
  input(' mp')
  wait_for([=[return vim.api.nvim_get_current_buf() == vim.g.test_source]=], 'Host toggle did not restore source')
  input(' mp')
  wait_for([=[return vim.b.markdown_preview_source == vim.g.test_source]=], 'Host toggle did not reopen rendered view')
  -- Returning through native history may leave the underlying source unlisted.
  evaluate([=[vim.bo[vim.g.test_source].buflisted = false]=])
  for iteration = 1, 50 do
    input('iX<Esc> sneedle<Esc>')
    wait_for([=[return vim.fn.mode() == 'n' and vim.api.nvim_get_current_buf() == vim.g.test_source]=],
      'Rapid edit/Flash reopened preview at iteration ' .. iteration)
    input(' mp')
    wait_for([=[return vim.b.markdown_preview_source == vim.g.test_source]=],
      'Manual render failed after rapid edit/Flash at iteration ' .. iteration)
    input(' sneedle<Esc>')
    wait_for([=[return vim.b.markdown_preview_source == vim.g.test_source and vim.fn.mode() == 'n']=],
      'Flash text jump left preview at iteration ' .. iteration)
  end
end
local succeeded, failure = xpcall(check, debug.traceback)
pcall(vim.fn.jobstop, child)
vim.fn.delete(directory, 'rf')
assert(succeeded, failure)
print('Installed Flash projected-Markdown integration tests passed')
