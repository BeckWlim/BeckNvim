local M = {}

local preview_namespace = vim.api.nvim_create_namespace('contextual-grep-preview')

local function context_winbar(context_labels)
  if #context_labels == 0 then
    return ''
  end

  local escaped_labels = {}
  for label_index, context_label in ipairs(context_labels) do
    escaped_labels[label_index] = context_label:gsub('%%', '%%%%')
  end
  local separator = '%#TreesitterContextPreviewSeparator#  ›  '
    .. '%#TreesitterContextPreview#'
  return '%#TreesitterContextPreview#  ' .. table.concat(escaped_labels, separator) .. ' '
end

local function context_winhighlight(current_winhighlight)
  local retained_mappings = {}
  for highlight_mapping in current_winhighlight:gmatch('[^,]+') do
    local source_group = highlight_mapping:match('^([^:]+):')
    if source_group ~= 'WinBar' and source_group ~= 'WinBarNC' then
      retained_mappings[#retained_mappings + 1] = highlight_mapping
    end
  end
  retained_mappings[#retained_mappings + 1] = 'WinBar:TreesitterContextPreview'
  retained_mappings[#retained_mappings + 1] = 'WinBarNC:TreesitterContextPreview'
  return table.concat(retained_mappings, ',')
end

local function update_context_winbar(preview_window, preview_buffer, target_line)
  if not vim.api.nvim_win_is_valid(preview_window)
    or not vim.api.nvim_buf_is_valid(preview_buffer)
    or vim.api.nvim_win_get_buf(preview_window) ~= preview_buffer
  then
    return
  end

  local source_line = vim.api.nvim_buf_get_lines(
    preview_buffer,
    target_line - 1,
    target_line,
    false
  )[1] or ''
  local first_nonblank_byte = source_line:find('%S') or 1
  local context_labels = require('config.syntax.treesitter_context').structural_context_labels(
    preview_buffer,
    target_line - 1,
    first_nonblank_byte - 1
  )
  vim.wo[preview_window].winbar = context_winbar(context_labels)
  vim.wo[preview_window].winhighlight = context_winhighlight(
    vim.wo[preview_window].winhighlight
  )
end

local function show_entry(previewer, preview_buffer, entry)
  local preview_window = previewer.state.winid
  if not preview_window
    or not entry.lnum
    or entry.lnum <= 0
    or not vim.api.nvim_win_is_valid(preview_window)
    or vim.api.nvim_win_get_buf(preview_window) ~= preview_buffer
  then
    return
  end

  vim.api.nvim_buf_clear_namespace(preview_buffer, preview_namespace, 0, -1)
  local first_line = entry.lnum - 1
  local final_line = (entry.lnend or entry.lnum) - 1
  local first_column = 0
  local final_column = -1
  if entry.col and entry.colend then
    first_column = entry.col - 1
    final_column = entry.colend - 1
  end
  for line_number = first_line, final_line do
    vim.hl.range(
      preview_buffer,
      preview_namespace,
      'TelescopePreviewLine',
      { line_number, line_number == first_line and first_column or 0 },
      { line_number, line_number == final_line and final_column or -1 }
    )
  end

  local middle_line = math.floor(first_line + (final_line - first_line) / 2) + 1
  pcall(vim.api.nvim_win_set_cursor, preview_window, { middle_line, 0 })
  vim.api.nvim_win_call(preview_window, function()
    vim.cmd('normal! zz')
  end)
  update_context_winbar(preview_window, preview_buffer, middle_line)
end

function M.new(options)
  local preview_options = options or {}
  local previewers = require('telescope.previewers')
  local telescope_config = require('telescope.config').values
  local from_entry = require('telescope.from_entry')
  local Path = require('plenary.path')
  local working_directory = preview_options.cwd or vim.uv.cwd()

  if preview_options.source_buffer then
    local source_buffer = preview_options.source_buffer
    local source_filename = preview_options.source_filename
      or vim.api.nvim_buf_get_name(source_buffer)
    return previewers.new_buffer_previewer({
      title = 'Source Preview',
      dyn_title = function()
        return Path:new(source_filename):normalize(working_directory)
      end,
      get_buffer_by_name = function()
        return ('git-history-symbols://%d/%s'):format(source_buffer, source_filename)
      end,
      define_preview = function(previewer, entry)
        if not vim.api.nvim_buf_is_valid(source_buffer) then
          return
        end
        local preview_buffer = previewer.state.bufnr
        local source_changedtick = vim.api.nvim_buf_get_changedtick(source_buffer)
        local preview_matches_source = vim.b[preview_buffer].git_history_source_buffer
            == source_buffer
          and vim.b[preview_buffer].git_history_source_changedtick == source_changedtick
        if not preview_matches_source then
          local source_lines = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
          vim.bo[preview_buffer].modifiable = true
          vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, source_lines)
          vim.bo[preview_buffer].filetype = vim.bo[source_buffer].filetype
          vim.bo[preview_buffer].modifiable = false
          vim.b[preview_buffer].git_history_source_buffer = source_buffer
          vim.b[preview_buffer].git_history_source_changedtick = source_changedtick
        end
        vim.schedule(function()
          show_entry(previewer, preview_buffer, entry)
        end)
      end,
    })
  end

  return previewers.new_buffer_previewer({
    title = 'Source Preview',
    dyn_title = function(_, entry)
      return Path:new(from_entry.path(entry, false, false)):normalize(working_directory)
    end,
    get_buffer_by_name = function(_, entry)
      return from_entry.path(entry, false, false)
    end,
    define_preview = function(previewer, entry)
      local entry_path = from_entry.path(entry, true, false)
      if not entry_path or entry_path == '' then
        return
      end

      telescope_config.buffer_previewer_maker(entry_path, previewer.state.bufnr, {
        bufname = previewer.state.bufname,
        winid = previewer.state.winid,
        preview = preview_options.preview,
        file_encoding = preview_options.file_encoding,
        callback = function(preview_buffer)
          vim.schedule(function()
            show_entry(previewer, preview_buffer, entry)
          end)
        end,
      })
    end,
  })
end

M.context_winbar = context_winbar
M.context_winhighlight = context_winhighlight

return M
