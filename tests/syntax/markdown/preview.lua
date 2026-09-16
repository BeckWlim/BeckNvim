local preview = require('config.syntax.markdown.preview')
local markdown = require('config.syntax.markdown')
local features = require('config.syntax.markdown_features')
local original_buffer = vim.api.nvim_get_current_buf()
local original_options = {
  number = vim.wo.number, winbar = vim.wo.winbar, wrap = vim.wo.wrap,
  relativenumber = vim.wo.relativenumber, colorcolumn = vim.wo.colorcolumn,
  conceallevel = vim.wo.conceallevel, concealcursor = vim.wo.concealcursor,
}
local source = vim.api.nvim_create_buf(true, false)
local source_lines = {
  string.rep('Prose before the table. ', 10), '',
  '| heading | description |', '|---|---|',
  '| value | alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november |', '',
  string.rep('Prose after the table. ', 10),
}
vim.api.nvim_buf_set_lines(source, 0, -1, false, source_lines)
vim.api.nvim_set_current_buf(source)
local window = vim.api.nvim_get_current_win()
local window_count = #vim.api.nvim_list_wins()
local window_width = vim.api.nvim_win_get_width(window)
vim.wo[window].wrap = true
vim.wo[window].number = true
vim.wo[window].relativenumber = true
vim.wo[window].winbar = 'source window'
vim.wo[window].colorcolumn = '80,160'
local source_tick = vim.api.nvim_buf_get_changedtick(source)
preview.setup()
vim.bo[source].filetype = 'markdown'
assert(vim.wait(200, function() return vim.api.nvim_get_current_buf() ~= source end, 5),
  'Markdown did not open rendered by default')
local preview_buffer = vim.api.nvim_get_current_buf()
assert(vim.wo[window].winbar == '', 'Preview retained the shortcut banner')
assert(vim.wo[window].colorcolumn == '', 'Rendered Markdown retained editing column guides')
assert(vim.wo[window].number and vim.wo[window].relativenumber,
  'Preview hid the editor line-number settings')
assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == window_count
  and vim.api.nvim_win_get_width(window) == window_width, 'Default rendering changed the pane layout')
assert(vim.b[preview_buffer].markdown_preview_source == source and not vim.bo[preview_buffer].modifiable,
  'Default view is not an independent read-only projection')
local preview_lines = vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false)
local blank_count = 0
for _, line in ipairs(preview_lines) do if line == '' then blank_count = blank_count + 1 end end
assert(blank_count == 2, 'Preview inserted phantom blank rows beneath the table')
assert(#preview_lines > #source_lines, 'Table continuations are not real preview lines')
assert(source_tick == vim.api.nvim_buf_get_changedtick(source), 'Preview changed source text')
local prose_parser = vim.treesitter.get_parser(preview_buffer, 'markdown')
local prose_regions = prose_parser:included_regions()
assert(#prose_regions == 2, 'Generated table rows were included in Markdown parsing')
assert(prose_regions[1][1][1] == 0 and prose_regions[1][1][4] == 2
  and prose_regions[2][1][1] == #preview_lines - 2,
  'Prose regions do not preserve the surrounding source lines')
local tree = assert(vim.treesitter.get_parser(source, 'markdown'):parse()[1])
local rows = markdown.project({
  buf = source, root = tree:root(), width = window_width - vim.fn.getwininfo(window)[1].textoff,
})
local target_row
for index, row in ipairs(rows) do
  if row.source_row == 4 and row.spans and row.spans[1].source_column > 20 then target_row = index; break end
end
assert(target_row, 'Fixture has no mapped table continuation')
local target_column = rows[target_row].spans[1].first
local source_target = features.source_position(rows[target_row], target_column)
vim.api.nvim_win_set_cursor(window, { target_row, target_column })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = preview_buffer })
local cursor_namespace = vim.api.nvim_get_namespaces().markdown_preview_cursor
local cursor_marks = vim.api.nvim_buf_get_extmarks(preview_buffer, cursor_namespace, 0, -1, { details = true })
assert(#cursor_marks == 1 and cursor_marks[1][2] == target_row - 1
  and cursor_marks[1][4].hl_group == 'CursorLine' and cursor_marks[1][4].priority > 200,
  'Current table row does not place CursorLine above semantic chunk backgrounds')
-- Simulate the prose renderer's window options before returning to editable source.
vim.wo[window].conceallevel = 3
vim.wo[window].concealcursor = 'nvic'
vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'xt', false)
assert(vim.api.nvim_get_current_win() == window and vim.api.nvim_get_current_buf() == preview_buffer,
  'Enter unexpectedly switched the rendered table to source mode')
