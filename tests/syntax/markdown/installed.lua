-- Run separately with installed plugins and Termaid:
-- nvim --headless -u NONE -i NONE -l tests/syntax/markdown/installed.lua
local project_directory = vim.fn.tempname()
vim.fn.mkdir(project_directory .. '/.git', 'p')
vim.fn.mkdir(project_directory .. '/docs/production', 'p')
vim.fn.writefile({ '# Replicas', 'Replica details' }, project_directory .. '/docs/production/replicas.md')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true })
local function evaluate(source)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, {})
end
local function check()
  evaluate([[
    local highlights = assert(vim.treesitter.query.get('markdown', 'highlights'))
    assert(vim.list_contains(highlights.captures, 'markup.table.markdown'),
      'Relocated Markdown table query was not loaded during startup')
    assert(vim.list_contains(highlights.captures, 'markup.heading'),
      'Custom Markdown query replaced the standard highlights')
    local plugin = assert(require('lazy.core.config').plugins.termaid, 'Termaid is not managed by lazy.nvim')
    assert(require('config.syntax.mermaid').find_executable() == plugin.dir .. '/.venv/bin/termaid',
      'Markdown renderer is not using the managed Termaid build')
  ]])
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 36, { rgb = true })
  evaluate([[vim.api.nvim__inspect_cell(1, 0, 0)]])
  vim.rpcrequest(child, 'nvim_set_var', 'preview_test_project', project_directory)
  evaluate([[
    vim.cmd('enew!')
    vim.api.nvim_buf_set_name(0, vim.g.preview_test_project .. '/navigation-origin.lua')
    vim.g.preview_jump_origin = vim.api.nvim_get_current_buf()
    vim.cmd('clearjumps')
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# Markdown preview', '', '[Visible link](https://example.com/prose) and [Replica support](replicas.md#L2)', '- List item', '',
      string.rep('Ordinary prose wraps independently. ', 5), '',
      '| Key | Description |', '| --- | --- |',
      '| Enter | **literal cell** ' .. string.rep('long cell content ', 100) .. '|', '',
      '```mermaid', 'graph LR', '  A[Source] -->|render| B[Preview]', '```', '',
      'Source navigation remains native.',
    })
    vim.g.preview_test_source = vim.api.nvim_get_current_buf()
    vim.g.preview_test_window = vim.api.nvim_get_current_win()
    vim.g.preview_test_windows = #vim.api.nvim_list_wins()
    vim.api.nvim_buf_set_name(0, vim.g.preview_test_project .. '/docs/production/report.md')
    vim.bo.filetype = 'markdown'
  ]])
  assert(vim.wait(10000, function()
    return evaluate([[
      local source = vim.b.markdown_preview_source
      local blocks = source and require('config.syntax.mermaid').stage(source) or {}
      return #blocks > 0 and not blocks[1].pending
        and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('󰙅 mermaid', 1, true) ~= nil
    ]])
  end, 100), 'Real Mermaid render did not complete')
  assert(evaluate([[return require('lazy.core.config').plugins.termaid._.loaded ~= nil]]),
    'Markdown rendering left its Termaid dependency unloaded in lazy.nvim')
  evaluate([[
    local rendered = vim.api.nvim_get_current_buf()
    local position = { 1, 4 }
    vim.api.nvim_win_set_cursor(0, position)
    for _ = 1, 3 do
      vim.api.nvim_feedkeys(vim.keycode('<Space>o'), 'xt', false)
      vim.wait(50)
      assert(vim.api.nvim_get_current_buf() == vim.g.preview_jump_origin,
        'Space o bounced back into rendered Markdown')
      vim.api.nvim_feedkeys(vim.keycode('<Space>p'), 'xt', false)
      vim.wait(50)
      assert(vim.api.nvim_get_current_buf() == rendered
        and vim.deep_equal(vim.api.nvim_win_get_cursor(0), position),
        'Space p lost its rendered Markdown destination')
    end
    assert(vim.wo.foldmethod == 'manual' and vim.wo.conceallevel == 3,
      'Jumping forward did not restore the rendered window options')
  ]])
  vim.wait(100)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Preview opened a blocking prompt')
  -- Use real input and inspect the screen: command mode alone does not prove
  -- that the prompt is visible while Markdown conceals the cursor's link.
  for _, column in ipairs({ 2, 20, 47, 70 }) do
    vim.rpcrequest(child, 'nvim_win_set_cursor', 0, { 3, column })
    vim.rpcnotify(child, 'nvim_input', ':')
    assert(vim.wait(1000, function()
      return vim.rpcrequest(child, 'nvim_get_mode').mode == 'c'
        and evaluate([[return vim.fn.screenstring(vim.o.lines, 1) == ':']])
    end, 20), 'Colon prompt is not visible with the cursor on a rendered link')
    vim.rpcnotify(child, 'nvim_input', 'let g:preview_command_entered = 1<CR>')
    assert(vim.wait(1000, function()
      return evaluate([[return vim.g.preview_command_entered == 1]])
    end, 20), 'Command input stalled on a rendered link')
    evaluate([[vim.g.preview_command_entered = nil]])
  end
  evaluate([[
    local rendered = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 3, 47 })
    local position = vim.api.nvim_win_get_cursor(0)
    local original_confirm = vim.fn.confirm
    vim.fn.confirm = function() return 1 end
    vim.api.nvim_feedkeys('gx', 'xt', false)
    vim.fn.confirm = original_confirm
    vim.g.preview_link_origin = rendered
    vim.g.preview_link_position = position
  ]])
  assert(vim.wait(1000, function()
    return evaluate([[
      local source = vim.b.markdown_preview_source
      return source and vim.api.nvim_buf_get_name(source) == vim.g.preview_test_project .. '/docs/production/replicas.md'
    ]])
  end, 20), 'Installed gx did not open the source-relative Markdown link')
  evaluate([[
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'Installed gx lost its line anchor')
    vim.api.nvim_feedkeys(vim.keycode('<Space>o'), 'xt', false)
  ]])
  assert(vim.wait(1000, function()
    return evaluate([[return vim.api.nvim_get_current_buf() == vim.g.preview_link_origin]])
  end, 20), 'Returning from gx did not restore the rendered source')
  evaluate([[
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), vim.g.preview_link_position),
      'Returning from gx lost the link cursor position')
  ]])
  evaluate([[
    vim.cmd('redraw!')
    local buffer = vim.api.nvim_get_current_buf()
    local source = vim.g.preview_test_source
    local renderer_namespace = vim.api.nvim_get_namespaces()['render-markdown.nvim']
    local renderer_marks = vim.api.nvim_buf_get_extmarks(buffer, renderer_namespace, 0, -1, { details = true })
    local heading_rendered, link_rendered, bullet_rendered = false, false, false
    for _, mark in ipairs(renderer_marks) do
      if mark[2] == 0 and mark[4].hl_group == 'RenderMarkdownH1Bg' then heading_rendered = true end
      if mark[2] == 2 and mark[4].virt_text then link_rendered = true end
      if mark[2] == 3 and mark[4].virt_text then bullet_rendered = true end
    end
    assert(heading_rendered and link_rendered and bullet_rendered,
      'Preview prose is still raw: ' .. vim.inspect(renderer_marks))
    local link_position = vim.fn.screenpos(0, 3, 1)
    local link_cells = {}
    for column = 1, 120 do link_cells[column] = vim.fn.screenstring(link_position.row, column) end
    local displayed_link = table.concat(link_cells)
    assert(displayed_link:find('Visible link', 1, true) and not displayed_link:find('https://', 1, true),
      'Rendered prose still displays a raw link destination: ' .. displayed_link)
    assert(vim.wo.conceallevel == 3 and vim.wo.concealcursor == 'nvic', 'Preview reveals syntax under cursor')
    assert(not require('render-markdown.core.manager').attached(source), 'Editable source is rendered')
    assert(vim.api.nvim_get_current_win() == vim.g.preview_test_window
      and #vim.api.nvim_list_wins() == vim.g.preview_test_windows, 'Rendering changed the pane layout')
    assert(vim.wo.foldmethod == 'manual', 'Generated rows still invoke source folding')
    assert(vim.wo.winbar == '', 'Shortcut banner still occupies a preview row')
    assert(vim.wo.number, 'Markdown preview hid the editor line numbers')
    local statusline = require('config.ui.statusline')
    assert(statusline.project_name() == vim.fs.basename(vim.g.preview_test_project),
      'Preview footer follows the working directory instead of the source project')
    assert(statusline.project_relative_path() == 'docs/production/report.md [+]',
      'Preview footer lost the source path or unsaved changes')
    require('lualine').refresh({ force = true })
    local footer = vim.api.nvim_eval_statusline(vim.wo.statusline, { winid = vim.api.nvim_get_current_win() }).str
    assert(footer:find('docs/production/report.md', 1, true) and not footer:find('markdown-preview', 1, true),
      'Rendered footer does not identify the source file: ' .. footer)
    local feature_namespace = vim.api.nvim_get_namespaces().markdown_preview
    local feature_marks = vim.api.nvim_buf_get_extmarks(buffer, feature_namespace, 0, -1, { details = true })
    local checked = {}
    local connection_colors = {}
    for _, mark in ipairs(feature_marks) do
      local group = mark[4].hl_group
      if group == 'RenderMarkdownMermaidEdge' or group == 'RenderMarkdownMermaidArrow'
          or group == 'RenderMarkdownMermaidEdgeLabel' then
        connection_colors[group] = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
        if group == 'RenderMarkdownMermaidEdgeLabel' then
          local label_text = vim.api.nvim_buf_get_text(buffer, mark[2], mark[3],
            mark[4].end_row, mark[4].end_col, {})
          assert(table.concat(label_text):find('render', 1, true), 'Connection label lost its semantic span')
        end
      end
      local feature = group == 'RenderMarkdownTableCell' and 'table'
        or group == 'RenderMarkdownMermaidLabel' and 'mermaid' or nil
      if feature and not checked[feature] then
        local row, column = mark[2] + 1, mark[3]
        for _, prose_mark in ipairs(renderer_marks) do
          assert(prose_mark[2] ~= row - 1, 'Generated feature text was reinterpreted as prose')
        end
        vim.api.nvim_win_set_cursor(0, { row, column })
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buffer })
        vim.cmd('normal! zz')
        vim.cmd('redraw!')
        local position = vim.fn.screenpos(0, row, column + 1)
        local cell = vim.api.nvim__inspect_cell(1, position.row - 1, position.col - 1)
        assert(cell[2].background == vim.api.nvim_get_hl(0, { name = 'CursorLine' }).bg,
          feature .. ' background covers CursorLine')
        assert(cell[2].foreground == vim.api.nvim_get_hl(0, { name = group }).fg,
          'CursorLine erased ' .. feature .. ' semantic foreground')
        checked[feature] = true
      end
    end
    assert(checked.table and checked.mermaid, 'Missing semantic table or Mermaid rows')
    assert(connection_colors.RenderMarkdownMermaidEdge and connection_colors.RenderMarkdownMermaidArrow
      and connection_colors.RenderMarkdownMermaidEdgeLabel == vim.api.nvim_get_hl(0, { name = 'Normal' }).fg
      and connection_colors.RenderMarkdownMermaidEdgeLabel ~= connection_colors.RenderMarkdownMermaidEdge
      and connection_colors.RenderMarkdownMermaidEdgeLabel ~= connection_colors.RenderMarkdownMermaidArrow,
      'Rendered connection labels do not separate text from connector colors')
    local theme_buffer_tick = vim.api.nvim_buf_get_changedtick(buffer)
    local theme_cursor = vim.api.nvim_win_get_cursor(0)
    local theme_window = vim.api.nvim_get_current_win()
    for _, name in ipairs({ 'morning', 'monokai' }) do
      vim.api.nvim_cmd({ cmd = 'colorscheme', args = { name } }, {})
      vim.wait(30)
      assert(vim.api.nvim_get_current_buf() == buffer and vim.api.nvim_buf_get_changedtick(buffer) == theme_buffer_tick,
        'Theme switch rebuilt rendered Markdown content')
      assert(vim.deep_equal(theme_cursor, vim.api.nvim_win_get_cursor(0))
        and theme_window == vim.api.nvim_get_current_win(), 'Theme switch changed preview navigation')
      assert(vim.api.nvim_get_hl(0, { name = 'RenderMarkdownMermaidEdgeLabel' }).fg
        == vim.api.nvim_get_hl(0, { name = 'Normal' }).fg, 'Rendered Mermaid labels kept the old theme')
      local palette = require('config.ui.palette').resolve()
      local icon_colors = {
        RenderMarkdownTableIcon = palette.table.icon,
        RenderMarkdownTableLabel = palette.table.label,
        RenderMarkdownMermaidIcon = palette.mermaid.icon,
        RenderMarkdownMermaidLabel = palette.mermaid.label,
      }
      local checked_icons = {}
      for _, mark in ipairs(feature_marks) do
        local icon_color = icon_colors[mark[4].hl_group]
        if icon_color then
          local row, column = mark[2] + 1, mark[3]
          vim.api.nvim_win_set_cursor(0, { row, column })
          vim.cmd('normal! zz')
          vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
          vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buffer })
          vim.cmd('redraw!')
          local position = vim.fn.screenpos(0, row, column + 1)
          local cell = vim.api.nvim__inspect_cell(1, position.row - 1, position.col - 1)
          assert(cell[2].foreground == icon_color, 'Rendered icon lost its semantic accent')
          assert(cell[2].background == palette.block, 'Rendered icon left the filled header')
          checked_icons[mark[4].hl_group] = true
        end
      end
      assert(checked_icons.RenderMarkdownTableIcon and checked_icons.RenderMarkdownTableLabel
          and checked_icons.RenderMarkdownMermaidIcon and checked_icons.RenderMarkdownMermaidLabel,
        'Missing rendered table or Mermaid icon and label')
      local diagram_rows = {}
      for _, mark in ipairs(feature_marks) do
        local group = mark[4].hl_group or ''
        if group:find('RenderMarkdownMermaid', 1, true) == 1 then
          diagram_rows[mark[2] + 1] = true
        end
      end
      local diagram_width
      for row in pairs(diagram_rows) do
        local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1]
        local width = vim.fn.strdisplaywidth(line)
        diagram_width = diagram_width or width
        assert(width == diagram_width, 'Mermaid title or canvas has an uneven right edge')
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        vim.cmd('normal! zz')
        vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
        vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buffer })
        vim.cmd('redraw!')
        local position = vim.fn.screenpos(0, row, 1)
        for column = 0, width - 1 do
          local cell = vim.api.nvim__inspect_cell(1, position.row - 1, position.col - 1 + column)
          assert(cell[2].background == palette.block,
            'Mermaid rectangle contains a gap or differs from the table background')
        end
      end
      assert(diagram_width and diagram_width > 0, 'Missing rendered Mermaid canvas')
      vim.api.nvim_win_set_cursor(0, theme_cursor)
    end
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:find('stack traceback', 1, true), messages)
    vim.cmd('normal! gg')
    vim.cmd('redraw!')
  ]])
  evaluate([[vim.api.nvim_input_mouse('wheel', 'down', '', 0, 10, 90)]])
  vim.wait(100)
  local down_view = evaluate([[return vim.fn.winsaveview()]])
  evaluate([[vim.api.nvim_input_mouse('wheel', 'up', '', 0, 10, 90)]])
  vim.wait(100)
  local up_view = evaluate([[return vim.fn.winsaveview()]])
  assert(up_view.topline < down_view.topline or up_view.skipcol < down_view.skipcol,
    'Mouse wheel up did not reverse the preview scroll')
  evaluate([[
    vim.api.nvim_win_set_cursor(0, { 25, 0 })
    vim.cmd('normal! zt')
    vim.api.nvim_win_set_cursor(0, { 30, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
  ]])
  vim.wait(200)
  evaluate([[
    local context_found = false
    for _, window in ipairs(vim.api.nvim_list_wins()) do
      if vim.w[window].treesitter_context then
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)
        context_found = vim.tbl_contains(lines, '# Markdown preview')
      end
    end
    assert(context_found, 'Existing pinned-context renderer did not display the source heading over table rows')
    require('config.syntax.treesitter_context').go_to_nearest_context()
    assert(vim.api.nvim_win_get_cursor(0)[1] == 1, 'Section navigation lost its preview heading position')
    vim.cmd('normal! zt')
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
  ]])
  vim.wait(200)
  evaluate([[
    local preview_buffer = vim.api.nvim_get_current_buf()
    local source_tick = vim.api.nvim_buf_get_changedtick(vim.g.preview_test_source)
    local rendered_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local diagram_row
    for index, line in ipairs(rendered_lines) do
      if line:find('󰙅 mermaid', 1, true) then diagram_row = index; break end
    end
    assert(diagram_row, 'Rendered Mermaid fixture is missing')
    for _, row in ipairs({ 1, diagram_row }) do
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'xt', false)
      assert(vim.api.nvim_get_current_buf() == preview_buffer and not vim.bo.modifiable,
        'Enter unexpectedly left the rendered Markdown preview')
      assert(vim.api.nvim_win_get_cursor(0)[1] == row + 1, 'Enter lost native next-line movement')
    end
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
    vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'xt', false)
    assert(vim.api.nvim_get_current_buf() == preview_buffer,
      'Enter at the end of the preview switched to source mode')
    assert(vim.api.nvim_buf_get_changedtick(vim.g.preview_test_source) == source_tick,
      'Preview navigation modified the source')
    vim.api.nvim_feedkeys(vim.keycode('<Space>mp'), 'xt', false)
    assert(vim.api.nvim_get_current_buf() == vim.g.preview_test_source)
    assert(require('config.ui.statusline').project_relative_path() == 'docs/production/report.md [+]',
      'Switching to source changed the footer identity')
    assert(vim.api.nvim_win_get_cursor(0)[1] == 17, 'Source toggle lost the mapped source position')
    assert(vim.wo.conceallevel == 0 and vim.wo.foldmethod == 'expr', 'Source options were not restored')
    vim.api.nvim_feedkeys(vim.keycode('<Space>mp'), 'xt', false)
    assert(vim.b.markdown_preview_source == vim.g.preview_test_source)
    vim.api.nvim_feedkeys(vim.keycode('<Space>mp'), 'xt', false)
    assert(vim.api.nvim_get_current_buf() == vim.g.preview_test_source)
    assert(#vim.api.nvim_list_wins() == vim.g.preview_test_windows)
  ]])
  evaluate([[
    require('config.syntax.markdown.preview').toggle()
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 7 })
    vim.g.preview_insert_line = vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 16, 17, false)[1]
  ]])
  assert(vim.wait(10000, function()
    return evaluate([[
      local blocks = require('config.syntax.mermaid').stage(vim.g.preview_test_source)
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      return #blocks > 0 and not blocks[1].pending and not text:find('mermaid ↻', 1, true)
    ]])
  end, 50), 'Quick-edit fixture did not finish its initial render')
  evaluate([[
    vim.g.quick_edit_preview = vim.api.nvim_get_current_buf()
    vim.g.quick_edit_marks = vim.api.nvim_buf_get_extmarks(0,
      vim.api.nvim_get_namespaces().markdown_preview, 0, -1, {})
    local mermaid = require('config.syntax.mermaid')
    local start_process = mermaid.start_process
    vim.g.quick_edit_render_jobs = 0
    mermaid.start_process = function(...)
      vim.g.quick_edit_render_jobs = vim.g.quick_edit_render_jobs + 1
      return start_process(...)
    end
    _G.restore_quick_edit_process = function() mermaid.start_process = start_process end
  ]])
  vim.rpcnotify(child, 'nvim_input', 'i')
  vim.wait(100)
  assert(vim.rpcrequest(child, 'nvim_get_mode').mode == 'i', 'Preview i did not enter Insert mode')
  evaluate([[
    assert(vim.api.nvim_get_current_buf() == vim.g.preview_test_source and vim.bo.modifiable,
      'Insert mode is still targeting the read-only preview')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 17, 7 }), 'Insert lost the source position')
  ]])
  vim.rpcnotify(child, 'nvim_input', vim.keycode('EDIT<Esc>'))
  vim.wait(100)
  evaluate([[
    local before = vim.g.preview_insert_line
    local edited = vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 16, 17, false)[1]
    assert(edited == before:sub(1, 7) .. 'EDIT' .. before:sub(8), 'Insert did not edit the source text')
    assert(vim.b.markdown_preview_source == vim.g.preview_test_source and not vim.bo.modifiable,
      'Escape did not automatically return to rendered Markdown')
    assert(vim.bo[vim.g.preview_test_source].modified, 'Automatic preview lost unsaved changes')
    assert(vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview,
      'Quick edit recreated the preview buffer')
    assert(vim.g.quick_edit_render_jobs == 0, 'Prose-only quick edit restarted Termaid')
    assert(vim.deep_equal(vim.g.quick_edit_marks, vim.api.nvim_buf_get_extmarks(0,
      vim.api.nvim_get_namespaces().markdown_preview, 0, -1, {})),
      'Prose-only quick edit replaced unchanged feature highlights')
    _G.restore_quick_edit_process()
    _G.restore_quick_edit_process = nil
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:find('E21:', 1, true), messages)
  ]])
  vim.rpcnotify(child, 'nvim_input', ':w<CR>')
  assert(vim.wait(1000, function()
    return evaluate([[return not vim.bo[vim.g.preview_test_source].modified]])
  end, 10), 'Writing from the installed preview did not save the source')
  evaluate([[
    local source = vim.g.preview_test_source
    assert(vim.deep_equal(vim.fn.readfile(vim.api.nvim_buf_get_name(source)),
      vim.api.nvim_buf_get_lines(source, 0, -1, false)), 'Preview saved generated rows to the Markdown file')
    assert(vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview
      and not vim.bo.modifiable and not vim.api.nvim_get_mode().blocking,
      'Saving left the preview, made it editable, or blocked input')
    assert(require('config.ui.statusline').project_relative_path() == 'docs/production/report.md',
      'Saving from preview left the unsaved indicator in the statusline')
  ]])
  -- The preview owns no editing history: source undo/redo and native editing
  -- keys keep their counts, registers, operator motions, and retained view.
  vim.rpcnotify(child, 'nvim_input', 'u')
  assert(vim.wait(1000, function()
    return evaluate([[return vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 16, 17, false)[1]
      == vim.g.preview_insert_line and vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview]])
  end, 10), 'Preview undo did not undo the source edit in place')
  vim.rpcnotify(child, 'nvim_input', vim.keycode('<C-r>'))
  assert(vim.wait(1000, function()
    return evaluate([[return vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 16, 17, false)[1]
      ~= vim.g.preview_insert_line and vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview]])
  end, 10), 'Preview redo did not restore the source edit in place')
  evaluate([[
    vim.g.source_before_common_edit = vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 0, -1, false)
    vim.fn.setreg('z', 'REGISTER', 'v')
  ]])
  for _, edit in ipairs({
    { keys = '2x', prefix = nil },
    { keys = '"zP', prefix = 'REGISTER' },
    { keys = 'cwREPLACED<Esc>', prefix = 'REPLACED' },
    { keys = 'OInserted<Esc>', prefix = 'Inserted' },
    { keys = '.', prefix = 'Inserted' },
  }) do
    evaluate([[
      vim.api.nvim_win_set_cursor(0,
        require('config.syntax.markdown.preview').display_position(vim.api.nvim_get_current_win(), { 17, 0 }))
    ]])
    vim.rpcnotify(child, 'nvim_input', vim.keycode(edit.keys))
    assert(vim.wait(1000, function()
      return evaluate([[return vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview
        and not vim.deep_equal(vim.g.source_before_common_edit,
          vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 0, -1, false))]])
    end, 10), 'Common edit did not change source and restore preview: ' .. edit.keys)
    local edited_line = evaluate([[return vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 16, 17, false)[1] ]])
    if edit.prefix then
      assert(edited_line:sub(1, #edit.prefix) == edit.prefix, 'Edit lost its register/motion: ' .. edit.keys)
    else
      assert(edited_line == evaluate([[return vim.g.source_before_common_edit[17]:sub(3)]]),
        'Native edit lost its count')
    end
    vim.rpcnotify(child, 'nvim_input', 'u')
    assert(vim.wait(1000, function()
      return evaluate([[return vim.deep_equal(vim.g.source_before_common_edit,
        vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 0, -1, false))]])
    end, 10), 'Common edit was not a source undo step: ' .. edit.keys)
  end
  evaluate([[
    local blank_row
    for index, line in ipairs(vim.g.source_before_common_edit) do
      if line == '' then blank_row = index; break end
    end
    assert(blank_row, 'Common edit fixture needs an empty line')
    vim.api.nvim_win_set_cursor(0,
      require('config.syntax.markdown.preview').display_position(vim.api.nvim_get_current_win(), { blank_row, 0 }))
  ]])
  vim.rpcnotify(child, 'nvim_input', 'x')
  vim.wait(100)
  assert(evaluate([[return vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview
    and vim.deep_equal(vim.g.source_before_common_edit,
      vim.api.nvim_buf_get_lines(vim.g.preview_test_source, 0, -1, false))]]),
    'An edit with no change left the source exposed')
  vim.rpcnotify(child, 'nvim_input', 'd')
  assert(vim.wait(1000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'no' end, 10),
    'Preview interrupted a pending source operator')
  vim.rpcnotify(child, 'nvim_input', vim.keycode('<Esc>'))
  assert(vim.wait(1000, function()
    return evaluate([[return vim.api.nvim_get_current_buf() == vim.g.quick_edit_preview]])
  end, 10), 'Cancelling an operator did not restore preview')
  vim.rpcnotify(child, 'nvim_input', 'i')
  assert(vim.wait(1000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'i' end, 10))
  vim.rpcnotify(child, 'nvim_input', vim.keycode('<C-o>'))
  assert(vim.wait(1000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'niI' end, 10))
  vim.wait(50)
  assert(evaluate([[return vim.api.nvim_get_current_buf() == vim.g.preview_test_source]]),
    'Temporary Normal mode interrupted the quick edit')
  vim.rpcnotify(child, 'nvim_input', 'l')
  assert(vim.wait(1000, function() return vim.rpcrequest(child, 'nvim_get_mode').mode == 'i' end, 10))
  vim.rpcnotify(child, 'nvim_input', vim.keycode('<C-c>'))
  assert(vim.wait(1000, function()
    return evaluate([[return vim.b.markdown_preview_source == vim.g.preview_test_source]])
  end, 10), 'Ctrl-C did not return the quick edit to preview')
  vim.rpcnotify(child, 'nvim_input', vim.keycode('<Space>mp'))
  assert(vim.wait(1000, function()
    return evaluate([[return vim.api.nvim_get_current_buf() == vim.g.preview_test_source]])
  end, 10))
  vim.rpcnotify(child, 'nvim_input', vim.keycode('iRAW<Esc>'))
  vim.wait(100)
  assert(evaluate([[return vim.api.nvim_get_current_buf() == vim.g.preview_test_source]]),
    'Explicit raw mode was overridden after editing')
  -- Editing column guides must not leave stripes beyond fenced code blocks.
  vim.rpcrequest(child, 'nvim_ui_try_resize', 200, 40)
  evaluate([[
    vim.cmd('enew!')
    vim.wo.colorcolumn = '80,160'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      '# Code sample', '', '```lua', 'local value = 1', 'print(value)', '```', '', 'End prose',
    })
    vim.g.code_test_source = vim.api.nvim_get_current_buf()
    vim.bo.filetype = 'markdown'
  ]])
  assert(vim.wait(2000, function()
    return evaluate([[return vim.b.markdown_preview_source == vim.g.code_test_source]])
  end, 20), 'Code fixture did not open rendered')
  vim.wait(100)
  for _, name in ipairs({ 'morning', 'monokai' }) do
    vim.rpcrequest(child, 'nvim_exec_lua', [[
      vim.api.nvim_cmd({ cmd = 'colorscheme', args = { ... } }, {})
      vim.api.nvim_win_set_cursor(0, { 8, 0 })
      vim.cmd('redraw!')
    ]], { name })
    vim.wait(50)
    evaluate([[
      assert(vim.wo.colorcolumn == '', 'Code preview retained editing column guides')
      local background = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg
      for _, line in ipairs({ 3, 4, 5 }) do
        local position = vim.fn.screenpos(0, line, 1)
        for column = 40, 199 do
          local cell = vim.api.nvim__inspect_cell(1, position.row - 1, column)
          assert(cell[2].background == nil or cell[2].background == background,
            'Fenced code leaves a colored strip at screen column ' .. (column + 1))
        end
      end
    ]])
  end
  evaluate([[
    require('config.syntax.markdown.preview').toggle()
    assert(vim.wo.colorcolumn == '80,160', 'Returning to source lost column guides')
  ]])
  vim.rpcrequest(child, 'nvim_ui_try_resize', 120, 36)
  -- Several independently completing diagrams repeatedly move Markdown parse
  -- regions. Keep exercising actual input while those replacements arrive.
  evaluate([[
    vim.cmd('enew!')
    local lines = { '# Refresh stress test', '' }
    for section = 1, 7 do
      vim.list_extend(lines, {
        '## Section ' .. section, '',
        '[Documentation](https://example.com) and **emphasis**.', '',
        '| 名称 | 说明 | 指标 | 结果 |', '|---|---|---|---|',
      })
      for row = 1, 10 do
        lines[#lines + 1] = '| 项目 | ' .. string.rep('中文内容与 `code` ', 8)
          .. '| [目标](https://example.com) | ' .. string.rep('持续更新 ', 8) .. '|'
      end
      vim.list_extend(lines, {
        '', '```mermaid', 'graph LR', 'A[Section ' .. section .. '] --> B[Result]', '```', '',
        '```lua', 'local value = ' .. section, '```', '',
      })
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.filetype = 'markdown'
  ]])
  for step = 1, 30 do
    local started_at = vim.uv.hrtime()
    local mode = vim.rpcrequest(child, 'nvim_get_mode')
    assert((vim.uv.hrtime() - started_at) / 1e6 < 2000, 'Preview refresh blocked the UI for two seconds')
    assert(not mode.blocking, 'Preview refresh opened a blocking prompt')
    vim.rpcnotify(child, 'nvim_input', step % 2 == 0 and 'k' or 'j')
    if step == 10 then vim.rpcrequest(child, 'nvim_ui_try_resize', 90, 36) end
    if step == 20 then vim.rpcrequest(child, 'nvim_ui_try_resize', 120, 36) end
    vim.wait(100)
  end
  assert(vim.wait(10000, function()
    return evaluate([[
      local count = 0
      for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if line:find('󰙅 mermaid', 1, true) then count = count + 1 end
      end
      return count == 7
    ]])
  end, 100), 'Seven diagrams did not settle within ten seconds')
  evaluate([[
    local diagrams = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find('󰙅 mermaid', 1, true) then diagrams = diagrams + 1 end
    end
    assert(diagrams == 7, 'Stress fixture did not exercise all seven diagram replacements')
    local messages = vim.api.nvim_exec2('messages', { output = true }).output
    assert(not messages:find('stack traceback', 1, true), messages)
  ]])
  evaluate([[
    vim.g.homepage_test_source = vim.b.markdown_preview_source
    vim.g.homepage_test_window = vim.api.nvim_get_current_win()
    vim.api.nvim_feedkeys(vim.keycode('<Space>h'), 'xt', false)
  ]])
  assert(vim.wait(1500, function()
    return evaluate([[return vim.bo.filetype == 'dashboard' and not vim.bo.modifiable]])
  end, 20), 'Space h did not open the dashboard from Markdown preview')
  evaluate([[
    assert(vim.api.nvim_get_current_win() == vim.g.homepage_test_window, 'Homepage changed the editor pane')
    assert(not vim.wo.number and not vim.wo.relativenumber, 'Homepage inherited the preview number gutter')
    local intent = require('config.ui.window_state').resolve(0, { 'number' })
    assert(intent.number, 'Homepage lost the underlying editor line-number setting')
    vim.api.nvim_set_current_buf(vim.g.homepage_test_source)
  ]])
  assert(vim.wait(500, function()
    return evaluate([[return vim.b.markdown_preview_source == vim.g.homepage_test_source]])
  end, 20), 'Revisiting Markdown from the homepage lost the rendered preference')
  evaluate([[
    assert(vim.wo.number, 'Revisiting Markdown lost line numbers')
    vim.api.nvim_feedkeys(vim.keycode('i'), 'xt', false)
    assert(vim.api.nvim_get_current_buf() == vim.g.homepage_test_source and vim.wo.number,
      'Returning to source after the homepage lost line numbers')
  ]])
  local external_path = project_directory .. '/external.md'
  local function write_diagram(label)
    vim.fn.writefile({ '# External changes', '', '```mermaid', 'graph LR',
      'A[Input] --> B[' .. label .. ']', '```', '', 'End of document',
    }, external_path)
  end
  write_diagram('Original')
  vim.rpcrequest(child, 'nvim_exec_lua', [[
    vim.api.nvim_cmd({ cmd = 'edit', args = { ... }, bang = true }, {})
    vim.g.external_test_source = vim.api.nvim_get_current_buf()
  ]], { external_path })
  local function diagram_contains(label)
    return vim.rpcrequest(child, 'nvim_exec_lua', [[
      local label = ...
      local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      return vim.b.markdown_preview_source == vim.g.external_test_source
        and text:find('󰙅 mermaid', 1, true) ~= nil and text:find(label, 1, true) ~= nil
    ]], { label })
  end
  assert(vim.wait(10000, function() return diagram_contains('Original') end, 50),
    'External-change fixture did not render its initial diagram')
  local external_preview = evaluate([[return vim.api.nvim_get_current_buf()]])
  for _, change in ipairs({
    { label = 'DiskUpdate', event = 'FocusGained' },
    { label = 'IdleUpdate', event = 'CursorHold' },
  }) do
    write_diagram(change.label)
    vim.rpcrequest(child, 'nvim_exec_lua', [[
      vim.api.nvim_exec_autocmds(..., {})
    ]], { change.event })
    assert(vim.wait(10000, function() return diagram_contains(change.label) end, 50),
      change.event .. ' did not rerender the externally changed Mermaid diagram: ' .. vim.inspect(evaluate([[
        return { source = vim.api.nvim_buf_get_lines(vim.g.external_test_source, 0, -1, false),
          preview = vim.api.nvim_buf_get_lines(0, 0, -1, false),
          messages = vim.api.nvim_exec2('messages', { output = true }).output }
      ]])))
    assert(evaluate([[return vim.api.nvim_get_current_buf()]]) == external_preview,
      'External change replaced the preview session')
    assert(not diagram_contains('Original'), 'External change retained the cached diagram')
    assert(evaluate([[return not vim.bo[vim.g.external_test_source].modified]]),
      'External reload marked its source modified')
  end
  -- Keep the UI attached so render failures exercise normal hit-enter behavior.
  evaluate([[
    local mermaid = require('config.syntax.mermaid')
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, vim.g.preview_test_project .. '/invalid-diagram.md')
    local original_line_limit = mermaid.max_rendered_lines
    local original_window = vim.api.nvim_get_current_win()
    local original_buffer = vim.api.nvim_get_current_buf()
    local original_cursor = vim.api.nvim_win_get_cursor(0)
    local original_error = vim.v.errmsg
    for _, case in ipairs({
      { source = { 'not-a-diagram-type' }, width = 120, lines = original_line_limit,
        exit_code = 1 },
      { source = { 'graph LR', 'A --> B' }, width = 2, lines = original_line_limit,
        exit_code = 2 },
      { source = { 'graph LR', 'A --> B' }, width = 120, lines = 1,
        exit_code = 2 },
    }) do
      local source_lines = vim.list_extend({ '```mermaid' }, case.source)
      source_lines[#source_lines + 1] = '```'
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, source_lines)
      local tree = assert(vim.treesitter.get_parser(buffer, 'markdown'):parse()[1])
      local context = { buf = buffer, root = tree:root(), width = case.width }
      mermaid.max_rendered_lines = case.lines
      vim.cmd('messages clear')
      mermaid.parse(context)
      assert(vim.wait(10000, function()
        return vim.api.nvim_exec2('messages', { output = true }).output:find('Mermaid line 1:', 1, true)
      end, 20), 'Installed Termaid failure did not reach :messages')
      local messages = vim.api.nvim_exec2('messages', { output = true }).output
      assert(not messages:find('\n', 1, true) and messages:find('exit ' .. case.exit_code, 1, true),
        'Installed Termaid failure did not produce a single-line warning: ' .. messages)
      assert(not vim.api.nvim_get_mode().blocking and vim.v.errmsg == original_error,
        'Optional render failure blocked input or raised an editor error')
      assert(vim.api.nvim_get_current_win() == original_window
          and vim.api.nvim_get_current_buf() == original_buffer
          and vim.deep_equal(vim.api.nvim_win_get_cursor(0), original_cursor),
        'Optional render failure interrupted reading')
      assert(#mermaid.stage(buffer) == 0 and vim.deep_equal(
        vim.api.nvim_buf_get_lines(buffer, 0, -1, false), source_lines), 'Failed render replaced its source')
      mermaid.parse(context)
      assert(vim.api.nvim_exec2('messages', { output = true }).output == messages,
        'Cached installed Termaid failure repeated its log')
      mermaid.detach(buffer)
      vim.api.nvim_buf_set_lines(buffer, 1, 2, false, { 'graph LR' })
      assert(vim.api.nvim_buf_get_lines(buffer, 1, 2, false)[1] == 'graph LR',
        'Failed Mermaid source could not be edited')
    end
    mermaid.max_rendered_lines = original_line_limit
    vim.api.nvim_buf_delete(buffer, { force = true })
  ]])
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(project_directory, 'rf')
assert(passed, failure)
print('Installed Markdown prose, feature colors, source navigation, and scrolling passed')
