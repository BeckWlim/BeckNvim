-- Run with: nvim --headless -u init.lua -i NONE '+luafile tests/git/graph_installed.lua' '+qa!'
local graph = require('config.git.graph')
local root = vim.fn.getcwd()
local editor_tab = vim.api.nvim_get_current_tabpage()
local editor_buffer = vim.api.nvim_get_current_buf()

assert(graph.open(root), 'Graph history did not open')
assert(vim.wait(5000, function()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= 'Loading commit history…'
end, 20), 'Graph history did not load')
local windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 2, 'Graph history must have two windows')
local list_window = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_width(list_window) == math.floor(vim.o.columns * 0.40),
  'Default history list does not occupy 40% of the editor width')
local preview_window = windows[1] == list_window and windows[2] or windows[1]
assert(vim.api.nvim_win_get_position(list_window)[2]
  < vim.api.nvim_win_get_position(preview_window)[2],
  'History list is not left of the commit preview')
local list_buffer = vim.api.nvim_win_get_buf(list_window)
local preview_buffer = vim.api.nvim_win_get_buf(preview_window)
assert(vim.bo[preview_buffer].filetype == 'gitcommit'
  and not vim.bo[preview_buffer].modifiable,
  'Right window is not a read-only native commit buffer')
local first_line = vim.api.nvim_buf_get_lines(list_buffer, 0, 1, false)[1]
assert(first_line:find('●', 1, true) or first_line:find('◆', 1, true),
  'Commit graph node is missing')
local graph_namespace = vim.api.nvim_get_namespaces()['config-git-graph-list']
local marks = vim.api.nvim_buf_get_extmarks(list_buffer, graph_namespace, 0, -1,
  { details = true })
local graph_groups = {}
for _, mark in ipairs(marks) do
  if mark[4].hl_group then graph_groups[mark[4].hl_group] = true end
  for _, chunk in ipairs(mark[4].virt_text or {}) do
    graph_groups[chunk[2]] = true
  end
end
assert(graph_groups.DiagnosticInfo and graph_groups.DiagnosticOk
  and graph_groups.Directory and graph_groups.DiagnosticHint,
  'Commit graph colors did not use the shared theme roles')
assert(vim.wait(5000, function()
  local text = table.concat(vim.api.nvim_buf_get_lines(
    vim.api.nvim_win_get_buf(preview_window), 0, -1, false), '\n')
  return text:find('# Files changed in this commit:', 1, true)
    and not text:find('loading…', 1, true)
end, 20), 'Commit message and changed-file preview did not load')

local history_lines = vim.api.nvim_buf_get_lines(list_buffer, 0, -1, false)
local long_row
for row, line in ipairs(history_lines) do
  if vim.fn.strdisplaywidth(line) > vim.api.nvim_win_get_width(list_window) then
    long_row = row
    break
  end
end
assert(long_row, 'Long commit subjects are missing from the history buffer')
vim.api.nvim_win_set_cursor(list_window, { long_row, 0 })
vim.cmd('normal! $')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = list_buffer })
vim.cmd('redraw')
assert(vim.api.nvim_win_get_cursor(list_window)[2] >= #history_lines[long_row] - 4
  and vim.fn.winsaveview().leftcol > 0,
  'Moving right did not scroll to the end of the full commit subject')
vim.cmd('normal! gg0')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = list_buffer })
local next_commit_row
for row = 2, #history_lines do
  if history_lines[row]:find('●', 1, true) or history_lines[row]:find('◆', 1, true) then
    next_commit_row = row
    break
  end
end
assert(next_commit_row, 'History lacks a second selectable commit')
vim.cmd('normal! j')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = list_buffer })
assert(vim.api.nvim_win_get_cursor(list_window)[1] == next_commit_row,
  'Downward navigation stopped on a spacer or topology row')
vim.cmd('normal! k')
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = list_buffer })
assert(vim.api.nvim_win_get_cursor(list_window)[1] == 1,
  'Upward navigation stopped on a spacer or topology row')

local open_preview = vim.fn.maparg('o', 'n', false, true)
local enter_preview = vim.fn.maparg('<CR>', 'n', false, true)
assert(open_preview.buffer == 1 and enter_preview.buffer == 1,
  'Commit preview keys are not local to the graph')
assert(graph.focus_preview() and vim.api.nvim_get_current_win() == preview_window,
  'Commit preview did not focus the right window')