assert(vim.api.nvim_win_get_cursor(window)[1] == target_row + 1,
  'Enter lost its native next-line movement in the preview')
assert(vim.api.nvim_buf_get_changedtick(source) == source_tick and not vim.bo[preview_buffer].modifiable,
  'Enter changed the source or made the preview editable')
vim.api.nvim_win_set_cursor(window, { target_row, target_column })
vim.api.nvim_feedkeys('q', 'xt', false)
assert(vim.api.nvim_get_current_win() == window and vim.api.nvim_get_current_buf() == source,
  'q did not restore source in the same pane')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(window), source_target), 'q lost its source byte position')
assert(vim.wo[window].number and vim.wo[window].winbar == 'source window' and vim.wo[window].wrap,
  'Returning to source did not restore window options')
assert(vim.wo[window].conceallevel == 0 and vim.wo[window].concealcursor == original_options.concealcursor,
  'Source mode still conceals Markdown punctuation')
vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = source })
vim.wait(50)
assert(vim.api.nvim_get_current_buf() == source, 'Automatic preview overrode the explicit source selection')
assert(not vim.api.nvim_buf_is_valid(preview_buffer), 'Source toggle retained the old preview buffer')
assert(vim.wo[window].colorcolumn == '80,160', 'Source toggle lost its editing column guides')
preview.toggle()
vim.api.nvim_win_set_cursor(window, { target_row, target_column })
vim.api.nvim_feedkeys(vim.keycode('iEDIT<Esc>'), 'xt', false)
assert(vim.api.nvim_get_current_buf() == source and vim.api.nvim_get_current_win() == window,
  'Insert did not switch from preview to source in the same pane')
local original_table_line = source_lines[source_target[1]]
local expected_table_line = original_table_line:sub(1, source_target[2])
  .. 'EDIT' .. original_table_line:sub(source_target[2] + 1)
assert(vim.api.nvim_buf_get_lines(source, source_target[1] - 1, source_target[1], false)[1] == expected_table_line,
  'Typing from a wrapped preview cell did not insert at its mapped source byte')
vim.api.nvim_buf_set_lines(source, source_target[1] - 1, source_target[1], false, { original_table_line })
vim.api.nvim_buf_set_lines(source, 6, 7, false, { 'changed prose after table' })
preview.toggle()
local reopened = vim.api.nvim_get_current_buf()
assert(reopened ~= source and #vim.api.nvim_list_wins() == window_count,
  'Render toggle opened an extra pane')
assert(vim.api.nvim_buf_get_lines(reopened, -2, -1, false)[1] == 'changed prose after table',
  'Reopening the rendered view did not reflect source edits')
vim.api.nvim_win_set_cursor(window, { vim.api.nvim_buf_line_count(reopened), 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = reopened })
vim.treesitter.start(reopened)
vim.api.nvim_buf_set_lines(source, 0, 0, false, { 'inserted above preview selection' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = source })
for _ = 1, 4 do
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = reopened })
  vim.wait(50)
  assert(vim.api.nvim_buf_get_lines(reopened, 0, 1, false)[1] ~= 'inserted above preview selection',
    'A background refresh interrupted ongoing preview navigation')
end
assert(vim.wait(200, function()
  return vim.api.nvim_buf_get_lines(reopened, 0, 1, false)[1] == 'inserted above preview selection'
end, 5), 'Hidden source edits did not refresh the rendered view')
assert(vim.treesitter.highlighter.active[reopened], 'Refresh did not restore prose highlighting')
local preserved_cursor = vim.api.nvim_win_get_cursor(window)
assert(vim.api.nvim_buf_get_lines(reopened, preserved_cursor[1] - 1, preserved_cursor[1], false)[1]
  == 'changed prose after table', 'Source insertion moved the selection to unrelated text')
vim.api.nvim_feedkeys('q', 'xt', false)
assert(vim.api.nvim_win_is_valid(window) and vim.api.nvim_get_current_buf() == source,
  'Leaving rendered view closed the editor pane')
features.request_render(source, 'late result')
vim.wait(50)
assert(vim.api.nvim_get_current_buf() == source, 'Late callback reopened an explicitly closed view')
preview.toggle()
local code_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(code_buffer)
assert(vim.api.nvim_get_current_buf() == code_buffer and vim.wo.wrap == vim.go.wrap,
  'Leaving rendered Markdown changed the next buffer or leaked its wrapping')
vim.api.nvim_set_current_buf(source)
assert(vim.wait(200, function() return vim.api.nvim_get_current_buf() ~= source end, 5),
  'Revisiting a rendered Markdown file unexpectedly selected raw source')
