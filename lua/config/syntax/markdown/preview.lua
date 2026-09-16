local M = { max_source_bytes = 1024 * 1024, max_source_lines = 10000 }
local markdown = require('config.syntax.markdown')
local features = require('config.syntax.markdown_features')
local namespace = vim.api.nvim_create_namespace('markdown_preview')
local cursor_namespace = vim.api.nvim_create_namespace('markdown_preview_cursor')
local sessions = {}
local sessions_by_preview = {}
local window_option_names = {
  'number', 'relativenumber', 'signcolumn', 'foldcolumn', 'foldenable', 'foldmethod', 'wrap',
  'linebreak', 'breakindent', 'breakindentopt', 'showbreak', 'smoothscroll', 'cursorline', 'winbar',
  'conceallevel', 'concealcursor', 'colorcolumn',
}

local function set_buffer(window, buffer)
  vim.api.nvim_win_call(window, function()
    vim.api.nvim_cmd({ cmd = 'buffer', args = { tostring(buffer) }, mods = { keepjumps = true } }, {})
  end)
end

local function preview_options(session)
  local window = session.window
  vim.wo[window].foldmethod = 'manual'
  vim.wo[window].number = session.source_options.number
  vim.wo[window].relativenumber = session.source_options.relativenumber
  vim.wo[window].signcolumn = 'no'
  vim.wo[window].foldcolumn = '0'
  vim.wo[window].foldenable = false
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
  vim.wo[window].breakindent = true
  vim.wo[window].showbreak = '↳ '
  vim.wo[window].smoothscroll = true
  vim.wo[window].cursorline = true
  vim.wo[window].colorcolumn = ''
  vim.wo[window].winbar = ''
end

local function live(session)
  return sessions[session.source] == session
    and vim.api.nvim_buf_is_valid(session.source)
    and vim.api.nvim_win_is_valid(session.window)
    and vim.api.nvim_win_get_buf(session.window) == session.buffer
end

