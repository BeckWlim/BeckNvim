local M = {}
local preview_namespace = vim.api.nvim_create_namespace('folder_picker_preview')

M.folder_limit = 500
M.scan_limit = 2000
M.maximum_width = 76
M.maximum_height = 18
M.minimum_width = 36
M.minimum_height = 6
M.search_root = '/'
M.maximum_search_results = 1000
M.maximum_preview_entries = 5000

local function abbreviated_path(path)
  return vim.fn.fnamemodify(path, ':~')
end

local function folder_entry(path, label, kind)
  local normalized_path = vim.fs.normalize(path)
  return {
    display = ('󰉋  %s'):format(label),
    kind = kind,
    ordinal = label .. ' ' .. normalized_path,
    path = normalized_path,
    value = normalized_path,
  }
end

local function display_path(path)
  return vim.fn.fnamemodify(path, ':~')
end

local function search_entry(path, shortcut)
  local normalized_path = vim.fs.normalize(path)
  local label = display_path(normalized_path)
  return {
    display = shortcut and ('%s  %s'):format(shortcut, label)
      or ('󰉋  %s'):format(label),
    kind = shortcut and 'shortcut' or 'directory',
    ordinal = label .. ' ' .. normalized_path,
    path = normalized_path,
    value = normalized_path,
    shortcut = shortcut,
  }
end

local project_metadata_cache = {}

local function project_metadata(path)
  local normalized_path = vim.fs.normalize(path)
  local cached_metadata = project_metadata_cache[normalized_path]
  if cached_metadata then
    return cached_metadata
  end
  local project = require('config.project')
  local detected_root = project.resolve_path(normalized_path)
  local project_root = detected_root or normalized_path
  local metadata = {
    icon = project.provider_icon(project.repository_provider(project_root)),
    name = project.name(project_root),
    branch = detected_root and project.branch_name(detected_root) or nil,
  }
  project_metadata_cache[normalized_path] = metadata
  return metadata
end

local function project_displayer()
  local entry_display = require('telescope.pickers.entry_display')
  local displayer = entry_display.create({
    separator = '  ',
    items = {
      { width = 2 },
      -- The project icon is the first part's leading marker. Keep the three
      -- text columns independent so branch text never shifts the path.
      { width = 0.30 },
      { width = 0.18 },
      -- Paths are usually the longest value, so reserve about half the row
      -- for them while keeping their text aligned from the column's left edge.
      { width = 0.50 },
    },
  })
  return function(entry)
    local annotation = display_path(entry.path)
    if entry.shortcut then
      return displayer({
        { entry.shortcut, 'TelescopeResultsIdentifier' },
        { '', 'TelescopeResultsComment' },
        { '', 'TelescopeResultsComment' },
        { annotation, 'TelescopeResultsComment' },
      })
    end
    local metadata = project_metadata(entry.path)
    local branch_annotation = ' ' .. (metadata.branch or '<None>')
    return displayer({
      { metadata.icon, 'TelescopeResultsIdentifier' },
      { metadata.name, 'TelescopeResultsIdentifier' },
      { branch_annotation, 'TelescopeResultsComment' },
      { annotation, 'TelescopeResultsComment' },
    })
  end
end

local function find_arguments(root, query, direct_children)
  local pattern = '*' .. query .. '*'
  return {
    root,
    '-xdev',
    '-mindepth', '1',
    '-maxdepth', direct_children and '1' or '12',
    '(',
      '-path', '*/.git',
      '-o', '-path', '*/node_modules',
      '-o', '-path', '*/.cache',
      '-o', '-path', '*/.venv',
      '-o', '-path', '*/vendor',
      '-o', '-path', '*/build',
    ')',
    '-prune',
    '-o',
    '-type', 'd',
    '(', '-iname', pattern, '-o', '-path', pattern, ')',
    '-print',
  }
end

