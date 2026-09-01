local github = require('config.git.github')
local panel = require('config.git.panel')

local M = {}
local active_detail

local function display_date(timestamp)
  return timestamp ~= '' and timestamp:gsub('T', ' '):gsub('Z$', ' UTC') or 'unknown'
end

function M.lines(issue)
  local label_text = #issue.labels > 0 and table.concat(issue.labels, ', ') or 'none'
  local description_lines = issue.body ~= ''
      and vim.split(issue.body, '\n', { plain = true })
    or { '_No description._' }
  local rendered_lines = {
    ('# #%d · %s'):format(issue.number, issue.title),
    '',
    ('**%s · %s · REMOTE** · @%s'):format(issue.kind, issue.state:upper(), issue.author),
    issue.remote_host
        and ('Remote: `%s/%s`'):format(issue.remote_host, issue.remote_repository)
      or 'Remote: project origin',
    ('Labels: %s'):format(label_text),
    ('Created: %s · Updated: %s · Comments: %d'):format(
      display_date(issue.created_at),
      display_date(issue.updated_at),
      issue.comments
    ),
    '',
  }
  vim.list_extend(rendered_lines, description_lines)
  vim.list_extend(rendered_lines, {
    '',
    ('[Open on GitHub](%s)'):format(issue.html_url),
    '',
    '_`q` / `<Space>de` returns to search · `<C-q>` returns to Git history · `o` opens GitHub._',
  })
  return rendered_lines
end

local function set_buffer_lines(buffer, rendered_lines)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, rendered_lines)
  vim.bo[buffer].modifiable = false
end

function M.render_buffer(buffer, issue)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].filetype = 'markdown'
  vim.b[buffer].git_issue_number = tostring(issue.number)
  vim.b[buffer].git_issue_url = issue.html_url
  vim.b[buffer].git_result_source = 'REMOTE'
  set_buffer_lines(buffer, M.lines(issue))
end

local function issue_number_under_cursor(buffer, window)
  local cursor = vim.api.nvim_win_get_cursor(window)
  local line = vim.api.nvim_buf_get_lines(buffer, cursor[1] - 1, cursor[1], false)[1] or ''
  local search_start = 1
  while search_start <= #line do
    local match_start, match_end, issue_digits = line:find('#(%d+)', search_start)
    if not match_start or not match_end then
      return nil
    end
    if cursor[2] + 1 >= match_start and cursor[2] + 1 <= match_end then
      return issue_digits
    end
    search_start = match_end + 1
  end
  return nil
end

local function close_detail(reopen_results)
  local detail = active_detail
  active_detail = nil
  if not detail then
    return false
  end
  panel.leave_search(detail)
  if detail.window and vim.api.nvim_win_is_valid(detail.window) then
    vim.api.nvim_win_close(detail.window, true)
  elseif detail.buffer and vim.api.nvim_buf_is_valid(detail.buffer) then
    vim.api.nvim_buf_delete(detail.buffer, { force = true })
  end
  if reopen_results and detail.return_to_results then
    vim.schedule(detail.return_to_results)
  elseif detail.parent_tabpage and vim.api.nvim_tabpage_is_valid(detail.parent_tabpage) then
    vim.api.nvim_set_current_tabpage(detail.parent_tabpage)
    if detail.parent_window and vim.api.nvim_win_is_valid(detail.parent_window) then
      vim.api.nvim_set_current_win(detail.parent_window)
    end
  end
  return true
end

local function open_external_url(buffer)
  local issue_url = vim.b[buffer].git_issue_url
  if not issue_url or issue_url == '' then
    vim.notify('GitHub URL is not available', vim.log.levels.INFO)
    return
  end
  vim.ui.open(issue_url)
end