local function clamp_source_position(buffer, position)
  local row = math.max(1, math.min(position[1], vim.api.nvim_buf_line_count(buffer)))
  local line = vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1] or ''
  return { row, math.min(position[2], #line) }
end

local function source_position(session)
  local cursor = vim.api.nvim_win_get_cursor(session.window)
  local row = session.rows[cursor[1]]
  return row and features.source_position(row, cursor[2]) or { 1, 0 }
end

local function remember_source_position(session)
  if not live(session) or session.changedtick ~= vim.api.nvim_buf_get_changedtick(session.source) then return end
  local position = clamp_source_position(session.source, source_position(session))
  session.anchor = vim.api.nvim_buf_set_extmark(session.source, namespace,
    position[1] - 1, position[2], { id = session.anchor })
end

local function highlight_cursor(session)
  if not live(session) then return end
  local row = vim.api.nvim_win_get_cursor(session.window)[1] - 1
  vim.api.nvim_buf_clear_namespace(session.buffer, cursor_namespace, 0, -1)
  if not vim.wo[session.window].cursorline then return end
  vim.api.nvim_buf_set_extmark(session.buffer, cursor_namespace, row, 0, {
    end_row = row + 1, hl_group = 'CursorLine', hl_eol = true, priority = 1000,
  })
end

-- Each untouched prose run is a Markdown parse region. Generated rows already
-- contain their final text and styling; diagram labels must not become links,
-- list markers, or code blocks when the ordinary Markdown renderer attaches.
local function parse_prose(buffer, rows)
  local parser_ok, parser = pcall(vim.treesitter.get_parser, buffer, 'markdown')
  if not parser_ok then return end
  local regions = {}
  local first_row = nil
  for index = 1, #rows + 1 do
    local row = rows[index]
    if row and row.identity then
      if not first_row then first_row = index - 1 end
    elseif first_row then
      regions[#regions + 1] = { { first_row, 0, index - 1, 0 } }
      first_row = nil
    end
  end
  parser:set_included_regions(regions)
end

local function close(session, buffer_wiping)
  if sessions[session.source] ~= session then return end
  local returning_to_source = live(session) and not buffer_wiping and not session.source_gone
  local position = live(session) and clamp_source_position(session.source, source_position(session)) or nil
  sessions[session.source] = nil
  sessions_by_preview[session.buffer] = nil
  features.forget_buffer(session.source)
  markdown.detach(session.source)
  pcall(vim.api.nvim_del_augroup_by_id, session.group)
  if vim.api.nvim_buf_is_valid(session.source) then
    if returning_to_source then vim.b[session.source].markdown_preview_disabled = true end
    if session.anchor then
      pcall(vim.api.nvim_buf_del_extmark, session.source, namespace, session.anchor)
    end
  end
  if vim.api.nvim_win_is_valid(session.window)
      and vim.api.nvim_win_get_buf(session.window) == session.buffer then
    if not buffer_wiping then
      local replacement = not session.source_gone and vim.api.nvim_buf_is_valid(session.source)
        and session.source or vim.api.nvim_create_buf(true, false)
      set_buffer(session.window, replacement)
    end
    if returning_to_source then
      for name, value in pairs(session.source_options) do vim.wo[session.window][name] = value end
    end
    if returning_to_source and position and vim.api.nvim_win_get_buf(session.window) == session.source then
      vim.api.nvim_win_call(session.window, function() vim.fn.winrestview(session.source_view) end)
      vim.api.nvim_win_set_cursor(session.window, position)
    end
  end
  if vim.api.nvim_buf_is_valid(session.source) then
    vim.bo[session.source].bufhidden = session.source_bufhidden
  end
  if not buffer_wiping and vim.api.nvim_buf_is_valid(session.buffer) then
    vim.api.nvim_buf_delete(session.buffer, { force = true })
  end
end

local function jump_to_source(session)
  if not live(session) then return end
  if session.changedtick ~= vim.api.nvim_buf_get_changedtick(session.source) then M.refresh(session.source) end
  close(session)
  vim.cmd('normal! zv')
end

local function source_rows(buffer)
  local rows = {}
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
    rows[index] = { chunks = { { line } }, source_row = index - 1, identity = true }
  end
  return rows
end

local function project(session)
  local line_count = vim.api.nvim_buf_line_count(session.source)
  local byte_count = vim.api.nvim_buf_get_offset(session.source, line_count)
  if line_count > M.max_source_lines or byte_count > M.max_source_bytes then
    return { { chunks = { { 'Markdown preview: document exceeds the preview size limit.' } }, source_row = 0 } }
  end
  local parser_ok, parser = pcall(vim.treesitter.get_parser, session.source, 'markdown')
  if not parser_ok then return source_rows(session.source) end
  local tree = parser:parse()[1]
  if not tree then return source_rows(session.source) end
  local window_info = vim.fn.getwininfo(session.window)[1] or { textoff = 0 }
  return markdown.project({
    buf = session.source,
    root = tree:root(),
    width = math.max(1, vim.api.nvim_win_get_width(session.window) - window_info.textoff),
    cache = session.feature_cache,
  })
end

function M.refresh(source)
  local session = sessions[source]
  if not session or not live(session) then return end
  local anchor_position = session.anchor
    and vim.api.nvim_buf_get_extmark_by_id(session.source, namespace, session.anchor, {}) or {}
  local previous_position = #anchor_position == 2
    and { anchor_position[1] + 1, anchor_position[2] } or source_position(session)
  local view = vim.api.nvim_win_call(session.window, vim.fn.winsaveview)
  local projected_rows = project(session)
  session.changedtick = vim.api.nvim_buf_get_changedtick(session.source)
  local first_changed = 1
  while first_changed <= #session.rows and first_changed <= #projected_rows
      and vim.deep_equal(session.rows[first_changed], projected_rows[first_changed]) do
    first_changed = first_changed + 1
  end
  if first_changed > #session.rows and first_changed > #projected_rows then return end
  local old_end = #session.rows == 0 and vim.api.nvim_buf_line_count(session.buffer) or #session.rows
  local new_end = #projected_rows
  while old_end >= first_changed and new_end >= first_changed
      and vim.deep_equal(session.rows[old_end], projected_rows[new_end]) do
    old_end, new_end = old_end - 1, new_end - 1
  end
  local lines = {}
  for index = first_changed, new_end do
    local row = projected_rows[index]
    local parts = {}
    for _, chunk in ipairs(row.chunks) do parts[#parts + 1] = chunk[1] end
    lines[#lines + 1] = table.concat(parts)
  end
  session.rows = projected_rows
  -- A buffer replacement can synchronously redraw. Retire the old highlight
  -- iterators before changing lines whose Markdown parse regions are moving.
  local highlighted = vim.treesitter.highlighter.active[session.buffer] ~= nil
  if highlighted then vim.treesitter.stop(session.buffer) end
  vim.api.nvim_buf_clear_namespace(session.buffer, namespace, first_changed - 1, old_end)
  vim.bo[session.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(session.buffer, first_changed - 1, old_end, false, lines)
  vim.bo[session.buffer].modifiable = false
  vim.bo[session.buffer].modified = false
  parse_prose(session.buffer, projected_rows)
  if highlighted then vim.treesitter.start(session.buffer) end
  for index = first_changed, new_end do
    local row = projected_rows[index]
    local column = 0
    for _, chunk in ipairs(row.chunks) do
      if chunk[2] and #chunk[1] > 0 then
        vim.api.nvim_buf_set_extmark(session.buffer, namespace, index - 1, column, {
          end_col = column + #chunk[1], hl_group = chunk[2], priority = 200,
        })
      end
      column = column + #chunk[1]
    end
  end
  local target = features.preview_position(projected_rows, previous_position[1] - 1, previous_position[2])
  vim.api.nvim_win_call(session.window, function() vim.fn.winrestview(view) end)
  vim.api.nvim_win_set_cursor(session.window, target)
  remember_source_position(session)
  highlight_cursor(session)
end

local function schedule_refresh(session)
  if session.pending then return end
  session.pending = true
  local function apply_when_idle()
    if not live(session) then session.pending = false; return end
    local quiet_ms = (vim.uv.hrtime() - session.last_activity_ns) / 1e6
    if quiet_ms < 120 then
      vim.defer_fn(apply_when_idle, math.ceil(120 - quiet_ms))
      return
    end
    session.pending = false
    M.refresh(session.source)
  end
  vim.defer_fn(apply_when_idle, 80)
end

function M.open(source)
  local window = vim.api.nvim_get_current_win()
  local existing = sessions[source]
  if existing and live(existing) and existing.window == window then
    return existing.buffer
  end
  if existing and existing.window == window then
    local source_cursor = vim.api.nvim_win_get_cursor(window)
    existing.source_view = vim.fn.winsaveview()
    for _, name in ipairs(window_option_names) do existing.source_options[name] = vim.wo[window][name] end
    set_buffer(window, existing.buffer)
    preview_options(existing)
    M.refresh(source)
    vim.api.nvim_win_set_cursor(window,
      features.preview_position(existing.rows, source_cursor[1] - 1, source_cursor[2]))
    remember_source_position(existing)
    highlight_cursor(existing)
    return existing.buffer
  end
  if existing then close(existing) end
  local source_cursor = vim.api.nvim_win_get_cursor(window)
  local source_view = vim.fn.winsaveview()
  local source_options = {}
  for _, name in ipairs(window_option_names) do source_options[name] = vim.wo[window][name] end
  local source_bufhidden = vim.bo[source].bufhidden
  vim.bo[source].bufhidden = 'hide'
  vim.b[source].markdown_preview_disabled = false
  local buffer = vim.api.nvim_create_buf(false, true)
  -- Native jump entries refer to this buffer. Keep it until an explicit source
  -- transition or source/window teardown so forward jumps retain their target.
  vim.bo[buffer].bufhidden = 'hide'
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].undolevels = -1
  vim.b[buffer].markdown_preview_source = source
  vim.api.nvim_buf_set_name(buffer, ('markdown-preview://%d'):format(source))
  vim.wo[window].foldmethod = 'manual'
  set_buffer(window, buffer)
  local session = {
    source = source, buffer = buffer, window = window, rows = {}, feature_cache = {},
    last_activity_ns = vim.uv.hrtime(),
    source_options = source_options, source_view = source_view, source_bufhidden = source_bufhidden,
    group = vim.api.nvim_create_augroup('markdown_preview_' .. buffer, { clear = true }),
  }
  sessions[source] = session
  sessions_by_preview[buffer] = session
  preview_options(session)
  features.subscribe(source, function() schedule_refresh(session) end)
  local close_preview = function() close(session) end
  require('config.ui.float').bind_close({ buffer = buffer, close = close_preview, description = 'Return to Markdown source' })
  vim.keymap.set({ 'n', 'x' }, '<C-q>', close_preview, { buffer = buffer, silent = true })
  vim.keymap.set('n', 'i', function()
    if not live(session) then return end
    jump_to_source(session)
    vim.cmd('startinsert')
  end, { buffer = buffer, silent = true, desc = 'Edit Markdown source at cursor' })
  vim.keymap.set('n', '<Space>mp', close_preview, { buffer = buffer, desc = 'Return to Markdown source' })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = session.group, buffer = buffer, callback = function()
      if not vim.api.nvim_win_is_valid(window) then return end
      for name, value in pairs(source_options) do vim.wo[window][name] = value end
      for _, name in ipairs({ 'wrap', 'linebreak', 'breakindent', 'showbreak', 'smoothscroll' }) do
        vim.wo[window][name] = vim.go[name]
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = session.group, buffer = buffer, callback = function()
      if not live(session) then return end
      preview_options(session)
      -- The native jump sets its destination cursor after BufWinEnter finishes.
      vim.schedule(function()
        if not live(session) then return end
        remember_source_position(session)
        M.refresh(source)
        highlight_cursor(session)
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost', 'FileChangedShellPost' }, {
    group = session.group, buffer = source, callback = function() schedule_refresh(session) end,
  })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = session.group, buffer = buffer, callback = function()
      session.last_activity_ns = vim.uv.hrtime()
      remember_source_position(session)
      highlight_cursor(session)
    end,
  })
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = session.group, pattern = tostring(window), callback = function()
      session.last_activity_ns = vim.uv.hrtime()
    end,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = session.group, callback = function() schedule_refresh(session) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = session.group, buffer = source, callback = function()
      session.source_gone = true
      close(session)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = session.group, buffer = buffer, callback = function() close(session, true) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = session.group, pattern = tostring(window), callback = close_preview,
  })
  M.refresh(source)
  vim.bo[buffer].filetype = 'markdown'
  vim.api.nvim_win_set_cursor(window, features.preview_position(session.rows, source_cursor[1] - 1, source_cursor[2]))
  remember_source_position(session)
  highlight_cursor(session)
  return buffer