local function search_scope(search_root, prompt)
  local normalized_prompt = vim.trim(prompt or '')
  local is_path_query = normalized_prompt:find('/', 1, true) ~= nil
    or normalized_prompt:sub(1, 1) == '~'
    or normalized_prompt:sub(1, 1) == '.'
  if not is_path_query then
    return search_root, normalized_prompt
  end

  local expanded_prompt = normalized_prompt:sub(1, 1) == '~'
      and vim.fn.expand(normalized_prompt)
    or normalized_prompt
  local absolute_prompt = expanded_prompt:sub(1, 1) == '/'
      and expanded_prompt
    or vim.fs.joinpath(vim.uv.cwd(), expanded_prompt)
  local normalized_path = vim.fs.normalize(absolute_prompt)
  local path_stat = vim.uv.fs_stat(normalized_path)
  if path_stat and path_stat.type == 'directory' then
    return normalized_path, '', true
  end

  local parent_path = vim.fs.dirname(normalized_path)
  local parent_stat = vim.uv.fs_stat(parent_path)
  if parent_stat and parent_stat.type == 'directory' then
    return parent_path, vim.fs.basename(normalized_path), false
  end
  return search_root, normalized_prompt, false
end

M.search_scope = search_scope

local function project_finder(root, initial_entries, displayer)
  local generation = 0
  local active_job
  local finder = {}

  local function cancel()
    generation = generation + 1
    if active_job and not active_job.is_shutdown then
      active_job:shutdown()
    end
    active_job = nil
  end

  finder.close = cancel
  return setmetatable(finder, {
    __call = function(_, prompt, process_result, process_complete)
      cancel()
      local active_generation = generation
      local normalized_prompt = vim.trim(prompt or '')
      if normalized_prompt == '' then
        for _, entry in ipairs(initial_entries) do
          process_result(entry)
        end
        process_complete()
        return
      end

      local scoped_root, scoped_query, direct_children = search_scope(root, normalized_prompt)
      local Job = require('plenary.job')
      local received_count = 0
      active_job = Job:new({
        command = 'find',
        args = find_arguments(scoped_root, scoped_query, direct_children),
        enable_recording = false,
        on_stdout = function(_, line)
          if generation ~= active_generation or received_count >= M.maximum_search_results
              or not line or line == '' then
            return
          end
          received_count = received_count + 1
          local entry = search_entry(line)
          entry.display = displayer
          vim.schedule(function()
            if generation == active_generation then
              process_result(entry)
            end
          end)
          if received_count == M.maximum_search_results then
            vim.schedule(function()
              if generation == active_generation and active_job then
                active_job:shutdown()
              end
            end)
          end
        end,
        on_exit = function()
          vim.schedule(function()
            if generation == active_generation then
              active_job = nil
              process_complete()
            end
          end)
        end,
      })
      active_job:start()
    end,
  })
end

local function tree_record(record)
  local kind, relative_path = record:match('^([fdl])\t(.*)$')
  if not relative_path then
    kind, relative_path = 'f', record
  end
  return kind, relative_path:gsub('\\', '/')
end