preview.toggle()
vim.api.nvim_buf_delete(code_buffer, { force = true })
preview.toggle()
preview.toggle()
assert(#vim.api.nvim_list_wins() == window_count and vim.api.nvim_get_current_buf() == source,
  'Repeated toggles changed window layout or source selection')
vim.cmd('vsplit')
local second_window = vim.api.nvim_get_current_win()
preview.toggle()
vim.api.nvim_set_current_win(window)
preview.toggle()
assert(vim.api.nvim_get_current_win() == window and vim.b.markdown_preview_source == source
  and vim.api.nvim_win_get_buf(second_window) == source,
  'Toggling a shared Markdown file redirected focus into another pane')
preview.toggle()
vim.api.nvim_win_close(second_window, true)
vim.api.nvim_del_augroup_by_name('markdown_default_preview')
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(source, { force = true })
local section_source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(section_source, 0, -1, false, {
  '# Document', '', '## Table section', '', '| Key | Value |', '|---|---|',
  '| item | ' .. string.rep('wrapped content ', 100) .. '|', '',
  '## Next section', '', 'Next body',
})
vim.api.nvim_set_current_buf(section_source)
vim.bo.filetype = 'markdown'
preview.open(section_source)
local section_position = preview.display_position(window, { 7, 400 })
vim.api.nvim_win_set_cursor(window, section_position)
vim.cmd('normal! zt5j')
local context = require('config.syntax.treesitter_context')
local _, heading_lines = context.preview_context(window)
assert(vim.deep_equal(heading_lines, { '# Document', '## Table section' }),
  'Preview lost nested source headings inside generated table rows')
context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(window)[1] == 3, 'Section jump did not reach the mapped subsection')
context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(window)[1] == 1, 'Repeated section jump lost the document heading')
preview.toggle()
vim.wo.number = false
vim.wo.relativenumber = false
preview.open(section_source)
assert(not vim.wo.number and not vim.wo.relativenumber,
  'Preview overrode an intentional choice to hide line numbers')
preview.toggle()
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(section_source, { force = true })

-- Disk reloads affect the hidden source without firing its editing events.
local external_path = vim.fn.tempname() .. '.md'
local saved_autoread = vim.o.autoread
vim.o.autoread = true
vim.fn.writefile({ '# Before reload', '', 'Original prose' }, external_path)
vim.api.nvim_cmd({ cmd = 'edit', args = { external_path } }, {})
local external_source = vim.api.nvim_get_current_buf()
local external_preview = preview.open(external_source)
vim.fn.writefile({ '# After external reload', '', 'Updated prose from disk' }, external_path)
vim.api.nvim_cmd({ cmd = 'checktime', args = { tostring(external_source) } }, {})
assert(vim.api.nvim_buf_get_lines(external_source, 0, 1, false)[1] == '# After external reload',
  'External change fixture did not reload its hidden source')
assert(vim.wait(500, function()
  return vim.api.nvim_buf_get_lines(external_preview, 0, 1, false)[1] == '# After external reload'
end, 5), 'External file reload did not refresh the rendered preview')
assert(vim.api.nvim_get_current_buf() == external_preview and not vim.bo[external_source].modified,
  'External reload left the preview or modified the source')
vim.api.nvim_buf_set_lines(external_source, 0, 1, false, { '# Unsaved local edit' })
vim.fn.writefile({ '# Conflicting external change', '', 'Disk content' }, external_path)
local conflict_reason
local conflict_handler = vim.api.nvim_create_autocmd('FileChangedShell', {
  buffer = external_source,
  callback = function()
    conflict_reason = vim.v.fcs_reason
    vim.v.fcs_choice = '' -- Keep local edits without opening an interactive prompt in the test.
  end,
})
vim.api.nvim_cmd({ cmd = 'checktime', args = { tostring(external_source) } }, {})
assert(conflict_reason == 'conflict' and vim.bo[external_source].modified
  and vim.api.nvim_buf_get_lines(external_source, 0, 1, false)[1] == '# Unsaved local edit',
  'External file checks bypassed Neovim conflict handling or overwrote local edits')
assert(vim.api.nvim_get_current_buf() == external_preview
  and vim.api.nvim_buf_get_lines(external_preview, 0, 1, false)[1] ~= '# Conflicting external change',
  'Conflict handling replaced the preview with disk content')
vim.api.nvim_del_autocmd(conflict_handler)
preview.toggle()
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(external_source, { force = true })
vim.fn.delete(external_path)
vim.o.autoread = saved_autoread
for name, value in pairs(original_options) do vim.wo[name] = value end