end

-- Syntax context resolves ancestry in the original document, then projects
-- heading positions back into this window's generated rows.
function M.source_location(window)
  local session = sessions_by_preview[vim.api.nvim_win_get_buf(window)]
  if not session or not live(session) or session.window ~= window then return end
  return session.source, clamp_source_position(session.source, source_position(session))
end

function M.display_position(window, position)
  local session = sessions_by_preview[vim.api.nvim_win_get_buf(window)]
  if not session or not live(session) or session.window ~= window then return end
  return features.preview_position(session.rows, position[1] - 1, position[2])
end

-- Leave the generated buffer before another full-pane UI captures the file and
-- editor options. Revisiting that file should retain its rendered preference.
function M.leave()
  local session = sessions_by_preview[vim.api.nvim_get_current_buf()]
  if not session or not live(session) then return end
  jump_to_source(session)
  if vim.api.nvim_buf_is_valid(session.source) then
    vim.b[session.source].markdown_preview_disabled = false
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('markdown_default_preview', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter' }, {
    group = group,
    callback = function(event)
      local buffer = event.buf
      local window = vim.api.nvim_get_current_win()
      if vim.bo[buffer].filetype ~= 'markdown' or vim.bo[buffer].buftype ~= ''
          or vim.b[buffer].markdown_preview_source
          or vim.api.nvim_win_get_buf(window) ~= buffer then return end
      vim.wo[window].conceallevel = 0
      if vim.b[buffer].markdown_preview_disabled then return end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_win_is_valid(window)
            and vim.api.nvim_get_current_win() == window
            and vim.api.nvim_win_get_buf(window) == buffer
            and not vim.b[buffer].markdown_preview_disabled then
          M.open(buffer)
        end
      end)
    end,
    desc = 'Show Markdown files rendered by default in their current pane',
  })
end

function M.toggle()
  local buffer = vim.api.nvim_get_current_buf()
  local session = sessions_by_preview[buffer]
  if session then close(session); return end
  if vim.bo[buffer].filetype ~= 'markdown' then
    vim.notify('Markdown preview is available in Markdown buffers', vim.log.levels.INFO)
    return
  end
  M.open(buffer)
end

return M