assert(graph.toggle_branches(), 'Branch pane did not open')
assert(vim.wait(5000, function()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= 'Loading branches…'
end, 20), 'Branch list did not load')
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Branch list did not split below history')
assert(vim.api.nvim_win_get_position(vim.api.nvim_get_current_win())[1]
  > vim.api.nvim_win_get_position(list_window)[1],
  'Branch list is not below the history list')
local fetch_mapping = vim.fn.maparg('f', 'n', false, true)
assert(fetch_mapping.buffer == 1, 'Fetch action is missing from branch pane')
assert(graph.toggle_branches(), 'Branch pane did not close')
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'Closing branches changed the main layout')

vim.api.nvim_set_current_win(list_window)
assert(vim.fn.maparg('<Space>dv', 'n', false, true).buffer == 1,
  'Commit list has no local detail binding')
vim.api.nvim_feedkeys(vim.keycode('<Space>dv'), 'mx', false)
local diffview = require('config.git.diffview')
assert(vim.wait(5000, diffview.is_active, 20), 'Diffview detail is inactive')
assert(diffview.toggle_history_layout(), 'Diffview detail did not return to graph')
assert(vim.wait(5000, graph.is_active, 20), 'Graph selection was not restored')
assert(vim.wait(5000, function()
  return vim.bo.filetype == 'gitgraph' and vim.api.nvim_get_current_line() ~= 'Loading commit history…'
end, 20))
assert(graph.focus_preview())
assert(vim.fn.maparg('<Space>dv', 'n', false, true).buffer == 1,
  'Commit message preview has no local detail binding')
vim.api.nvim_feedkeys(vim.keycode('<Space>dv'), 'mx', false)
assert(vim.wait(5000, diffview.is_active, 20), 'Preview detail key did not open Diffview')
assert(diffview.toggle_history_layout())
assert(vim.wait(5000, graph.is_active, 20))

local function type_quit()
  vim.api.nvim_feedkeys(vim.keycode(':q<CR>'), 'xt', false)
end

local function assert_git_closed(label)
  assert(vim.wait(5000, function()
    return not graph.is_active() and not diffview.is_active()
      and vim.api.nvim_get_current_tabpage() == editor_tab
  end, 20), label .. ' did not close the complete Git mode')
end

local function wait_for_graph()
  assert(vim.wait(5000, function()
    return graph.is_active() and vim.api.nvim_buf_get_lines(
      vim.api.nvim_get_current_buf(), 0, 1, false)[1] ~= 'Loading commit history…'
  end, 20), 'Graph did not reopen')
end

local graph_windows = vim.api.nvim_tabpage_list_wins(0)
local graph_list = vim.api.nvim_get_current_win()
local graph_preview = graph_windows[1] == graph_list and graph_windows[2] or graph_windows[1]
vim.api.nvim_set_current_win(graph_preview)
assert(vim.fn.maparg('<C-q>', 'n', false, true).buffer ~= 1,
  'Commit preview still maps Ctrl-Q as a pane close')
type_quit()
assert_git_closed('Preview :q')

assert(graph.open(root), 'Graph did not reopen for list quit')
wait_for_graph()
type_quit()
assert_git_closed('List :q')

assert(graph.open(root), 'Graph did not reopen for branch quit')
wait_for_graph()
assert(graph.toggle_branches(), 'Branch pane did not open for quit')
assert(vim.fn.maparg('<C-q>', 'n', false, true).buffer ~= 1,
  'Branch pane still maps Ctrl-Q as a pane close')
type_quit()
assert_git_closed('Branch :q')

assert(graph.open(root), 'Graph did not reopen for Diffview quit')
wait_for_graph()
assert(graph.open_detail(), 'Diffview detail did not open for quit')
assert(vim.wait(5000, diffview.is_active, 20), 'Diffview detail is inactive before quit')
assert(vim.wait(5000, function()
  local view = require('diffview.lib').get_current_view()
  return view and view.cur_layout and view.cur_layout.b
    and view.cur_layout.b.id and vim.api.nvim_win_is_valid(view.cur_layout.b.id)
end, 20), 'Diffview code pane did not render before quit')
local detail_view = require('diffview.lib').get_current_view()
vim.api.nvim_set_current_win(detail_view.cur_layout.b.id)
assert(vim.fn.maparg('<C-q>', 'n', false, true).buffer ~= 1,
  'Diffview code pane still maps Ctrl-Q as a close')
type_quit()
assert_git_closed('Diffview :q')
assert(vim.api.nvim_get_current_tabpage() == editor_tab
  and vim.api.nvim_get_current_buf() == editor_buffer,
  'Graph return did not restore the editor tab and buffer')
print('Installed Git graph tests passed')