function M.project_tree_lines(root, records)
  local normalized_root = vim.fs.normalize(root)
  local sorted_records = vim.deepcopy(records or {})
  table.sort(sorted_records, function(left, right)
    return left:lower() < right:lower()
  end)
  local lines = { ('󰉋  %s'):format(display_path(normalized_root)), '' }
  for _, record in ipairs(sorted_records) do
    local kind, relative_path = tree_record(record)
    local depth = select(2, relative_path:gsub('/', ''))
    local icon = kind == 'd' and '󰉋' or '󰈔'
    lines[#lines + 1] = ('  '):rep(depth) .. icon .. '  ' .. relative_path:match('[^/]+$')
  end
  if #lines == 2 then
    lines[#lines + 1] = '  (empty folder)'
  end
  return lines
end

local function tree_children_arguments(root)
  return {
    root,
    '-xdev',
    '-mindepth', '1',
    '-maxdepth', '1',
    '-printf', '%y\t%p\n',
  }
end

local function parse_tree_child(record)
  local kind, path = record:match('^([fdl])\t(.+)$')
  if not path then
    return
  end
  return {
    kind = kind,
    name = vim.fs.basename(path),
    path = vim.fs.normalize(path),
  }
end

local function sort_tree_children(children)
  table.sort(children, function(left, right)
    if left.kind ~= right.kind then
      return left.kind == 'd'
    end
    return left.name:lower() < right.name:lower()
  end)
end

local function project_tree_previewer()
  local previewers = require('telescope.previewers')
  local preview_request
  local active_job
  local session
  local function cancel()
    preview_request = nil
    session = nil
    if active_job and not active_job.is_shutdown then
      active_job:shutdown()
    end
    active_job = nil
  end
  local previewer = previewers.new_buffer_previewer({
    title = 'Project tree',
    teardown = cancel,
    dyn_title = function(_, entry)
      return entry and display_path(entry.value) or 'Project tree'
    end,
    define_preview = function(previewer, entry)
      cancel()
      local request = {}
      preview_request = request
      local preview_buffer = previewer.state.bufnr
      local root = entry and entry.value
      if not root or not vim.api.nvim_buf_is_valid(preview_buffer) then
        return
      end
      session = {
        request = request,
        root = vim.fs.normalize(root),
        preview_buffer = preview_buffer,
        expanded = {},
        children = {},
        loading = {},
        rows = {},
      }
      local filetree = require('config.ui.filetree')

      local function render_tree()
        if preview_request ~= request or not vim.api.nvim_buf_is_valid(preview_buffer) then
          return
        end
        local lines = { ('  %s'):format(display_path(root)), '' }
        local highlights = {}
        local rows = {}
        local function append_children(parent, depth)
          local parent_children = session.children[parent] or {}
          for _, child in ipairs(parent_children) do
            local row = #lines
            local is_expanded = session.expanded[child.path] == true
            local child_nodes = session.children[child.path]
            local has_children = child.kind == 'd'
              and (not child_nodes or #child_nodes > 0)
            local glyph, highlight_group = filetree.preview_node_icon(
              child.name,
              child.kind,
              is_expanded,
              has_children
            )
            lines[#lines + 1] = ('  '):rep(depth) .. glyph .. '  ' .. child.name
            highlights[#highlights + 1] = {
              row = #lines - 1,
              start_column = depth * 2,
              end_column = depth * 2 + #glyph,
              group = highlight_group,
            }
            rows[row + 1] = child
            if child.kind == 'd' and is_expanded then
              if session.loading[child.path] then
                lines[#lines + 1] = ('  '):rep(depth + 1) .. '  Loading…'
              else
                append_children(child.path, depth + 1)
              end
            end
          end
        end
        append_children(session.root, 0)
        if #lines == 2 then
          lines[#lines + 1] = '  (empty folder)'
        end
        session.rows = rows
        vim.bo[preview_buffer].modifiable = true
        vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(preview_buffer, preview_namespace, 0, -1)
        for _, highlight in ipairs(highlights) do
          vim.api.nvim_buf_add_highlight(
            preview_buffer,
            preview_namespace,
            highlight.group,
            highlight.row,
            highlight.start_column,
            highlight.end_column
          )
        end
        vim.bo[preview_buffer].modifiable = false
        vim.bo[preview_buffer].filetype = 'text'
      end

      local function load_children(folder_path, callback)
        if preview_request ~= request then
          return
        end
        session.loading[folder_path] = true
        render_tree()
        local records = {}
        local Job = require('plenary.job')
        active_job = Job:new({
          command = 'find',
          args = tree_children_arguments(folder_path),
          cwd = folder_path,
          enable_recording = false,
          on_stdout = function(_, line)
            if preview_request ~= request or #records >= M.maximum_preview_entries
                or not line or line == '' then
              return
            end
            records[#records + 1] = line
          end,
          on_exit = function()
            vim.schedule(function()
              if preview_request ~= request then
                return
              end
              local children = {}
              for _, record in ipairs(records) do
                local child = parse_tree_child(record)
                if child then
                  children[#children + 1] = child
                end
              end
              sort_tree_children(children)
              session.children[folder_path] = children
              session.loading[folder_path] = nil
              active_job = nil
              render_tree()
              if callback then
                callback()
              end
            end)
          end,
        })
        active_job:start()
      end

      previewer.toggle_folder = function(prompt_buffer)
        if not session or session.request ~= request or session.prompt_buffer ~= prompt_buffer then
          return
        end
        local preview_window = previewer.state.winid
        if not preview_window or not vim.api.nvim_win_is_valid(preview_window) then
          return
        end
        local cursor_row = vim.api.nvim_win_get_cursor(preview_window)[1]
        local selected_child = session.rows[cursor_row]
        if not selected_child or selected_child.kind ~= 'd' then
          return
        end
        local selected_path = selected_child.path
        if session.expanded[selected_path] then
          session.expanded[selected_path] = nil
          render_tree()
          return
        end
        session.expanded[selected_path] = true
        if session.children[selected_path] then
          render_tree()
        else
          load_children(selected_path)
        end
      end

      session.prompt_buffer = previewer.prompt_buffer
      render_tree()
      load_children(session.root)
    end,
  })
  return previewer
end

function M.entries(root)
  local normalized_root = vim.fs.normalize(root)
  local entries = {
    folder_entry(normalized_root, '.  ' .. abbreviated_path(normalized_root), 'current'),
  }
  local parent_root = vim.fs.dirname(normalized_root)
  if parent_root ~= normalized_root then
    entries[#entries + 1] = folder_entry(parent_root, '..', 'parent')
  end

  local child_directories = {}
  local scan_handle = vim.uv.fs_scandir(normalized_root)
  local scanned_entry_count = 0
  if scan_handle then
    while #child_directories < M.folder_limit and scanned_entry_count < M.scan_limit do
      local child_name, child_type = vim.uv.fs_scandir_next(scan_handle)
      if not child_name then
        break
      end
      scanned_entry_count = scanned_entry_count + 1
      local child_path = vim.fs.joinpath(normalized_root, child_name)
      local child_stat = child_type == 'directory' and { type = 'directory' }
        or vim.uv.fs_stat(child_path)
      if child_name ~= '.git' and child_stat and child_stat.type == 'directory' then
        child_directories[#child_directories + 1] = {
          name = child_name,
          path = child_path,
        }
      end
    end
  end
  table.sort(child_directories, function(left_directory, right_directory)
    return left_directory.name:lower() < right_directory.name:lower()
  end)
  for _, child_directory in ipairs(child_directories) do
    entries[#entries + 1] = folder_entry(
      child_directory.path,
      child_directory.name .. '/',
      'directory'
    )
  end
  return entries
end

function M.layout(entries, title, columns, lines)
  local available_width = math.max(1, columns - 4)
  local available_height = math.max(1, lines - 4)
  local content_width = vim.fn.strdisplaywidth(title)
  for _, entry in ipairs(entries) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(entry.display))
  end
  local desired_width = math.max(M.minimum_width, content_width + 4)
  local desired_height = math.max(M.minimum_height, #entries + 4)
  return {
    width = math.min(M.maximum_width, available_width, desired_width),
    height = math.min(M.maximum_height, available_height, desired_height),
  }
end

function M.query(input_text, current_root)
  local normalized_input = vim.trim(input_text or '')
  local normalized_current_root = vim.fs.normalize(current_root)
  local is_path_query = normalized_input:find('/', 1, true) ~= nil
    or normalized_input:sub(1, 1) == '~'
    or normalized_input == '.'
    or normalized_input == '..'
  if normalized_input == '' or not is_path_query then
    return {
      directory = normalized_current_root,
      leaf = '',
      path_query = false,
    }
  end

  local expanded_input = vim.fn.expand(normalized_input)
  local absolute_input = expanded_input:sub(1, 1) == '/'
      and expanded_input
    or vim.fs.joinpath(normalized_current_root, expanded_input)
  local normalized_path = vim.fs.normalize(absolute_input)
  local path_stat = vim.uv.fs_stat(normalized_path)
  if normalized_input:sub(-1) == '/' and path_stat and path_stat.type == 'directory' then
    return {
      directory = normalized_path,
      leaf = '',
      path_query = true,
    }
  end
  return {
    directory = vim.fs.dirname(normalized_path),
    leaf = vim.fs.basename(normalized_path),
    path_query = true,
  }
end

function M.existing_path(input_text, current_root)
  local normalized_input = vim.trim(input_text or '')
  if normalized_input == '' then
    return
  end
  local expanded_input = vim.fn.expand(normalized_input)
  local absolute_input = expanded_input:sub(1, 1) == '/'
      and expanded_input
    or vim.fs.joinpath(current_root, expanded_input)
  local normalized_path = vim.fs.normalize(absolute_input)
  local path_stat = vim.uv.fs_stat(normalized_path)
  if path_stat and path_stat.type == 'directory' then
    return normalized_path
  end
end

function M.completion_prefix(input_text, selected_path, current_root)
  if type(selected_path) ~= 'string' or selected_path == '' then
    return
  end
  local normalized_input = vim.trim(input_text or '')
  local normalized_current_root = vim.fs.normalize(current_root)
  local normalized_selected_path = vim.fs.normalize(selected_path)
  local completion_path
  if normalized_input:sub(1, 1) == '/' then
    completion_path = normalized_selected_path
  elseif normalized_input:sub(1, 1) == '~' then
    completion_path = abbreviated_path(normalized_selected_path)
  elseif normalized_selected_path == normalized_current_root then
    completion_path = '.'
  elseif normalized_selected_path == vim.fs.dirname(normalized_current_root) then
    completion_path = '..'
  else
    local exact_input_path = M.existing_path(normalized_input, normalized_current_root)
    if exact_input_path == normalized_selected_path then
      completion_path = normalized_input
    else
      local input_prefix = normalized_input:match('^(.*[/])[^/]*$') or ''
      completion_path = input_prefix .. vim.fs.basename(normalized_selected_path)
    end
  end
  if completion_path:sub(-1) == '/' then
    return completion_path
  end
  return completion_path .. '/'
end

function M.open(options)
  local picker_options = options or {}
  local starting_directory = vim.fs.normalize(
    picker_options.starting_directory or vim.uv.cwd()
  )
  local search_root = vim.fs.normalize(picker_options.search_root or M.search_root)
  local displayer = project_displayer()
  local initial_entries = { search_entry(starting_directory, '.') }
  initial_entries[1].display = displayer
  local parent_directory = vim.fs.dirname(starting_directory)
  if parent_directory ~= starting_directory then
    initial_entries[#initial_entries + 1] = search_entry(parent_directory, '..')
    initial_entries[2].display = displayer
  end
  local pickers = require('telescope.pickers')
  local telescope_config = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local picker
  local prompt_title = picker_options.prompt_title or 'Switch Project'
  local previewer = project_tree_previewer()

  picker = pickers.new({ cwd = search_root }, {
    prompt_title = prompt_title,
    finder = project_finder(search_root, initial_entries, displayer),
    previewer = previewer,
    sorter = telescope_config.generic_sorter({ cwd = search_root }),
    attach_mappings = function(prompt_buffer, map)
      previewer.prompt_buffer = prompt_buffer
      picker.preview_enter_action = function(active_prompt_buffer)
        if previewer.toggle_folder then
          previewer.toggle_folder(active_prompt_buffer)
        end
      end
      actions.select_default:replace(function()
        local selected_entry = action_state.get_selected_entry()
        if not selected_entry or not selected_entry.value then
          vim.notify('Select a folder to switch projects', vim.log.levels.INFO)
          return
        end
        if selected_entry.shortcut then
          picker:set_prompt(display_path(selected_entry.value))
          return
        end
        actions.close(prompt_buffer)
        if picker_options.on_select then
          picker_options.on_select(selected_entry.value)
        end
      end)
      if picker_options.on_close then
        vim.api.nvim_create_autocmd('BufWipeout', {
          buffer = prompt_buffer,
          once = true,
          callback = function()
            vim.schedule(picker_options.on_close)
          end,
          desc = 'Release project picker',
        })
      end
      return true
    end,
  })
  picker:find()
  return picker
end

function M.open_project(options)
  local source_buffer = vim.api.nvim_get_current_buf()
  local picker_options = vim.tbl_extend('force', {
    prompt_title = 'Switch Project',
    on_select = function(path)
      local dashboard = require('config.ui.dashboard')
      dashboard.activate_folder(path, source_buffer)
    end,
  }, options or {})
  return M.open(picker_options)
end

return M
