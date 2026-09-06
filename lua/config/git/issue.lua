local github = require('config.git.github')
local panel = require('config.git.panel')
local treesitter = require('config.syntax.treesitter')
local open_target = require('config.ui.open_target')

local M = {}
local active_detail
local direct_request_generation = 0
local pending_direct_request

local function clear_loading_message()
  pcall(vim.api.nvim_echo, {}, false, {})
end

local function cancel_pending_direct_request()
  direct_request_generation = direct_request_generation + 1
  local pending_request = pending_direct_request
  pending_direct_request = nil
  if pending_request then
    pending_request.cancel()
    clear_loading_message()
  end
end

local function resource_segment(github_record)
  return github_record.kind == 'Pull request' and 'pull' or 'issues'
end

local function buffer_name(root, github_record)
  local repository_identity = github_record.remote_repository or vim.fs.basename(root)
  return ('github://%s/%s/%d'):format(
    repository_identity,
    resource_segment(github_record),
    github_record.number
  )
end

local function display_date(timestamp)
  return timestamp ~= '' and timestamp:gsub('T', ' '):gsub('Z$', ' UTC') or 'unknown'
end

function M.lines(github_record)
  local label_text = #github_record.labels > 0
      and table.concat(github_record.labels, ', ')
    or 'none'
  local description_lines = github_record.body ~= ''
      and vim.split(github_record.body, '\n', { plain = true })
    or { '_No description._' }
  local remote_identity = github_record.remote_host
      and ('%s/%s#%d'):format(
        github_record.remote_host,
        github_record.remote_repository,
        github_record.number
      )
    or ('GitHub #%d'):format(github_record.number)
  local commit_shas = github_record.commit_shas or {}
  local commit_lines = {}
  if github_record.kind == 'Pull request' then
    for index, commit_sha in ipairs(commit_shas) do
      commit_lines[index] = ('Commit %d: `%s`'):format(index, commit_sha)
    end
  end
  local rendered_lines = {
    ('# #%d · %s'):format(github_record.number, github_record.title),
    '',
    ('**%s · %s · REMOTE** · @%s'):format(
      github_record.kind,
      github_record.state:upper(),
      github_record.author
    ),
    ('Remote: [%s](%s)'):format(remote_identity, github_record.html_url),
    ('Labels: %s'):format(label_text),
    ('Created: %s · Updated: %s · Comments: %d'):format(
      display_date(github_record.created_at),
      display_date(github_record.updated_at),
      github_record.comments
    ),
    '',
  }
  if #commit_lines > 0 then
    for index = #commit_lines, 1, -1 do
      table.insert(rendered_lines, 5, commit_lines[index])
    end
  end
  vim.list_extend(rendered_lines, description_lines)
  vim.list_extend(rendered_lines, { '', '## Discussion', '' })
  local discussion = github_record.discussion or {}
  if #discussion == 0 then
    local discussion_status = github_record.comments == 0
        and '_No discussion._'
      or ('_Discussion could not be loaded; open GitHub to view %d comments._'):format(
        github_record.comments
      )
    rendered_lines[#rendered_lines + 1] = discussion_status
  else
    for comment_index, comment in ipairs(discussion) do
      if comment_index > 1 then
        rendered_lines[#rendered_lines + 1] = ''
      end
      rendered_lines[#rendered_lines + 1] = ('### @%s · %s'):format(
        comment.author,
        display_date(comment.created_at)
      )
      if comment.html_url ~= '' then
        rendered_lines[#rendered_lines + 1] = ('[View comment](%s)'):format(comment.html_url)
      end
      rendered_lines[#rendered_lines + 1] = ''
      local comment_lines = comment.body ~= ''
          and vim.split(comment.body, '\n', { plain = true })
        or { '_No comment text._' }
      vim.list_extend(rendered_lines, comment_lines)
    end
    if not github_record.discussion_complete then
      vim.list_extend(rendered_lines, {
        '',
        ('_Showing %d of %d comments; open GitHub for the remaining discussion._'):format(
          #discussion,
          github_record.comments
        ),
      })
    end
  end
  vim.list_extend(rendered_lines, {
    '',
    '_`j`/`k`/`<C-d>`/`<C-u>` scroll · `q`/`<Space>de` returns to search · '
      .. '`<C-q>` closes detail · `za` folds Markdown sections · '
      .. '`o` opens GitHub._',
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

function M.render_buffer(buffer, github_record)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].filetype = 'markdown'
  vim.b[buffer].git_issue_number = tostring(github_record.number)
  vim.b[buffer].git_issue_url = github_record.html_url
  vim.b[buffer].git_result_source = 'REMOTE'
  set_buffer_lines(buffer, M.lines(github_record))
  treesitter.ensure_highlighting(buffer)
  M.attach_external_mappings(buffer)
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
  open_target.open_external(issue_url)
end

function M.attach_external_mappings(buffer)
  vim.keymap.set('n', 'o', function()
    open_external_url(buffer)
  end, { buffer = buffer, silent = true, desc = 'Open issue on GitHub' })
  vim.keymap.set('n', 'gx', function()
    open_external_url(buffer)
  end, { buffer = buffer, silent = true, desc = 'Open issue on GitHub' })
end

local function attach_mappings(buffer, root, fetch_related)
  vim.keymap.set('n', '<Tab>', '<Nop>', {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Ignore Tab in GitHub detail',
  })
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
    desc = 'Close GitHub detail layer',
  })
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
    fetch_related(related_issue_number, function(related_issue, issue_error)
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
        buffer_name(root, related_issue)
      )
      M.render_buffer(buffer, related_issue)
    end)
  end, { buffer = buffer, silent = true, desc = 'Open related GitHub issue' })
end

function M.open_file(root, github_record, options)
  cancel_pending_direct_request()
  close_detail(false)
  local detail_options = options or {}
  local parent_tabpage = detail_options.parent_tabpage or vim.api.nvim_get_current_tabpage()
  local parent_window = detail_options.parent_window or vim.api.nvim_get_current_win()
  local fetch_related = detail_options.fetch_related or function(issue_number, callback)
    return github.fetch_issue(root, issue_number, callback)
  end
  if parent_tabpage and vim.api.nvim_tabpage_is_valid(parent_tabpage) then
    vim.api.nvim_set_current_tabpage(parent_tabpage)
  end
  local detail_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[detail_buffer].bufhidden = 'wipe'
  vim.bo[detail_buffer].buftype = 'nofile'
  vim.bo[detail_buffer].swapfile = false
  vim.api.nvim_buf_set_name(detail_buffer, buffer_name(root, github_record))
  M.render_buffer(detail_buffer, github_record)
  local commit_shas = github_record.commit_shas or {}
  local commit_title = github_record.kind == 'Pull request'
      and #commit_shas > 0
      and (' · %s'):format(commit_shas[1]:sub(1, 12)
        .. (#commit_shas > 1 and (' +%d'):format(#commit_shas - 1) or ''))
    or ''
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
    title = (' GitHub #%d · %s%s · REMOTE '):format(
      github_record.number,
      github_record.kind:upper(),
      commit_title
    ),
    title_pos = 'center',
    width = detail_width,
  })
  attach_mappings(detail_buffer, root, fetch_related)
  vim.wo[detail_window].cursorline = true
  vim.wo[detail_window].foldenable = true
  vim.wo[detail_window].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  vim.wo[detail_window].foldlevel = 99
  vim.wo[detail_window].foldmethod = 'expr'
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

function M.open_url(target)
  local record_reference = github.parse_record_url(target)
  if not record_reference then
    return false
  end

  cancel_pending_direct_request()
  local request_generation = direct_request_generation
  local parent_tabpage = vim.api.nvim_get_current_tabpage()
  local parent_window = vim.api.nvim_get_current_win()
  local request_completed = false
  vim.notify(
    ('GitHub %s #%d: loading detail…'):format(
      record_reference.kind:lower(),
      record_reference.number
    ),
    vim.log.levels.INFO
  )
  local cancel_request = github.fetch_record(record_reference, function(github_record)
    request_completed = true
    if request_generation ~= direct_request_generation then
      return
    end
    pending_direct_request = nil
    clear_loading_message()
    if not github_record then
      open_target.open_external(target)
      return
    end
    local remote = record_reference.remote
    local function fetch_related(issue_number, callback)
      return github.fetch_record({
        number = tonumber(issue_number),
        remote = remote,
      }, callback)
    end
    M.open_file(remote.repository, github_record, {
      fetch_related = fetch_related,
      parent_tabpage = parent_tabpage,
      parent_window = parent_window,
    })
  end)
  if not request_completed then
    pending_direct_request = {
      cancel = cancel_request,
      generation = request_generation,
    }
  end
  return true
end

function M.is_active()
  return active_detail ~= nil
end

function M.close()
  local request_was_pending = pending_direct_request ~= nil
  cancel_pending_direct_request()
  return close_detail(false) or request_was_pending
end

return M