local function attach_mappings(buffer, root)
  vim.keymap.set('n', 'q', function()
    close_detail(true)
  end, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Return to Git search results',
  })
  vim.keymap.set('n', '<Space>de', function()
    close_detail(true)
  end, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Return to Git search',
  })
  vim.keymap.set('n', panel.close_key, function()
    panel.pop()
  end, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Close current Git panel layer',
  })
  vim.keymap.set('n', 'o', function()
    open_external_url(buffer)
  end, { buffer = buffer, silent = true, desc = 'Open issue on GitHub' })
  vim.keymap.set('n', 'gx', function()
    open_external_url(buffer)
  end, { buffer = buffer, silent = true, desc = 'Open issue on GitHub' })
  vim.keymap.set('n', '<CR>', function()
    local issue_window = vim.fn.bufwinid(buffer)
    if issue_window == -1 then
      return
    end
    local related_issue_number = issue_number_under_cursor(buffer, issue_window)
    local current_issue_number = vim.b[buffer].git_issue_number
    if not related_issue_number or related_issue_number == current_issue_number then
      open_external_url(buffer)
      return
    end
    set_buffer_lines(buffer, { ('Loading GitHub issue #%s…'):format(related_issue_number) })
    github.fetch_issue(root, related_issue_number, function(related_issue, issue_error)
      if not vim.api.nvim_buf_is_valid(buffer) then
        return
      end
      if not related_issue then
        set_buffer_lines(buffer, {
          ('GitHub issue #%s unavailable'):format(related_issue_number),
          '',
          issue_error or 'Unknown GitHub error',
        })
        return
      end
      vim.api.nvim_buf_set_name(
        buffer,
        ('github://%s/issues/%d'):format(vim.fs.basename(root), related_issue.number)
      )
      M.render_buffer(buffer, related_issue)
    end)
  end, { buffer = buffer, silent = true, desc = 'Open related GitHub issue' })
end

function M.open_file(root, issue, options)
  close_detail(false)
  local detail_options = options or {}
  local parent_tabpage = detail_options.parent_tabpage or vim.api.nvim_get_current_tabpage()
  local parent_window = vim.api.nvim_get_current_win()
  if parent_tabpage and vim.api.nvim_tabpage_is_valid(parent_tabpage) then
    vim.api.nvim_set_current_tabpage(parent_tabpage)
  end
  local detail_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[detail_buffer].bufhidden = 'wipe'
  vim.bo[detail_buffer].buftype = 'nofile'
  vim.bo[detail_buffer].swapfile = false
  vim.api.nvim_buf_set_name(
    detail_buffer,
    ('github://%s/issues/%d'):format(vim.fs.basename(root), issue.number)
  )
  M.render_buffer(detail_buffer, issue)
  local available_width = math.max(1, vim.o.columns - 4)
  local available_height = math.max(1, vim.o.lines - 4)
  local detail_width = math.min(available_width, math.max(60, math.floor(vim.o.columns * 0.72)))
  local detail_height = math.min(available_height, math.max(12, math.floor(vim.o.lines * 0.72)))
  local detail_window = vim.api.nvim_open_win(detail_buffer, true, {
    border = 'rounded',
    col = math.floor((vim.o.columns - detail_width) / 2),
    height = detail_height,
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - detail_height) / 2) - 1),
    style = 'minimal',
    title = (' GitHub #%d · REMOTE '):format(issue.number),
    title_pos = 'center',
    width = detail_width,
  })
  attach_mappings(detail_buffer, root)
  vim.wo[detail_window].cursorline = true
  vim.wo[detail_window].linebreak = true
  vim.wo[detail_window].wrap = true
  local detail = {
    buffer = detail_buffer,
    parent_tabpage = parent_tabpage,
    parent_window = parent_window,
    return_to_results = detail_options.return_to_results,
    window = detail_window,
  }
  active_detail = detail
  panel.enter_search(detail, function()
    close_detail(false)
  end)
  return true
end

function M.is_active()
  return active_detail ~= nil
end

function M.close()
  return close_detail(false)
end

return M
