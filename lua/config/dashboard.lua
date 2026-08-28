local M = {}
local dashboard_namespace = vim.api.nvim_create_namespace('project_dashboard')
local dashboard_states = {}
local requested_context
local requested_window_options

M.project_limit = 5
M.file_limit = 10
M.oldfile_scan_limit = 120
M.maximum_width = 96
M.minimum_width = 44
M.top_padding = 4
M.bottom_padding = 2

local brand_icon = {
  '███╗   ██╗',
  '████╗  ██║',
  '██╔██╗ ██║',
  '██║╚██╗██║',
  '██║ ╚████║',
}

local function normalized_existing_file(path)
  if type(path) ~= 'string' or path == '' then
    return
  end
  local normalized_path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  local path_stat = vim.uv.fs_stat(normalized_path)
  if not path_stat or path_stat.type ~= 'file' then
    return
  end
  return normalized_path
end

local function new_project(root)
  local project = require('config.project')
  local provider = project.repository_provider(root)
  return {
    root = root,
    name = project.name(root),
    icon = project.provider_icon(provider),
    files = {},
  }
end

local function prioritize_current_project(projects, selected_index)
  local project_count = #projects
  if project_count == 0 then
    projects.current_index = 0
    return projects
  end

  local ordered_projects = {}
  for project_offset = 0, project_count - 1 do
    local source_index = ((selected_index - 1 + project_offset) % project_count) + 1
    ordered_projects[#ordered_projects + 1] = projects[source_index]
  end
  ordered_projects.current_index = 1
  return ordered_projects
end

function M.collect(oldfiles, current_path)
  local project = require('config.project')
  local source_oldfiles = oldfiles or vim.v.oldfiles or {}
  local source_path = current_path or vim.uv.cwd()
  local current_root = source_path and project.for_path(source_path) or nil
  local projects = {}
  local projects_by_root = {}
  local seen_files = {}

  local function add_project(root)
    local normalized_root = vim.fs.normalize(root)
    local existing_project = projects_by_root[normalized_root]
    if existing_project then
      return existing_project
    end
    if #projects >= M.project_limit then
      return
    end
    local project_entry = new_project(normalized_root)
    projects[#projects + 1] = project_entry
    projects_by_root[normalized_root] = project_entry
    return project_entry
  end

  local scan_count = math.min(#source_oldfiles, M.oldfile_scan_limit)
  for oldfile_index = 1, scan_count do
    local file_path = normalized_existing_file(source_oldfiles[oldfile_index])
    if file_path and not seen_files[file_path] then
      seen_files[file_path] = true
      local project_root = project.resolve_path(file_path)
      if project_root then
        local project_entry = add_project(project_root)
        if project_entry and #project_entry.files < M.file_limit then
          project_entry.files[#project_entry.files + 1] = {
            path = file_path,
            relative_path = vim.fs.relpath(project_entry.root, file_path)
              or vim.fs.basename(file_path),
          }
        end
      end
    end
  end

  local current_project_entry = current_root and projects_by_root[current_root]
  if not current_project_entry and current_root then
    if #projects >= M.project_limit then
      local removed_project = table.remove(projects)
      projects_by_root[removed_project.root] = nil
    end
    local current_project = add_project(current_root)
    current_project_entry = current_project
  end

  local selected_index = 1
  if current_project_entry then
    for project_index, project_entry in ipairs(projects) do
      if project_entry == current_project_entry then
        selected_index = project_index
        break
      end
    end
  end
  return prioritize_current_project(projects, selected_index)
end

local function truncate_display(text, maximum_width)
  if vim.fn.strdisplaywidth(text) <= maximum_width then
    return text
  end
  if maximum_width <= 1 then
    return '…'
  end
  local truncated_text = text
  while vim.fn.strdisplaywidth(truncated_text) > maximum_width - 1 do
    local character_count = vim.fn.strchars(truncated_text)
    truncated_text = vim.fn.strcharpart(truncated_text, 0, character_count - 1)
  end
  return truncated_text .. '…'
end

local function abbreviated_path(path)
  return vim.fn.fnamemodify(path, ':~')
end

local function selected_project(state)
  return state.projects[state.project_index]
end

local function selected_files(state)
  local project_entry = selected_project(state)
  return project_entry and project_entry.files or {}
end

local function context_from_buffer(bufnr)
  local project = require('config.project')
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  if buffer_path ~= '' and vim.bo[bufnr].buftype == '' then
    local normalized_file_path = vim.fs.normalize(buffer_path)
    return {
      root = project.for_buffer(bufnr),
      file_path = normalized_file_path,
    }
  end

  local working_directory = vim.uv.cwd()
  return {
    root = project.for_path(working_directory),
  }
end

local function add_highlight(rendered, row, start_column, end_column, group)
  rendered.highlights[#rendered.highlights + 1] = {
    row = row,
    start_column = start_column,
    end_column = end_column,
    group = group,
  }
end

local function add_line(rendered, text)
  local row = #rendered.lines
  rendered.lines[#rendered.lines + 1] = text
  return row
end

local function add_centered_line(rendered, text, layout_width)
  local inner_padding = math.max(0, math.floor((layout_width - vim.fn.strdisplaywidth(text)) / 2))
  return add_line(rendered, (' '):rep(rendered.left_column + inner_padding) .. text)
end

local function render_title(rendered, layout_width)
  local brand_text = '  PROJECT DECK'
  local brand_width = vim.fn.strdisplaywidth(brand_text)
  local brand_padding = math.max(
    0,
    math.floor((layout_width - brand_width) / 2)
  )
  local brand_start = rendered.left_column + brand_padding
  local title_text = (' '):rep(brand_start) .. brand_text
  local title_row = add_line(rendered, title_text)
  add_highlight(
    rendered,
    title_row,
    brand_start,
    brand_start + #brand_text,
    'TypeInformationSection'
  )
end

local function render_active_context(rendered, state, layout_width)
  local active_context = state.context
  if not active_context or not active_context.root then
    return
  end

  local project = require('config.project')
  local provider = project.repository_provider(active_context.root)
  local project_prefix = project.provider_icon(provider) .. '  '
  local path_prefix = '󰉋  '
  local footer_left_column = rendered.left_column + 2
  local footer_width = math.max(1, layout_width - 2)
  local project_name = truncate_display(
    project.name(active_context.root),
    math.max(1, footer_width - vim.fn.strdisplaywidth(project_prefix))
  )
  local root_path = truncate_display(
    abbreviated_path(active_context.root),
    math.max(1, footer_width - vim.fn.strdisplaywidth(path_prefix))
  )

  local project_row = add_line(
    rendered,
    (' '):rep(footer_left_column) .. project_prefix .. project_name
  )
  add_highlight(
    rendered,
    project_row,
    footer_left_column,
    footer_left_column + #project_prefix,
    'TypeInformationSection'
  )
  add_highlight(
    rendered,
    project_row,
    footer_left_column + #project_prefix,
    -1,
    'TypeInformationIndex'
  )

  local path_row = add_line(
    rendered,
    (' '):rep(footer_left_column) .. path_prefix .. root_path
  )
  add_highlight(
    rendered,
    path_row,
    footer_left_column,
    footer_left_column + #path_prefix,
    'TypeInformationSection'
  )
  add_highlight(
    rendered,
    path_row,
    footer_left_column + #path_prefix,
    -1,
    'TypeInformationLocation'
  )
end

local function render_project_drawer(rendered, state, layout_width)
  local drawer_rows = { { text = '', cards = {} } }
  local project_count = #state.projects
  for project_index = 1, project_count do
    local project_entry = state.projects[project_index]
    local maximum_name_width = math.max(6, math.min(12, layout_width - 10))
    local project_name = truncate_display(project_entry.name, maximum_name_width)
    local card_text = (' %s %s '):format(project_entry.icon, project_name)
    local drawer_row = drawer_rows[#drawer_rows]
    local separator = drawer_row.text == '' and '' or '  '
    if drawer_row.text ~= ''
        and vim.fn.strdisplaywidth(drawer_row.text .. separator .. card_text) > layout_width then
      drawer_row = { text = '', cards = {} }
      drawer_rows[#drawer_rows + 1] = drawer_row
      separator = ''
    end

    local card_start = #drawer_row.text + #separator
    drawer_row.text = drawer_row.text .. separator .. card_text
    local card = {
      project_index = project_index,
      start_column = card_start,
      end_column = #drawer_row.text,
      icon_start = card_start + 1,
    }
    drawer_row.cards[#drawer_row.cards + 1] = card
  end

  for _, drawer_row in ipairs(drawer_rows) do
    local drawer_padding = math.max(
      0,
      math.floor((layout_width - vim.fn.strdisplaywidth(drawer_row.text)) / 2)
    )
    local drawer_left_column = rendered.left_column + drawer_padding
    local row = add_line(rendered, (' '):rep(drawer_left_column) .. drawer_row.text)
    for _, card in ipairs(drawer_row.cards) do
      local absolute_start = drawer_left_column + card.start_column
      local absolute_end = drawer_left_column + card.end_column
      if card.project_index == state.project_index then
        add_highlight(rendered, row, absolute_start, absolute_end, 'TypeInformationCursorLine')
      end
      add_highlight(
        rendered,
        row,
        drawer_left_column + card.icon_start,
        drawer_left_column + card.icon_start + #state.projects[card.project_index].icon,
        'TypeInformationSection'
      )
      if card.project_index == state.project_index then
        state.project_cursor = { row = row, column = absolute_start }
      end
    end
  end
end

local function file_icon(path)
  local loaded, devicons = pcall(require, 'nvim-web-devicons')
  if not loaded then
    return '󰈔', 'TypeInformationIndex'
  end
  local filename = vim.fs.basename(path)
  local extension = vim.fn.fnamemodify(filename, ':e')
  local icon, highlight = devicons.get_icon(filename, extension, { default = true })
  return icon or '󰈔', highlight or 'TypeInformationIndex'
end

local function render_files(rendered, state, layout_width, maximum_file_rows)
  local project_entry = selected_project(state)
  if not project_entry then
    local empty_row = add_line(rendered, (' '):rep(rendered.left_column) .. 'No recent projects')
    add_highlight(rendered, empty_row, 0, -1, 'TypeInformationHint')
    return
  end

  local root_label = truncate_display(abbreviated_path(project_entry.root), layout_width - 18)
  local heading = 'Recent files  ·  ' .. root_label
  local heading_row = add_line(rendered, (' '):rep(rendered.left_column) .. heading)
  add_highlight(
    rendered,
    heading_row,
    rendered.left_column,
    rendered.left_column + #'Recent files',
    'TypeInformationSection'
  )
  add_highlight(
    rendered,
    heading_row,
    rendered.left_column + #'Recent files  ',
    rendered.left_column + #'Recent files  ·  ',
    'TypeInformationSeparator'
  )
  add_highlight(
    rendered,
    heading_row,
    rendered.left_column + #'Recent files  ·  ',
    -1,
    'TypeInformationHint'
  )

  if #project_entry.files == 0 then
    if maximum_file_rows <= 0 then
      return
    end
    local empty_row = add_line(
      rendered,
      (' '):rep(rendered.left_column + 2) .. 'No recent files for this project'
    )
    add_highlight(rendered, empty_row, 0, -1, 'TypeInformationHint')
    return
  end

  if maximum_file_rows <= 0 then
    return
  end
  local maximum_start_index = math.max(1, #project_entry.files - maximum_file_rows + 1)
  local first_file_index = math.min(
    math.max(1, state.file_index - maximum_file_rows + 1),
    maximum_start_index
  )
  local last_file_index = math.min(
    #project_entry.files,
    first_file_index + maximum_file_rows - 1
  )
  for file_index = first_file_index, last_file_index do
    local file_entry = project_entry.files[file_index]
    local icon, icon_highlight = file_icon(file_entry.path)
    local prefix = ('  %d  %s  '):format(file_index, icon)
    local relative_path = truncate_display(
      file_entry.relative_path,
      math.max(8, layout_width - vim.fn.strdisplaywidth(prefix))
    )
    local row_text = (' '):rep(rendered.left_column) .. prefix .. relative_path
    local row = add_line(rendered, row_text)
    if state.mode == 'files' and file_index == state.file_index then
      add_highlight(rendered, row, rendered.left_column, -1, 'TypeInformationCursorLine')
      state.file_cursor = { row = row, column = rendered.left_column + 2 }
    end
    add_highlight(
      rendered,
      row,
      rendered.left_column + 2,
      rendered.left_column + 2 + #tostring(file_index),
      'TypeInformationIndex'
    )
    local icon_start = rendered.left_column + #(('  %d  '):format(file_index))
    add_highlight(rendered, row, icon_start, icon_start + #icon, icon_highlight)
    local path_start = rendered.left_column + #prefix
    add_highlight(rendered, row, path_start, -1, 'TypeInformationLocation')
  end
end

function M.footer_padding(content_line_count, window_height, footer_line_count)
  local target_footer_row = window_height - M.bottom_padding - footer_line_count
  local content_end_row = content_line_count + M.top_padding
  return math.max(0, target_footer_row - content_end_row)
end

local function build_render(state)
  local window_width = vim.api.nvim_win_is_valid(state.winid)
      and vim.api.nvim_win_get_width(state.winid)
    or vim.o.columns
  local window_height = vim.api.nvim_win_is_valid(state.winid)
      and vim.api.nvim_win_get_height(state.winid)
    or math.max(1, vim.o.lines - 2)
  local available_width = math.max(1, window_width - 6)
  local layout_width = math.min(M.maximum_width, available_width)
  local rendered = {
    lines = {},
    highlights = {},
    left_column = math.max(0, math.floor((window_width - layout_width) / 2)),
  }

  for _, icon_line in ipairs(brand_icon) do
    local icon_row = add_centered_line(rendered, icon_line, layout_width)
    add_highlight(rendered, icon_row, 0, -1, 'TypeInformationSection')
  end
  add_line(rendered, '')
  render_title(rendered, layout_width)
  local separator_row = add_line(
    rendered,
    (' '):rep(rendered.left_column) .. ('─'):rep(math.max(1, layout_width))
  )
  add_highlight(rendered, separator_row, 0, -1, 'TypeInformationSeparator')
  add_line(rendered, '')

  local visible_project_index = math.min(state.project_index, #state.projects)
  local project_heading = ('Recent projects  ‹ %d/%d ›'):format(
    visible_project_index,
    #state.projects
  )
  local project_heading_row = add_line(
    rendered,
    (' '):rep(rendered.left_column) .. project_heading
  )
  add_highlight(
    rendered,
    project_heading_row,
    rendered.left_column,
    rendered.left_column + #'Recent projects',
    'TypeInformationSection'
  )
  add_highlight(
    rendered,
    project_heading_row,
    rendered.left_column + #'Recent projects  ',
    -1,
    'TypeInformationHint'
  )
  render_project_drawer(rendered, state, layout_width)
  add_line(rendered, '')
  local has_active_context = state.context ~= nil and state.context.root ~= nil
  local footer_line_count = has_active_context and 4 or 1
  local reserved_bottom_lines = M.top_padding
    + M.bottom_padding
    + footer_line_count
    + 1
  local file_section_capacity = math.max(
    0,
    window_height - #rendered.lines - reserved_bottom_lines
  )
  if file_section_capacity > 0 then
    render_files(rendered, state, layout_width, file_section_capacity - 1)
  end
  local footer_padding = M.footer_padding(
    #rendered.lines,
    window_height,
    footer_line_count
  )
  for _ = 1, footer_padding do
    add_line(rendered, '')
  end
  render_active_context(rendered, state, layout_width)
  if has_active_context then
    add_line(rendered, '')
  end

  local hint = 'h/l project  ·  j/k file  ·  <Enter> activate/open  ·  q close'
  local hint_row = add_centered_line(rendered, truncate_display(hint, layout_width), layout_width)
  add_highlight(rendered, hint_row, 0, -1, 'TypeInformationHint')
  for _ = 1, M.bottom_padding do
    add_line(rendered, '')
  end

  local vertical_padding = M.top_padding
  for _ = 1, vertical_padding do
    table.insert(rendered.lines, 1, '')
  end
  for _, highlight in ipairs(rendered.highlights) do
    highlight.row = highlight.row + vertical_padding
  end
  if state.project_cursor then
    state.project_cursor.row = state.project_cursor.row + vertical_padding
  end
  if state.file_cursor then
    state.file_cursor.row = state.file_cursor.row + vertical_padding
  end
  return rendered
end

local function render(state)
  if not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end
  state.project_cursor = nil
  state.file_cursor = nil
  local rendered = build_render(state)
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, rendered.lines)
  vim.api.nvim_buf_clear_namespace(state.bufnr, dashboard_namespace, 0, -1)
  for _, highlight in ipairs(rendered.highlights) do
    vim.api.nvim_buf_add_highlight(
      state.bufnr,
      dashboard_namespace,
      highlight.group,
      highlight.row,
      highlight.start_column,
      highlight.end_column
    )
  end
  vim.bo[state.bufnr].modifiable = false
  vim.bo[state.bufnr].modified = false

  local winid = vim.fn.bufwinid(state.bufnr)
  local target_cursor = state.mode == 'files' and state.file_cursor or state.project_cursor
  if winid ~= -1 and target_cursor then
    vim.api.nvim_win_set_cursor(winid, { target_cursor.row + 1, target_cursor.column })
  end
end

local function schedule_initial_render(state)
  vim.schedule(function()
    if dashboard_states[state.bufnr] ~= state then
      return
    end
    if not vim.api.nvim_buf_is_valid(state.bufnr) then
      return
    end
    render(state)
  end)
end

function M.activate_project(project_path)
  local project_root = require('config.project').for_path(project_path)
  vim.cmd('lcd ' .. vim.fn.fnameescape(project_root))
  return project_root
end

local function open_selected_file(state)
  local project_entry = selected_project(state)
  local file_entry = project_entry and project_entry.files[state.file_index]
  if not project_entry or not file_entry then
    return
  end
  vim.cmd('lcd ' .. vim.fn.fnameescape(project_entry.root))
  vim.cmd('edit ' .. vim.fn.fnameescape(file_entry.path))
end

local function open_selection(state)
  if state.mode == 'files' then
    open_selected_file(state)
    return
  end
  local project_entry = selected_project(state)
  if project_entry then
    local activated_root = M.activate_project(project_entry.root)
    state.context = { root = activated_root }
    render(state)
  end
end

local function move_project(state, offset)
  if #state.projects == 0 then
    return
  end
  state.project_index = ((state.project_index - 1 + offset) % #state.projects) + 1
  state.file_index = 1
  render(state)
end

local function move_file(state, offset)
  local files = selected_files(state)
  if #files == 0 then
    state.mode = 'projects'
    render(state)
    return
  end
  if state.mode == 'projects' then
    if offset > 0 then
      state.mode = 'files'
      state.file_index = 1
    end
  else
    local next_index = state.file_index + offset
    if next_index < 1 then
      state.mode = 'projects'
      state.file_index = 1
    else
      state.file_index = math.min(next_index, #files)
    end
  end
  render(state)
end

local function capture_window_options(winid)
  return {
    breakindent = vim.wo[winid].breakindent,
    colorcolumn = vim.wo[winid].colorcolumn,
    cursorcolumn = vim.wo[winid].cursorcolumn,
    cursorline = vim.wo[winid].cursorline,
    foldcolumn = vim.wo[winid].foldcolumn,
    list = vim.wo[winid].list,
    number = vim.wo[winid].number,
    relativenumber = vim.wo[winid].relativenumber,
    signcolumn = vim.wo[winid].signcolumn,
    spell = vim.wo[winid].spell,
    wrap = vim.wo[winid].wrap,
  }
end

local function configured_window_options()
  return {
    breakindent = vim.go.breakindent,
    colorcolumn = vim.go.colorcolumn,
    cursorcolumn = vim.go.cursorcolumn,
    cursorline = vim.go.cursorline,
    foldcolumn = vim.go.foldcolumn,
    list = vim.go.list,
    number = vim.go.number,
    relativenumber = vim.go.relativenumber,
    signcolumn = vim.go.signcolumn,
    spell = vim.go.spell,
    wrap = vim.go.wrap,
  }
end

local function restore_window_options(winid, window_options)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].breakindent = window_options.breakindent
  vim.wo[winid].colorcolumn = window_options.colorcolumn
  vim.wo[winid].cursorcolumn = window_options.cursorcolumn
  vim.wo[winid].cursorline = window_options.cursorline
  vim.wo[winid].foldcolumn = window_options.foldcolumn
  vim.wo[winid].list = window_options.list
  vim.wo[winid].number = window_options.number
  vim.wo[winid].relativenumber = window_options.relativenumber
  vim.wo[winid].signcolumn = window_options.signcolumn
  vim.wo[winid].spell = window_options.spell
  vim.wo[winid].wrap = window_options.wrap
end

local function close_dashboard(state)
  restore_window_options(state.winid, state.original_window_options)
  if vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
end

local function map_buffer(state, lhs, callback, description)
  vim.keymap.set('n', lhs, callback, {
    buffer = state.bufnr,
    nowait = true,
    silent = true,
    desc = description,
  })
end

local function attach_mappings(state)
  for _, lhs in ipairs({ 'h', '<Left>' }) do
    map_buffer(state, lhs, function()
      move_project(state, -1)
    end, 'Dashboard: previous project')
  end
  for _, lhs in ipairs({ 'l', '<Right>' }) do
    map_buffer(state, lhs, function()
      move_project(state, 1)
    end, 'Dashboard: next project')
  end
  for _, lhs in ipairs({ 'j', '<Down>' }) do
    map_buffer(state, lhs, function()
      move_file(state, 1)
    end, 'Dashboard: next file')
  end
  for _, lhs in ipairs({ 'k', '<Up>' }) do
    map_buffer(state, lhs, function()
      move_file(state, -1)
    end, 'Dashboard: previous file')
  end
  map_buffer(state, '<CR>', function()
    open_selection(state)
  end, 'Dashboard: open selection')
  map_buffer(state, 'q', function()
    close_dashboard(state)
  end, 'Dashboard: close')
end

local function configure_buffer(bufnr, winid)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].filetype = 'dashboard'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.wo[winid].breakindent = false
  vim.wo[winid].colorcolumn = ''
  vim.wo[winid].cursorcolumn = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].foldcolumn = '0'
  vim.wo[winid].list = false
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].spell = false
  vim.wo[winid].wrap = false
end

function M.attach(bufnr, winid, projects, context)
  local current_state = dashboard_states[bufnr]
  if current_state then
    render(current_state)
    return bufnr
  end

  local original_window_options = requested_window_options or configured_window_options()
  requested_window_options = nil
  configure_buffer(bufnr, winid)
  local dashboard_context = context or requested_context or context_from_buffer(bufnr)
  requested_context = nil
  local context_path = dashboard_context.file_path or dashboard_context.root
  local dashboard_projects = projects or M.collect(nil, context_path)
  local state = {
    bufnr = bufnr,
    winid = winid,
    original_window_options = original_window_options,
    projects = dashboard_projects,
    project_index = #dashboard_projects > 0 and (dashboard_projects.current_index or 1) or 0,
    file_index = 1,
    mode = 'projects',
    context = dashboard_context,
  }
  dashboard_states[bufnr] = state
  attach_mappings(state)
  schedule_initial_render(state)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    once = true,
    callback = function()
      dashboard_states[bufnr] = nil
    end,
    desc = 'Release project dashboard state',
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      restore_window_options(winid, original_window_options)
    end,
    desc = 'Restore window options after leaving project dashboard',
  })
  return bufnr
end

function M.options()
  return {
    theme = 'project',
    config = {},
  }
end

function M.open()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()
  requested_context = context_from_buffer(current_buffer)
  requested_window_options = capture_window_options(current_window)
  vim.cmd('Dashboard')
end

return M
