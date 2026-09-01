local M = {}

M.folder_limit = 500
M.scan_limit = 2000
M.maximum_width = 76
M.maximum_height = 18
M.minimum_width = 36
M.minimum_height = 6

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
  local browser = {
    directory = vim.fs.normalize(options.starting_directory),
    entries = {},
    entry_cache = {},
    picker = nil,
  }
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local telescope_config = require('telescope.config').values

  local function directory_entries(directory)
    local normalized_directory = vim.fs.normalize(directory)
    local cached_entries = browser.entry_cache[normalized_directory]
    if cached_entries then
      return cached_entries
    end
    local entries = M.entries(normalized_directory)
    browser.entry_cache[normalized_directory] = entries
    return entries
  end

  local function entries_for_prompt(prompt)
    local query = M.query(prompt, browser.directory)
    if not query.path_query then
      return browser.entries
    end
    local query_entries = {}
    local lowercase_leaf = query.leaf:lower()
    for _, entry in ipairs(directory_entries(query.directory)) do
      local entry_name = vim.fs.basename(entry.path)
      local matches_leaf = lowercase_leaf == ''
        or entry_name:lower():find(lowercase_leaf, 1, true) ~= nil
      if matches_leaf then
        local display_path = abbreviated_path(entry.path)
        query_entries[#query_entries + 1] = {
          display = ('󰉋  %s'):format(display_path),
          kind = entry.kind,
          ordinal = prompt .. ' ' .. display_path .. ' ' .. entry.path,
          path = entry.path,
          value = entry.value,
        }
      end
    end
    return query_entries
  end

  local function finder()
    return finders.new_dynamic({
      entry_maker = function(entry)
        return entry
      end,
      fn = entries_for_prompt,
    })
  end

  local function picker_title(directory)
    return 'Open Folder · ' .. abbreviated_path(directory)
  end

  local function browse_to(directory)
    browser.directory = vim.fs.normalize(directory)
    browser.entries = directory_entries(browser.directory)
    local directory_title = picker_title(browser.directory)
    local directory_layout = M.layout(
      browser.entries,
      directory_title,
      vim.o.columns,
      vim.o.lines
    )
    browser.picker.layout_config.width = directory_layout.width
    browser.picker.layout_config.height = directory_layout.height
    browser.picker:refresh(finder(), { reset_prompt = true })
    browser.picker.prompt_title = directory_title
    local prompt_border = browser.picker.layout
      and browser.picker.layout.prompt
      and browser.picker.layout.prompt.border
    if prompt_border and prompt_border.change_title then
      prompt_border:change_title(browser.picker.prompt_title)
    end
    browser.picker:full_layout_update()
  end

  browser.entries = directory_entries(browser.directory)
  local initial_title = picker_title(browser.directory)
  local picker_options = {
    layout_strategy = 'center',
    layout_config = M.layout(browser.entries, initial_title, vim.o.columns, vim.o.lines),
  }
  browser.picker = pickers.new(picker_options, {
    prompt_title = initial_title,
    finder = finder(),
    previewer = false,
    sorter = telescope_config.generic_sorter({}),
    attach_mappings = function(prompt_buffer, map)
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')
      local function selected_or_typed_path()
        local input_text = action_state.get_current_line()
        local typed_path = M.existing_path(input_text, browser.directory)
        local selected_entry = action_state.get_selected_entry()
        return typed_path or (selected_entry and selected_entry.value)
      end
      actions.select_default:replace(function()
        local selected_path = selected_or_typed_path()
        if not selected_path then
          vim.notify('Select a folder or enter an existing path', vim.log.levels.INFO)
          return
        end
        actions.close(prompt_buffer)
        options.on_select(selected_path)
      end)
      local function browse_selected()
        local selected_path = selected_or_typed_path()
        if selected_path then
          browse_to(selected_path)
        end
      end
      local function browse_parent()
        browse_to(vim.fs.dirname(browser.directory))
      end
      local function complete_selected_prefix()
        local selected_entry = action_state.get_selected_entry()
        if not selected_entry then
          return
        end
        local completion_prefix = M.completion_prefix(
          action_state.get_current_line(),
          selected_entry.value,
          browser.directory
        )
        if completion_prefix then
          browser.picker:set_prompt(completion_prefix)
        end
      end
      map({ 'i', 'n' }, '<C-l>', browse_selected, {
        desc = 'Browse into selected folder',
      })
      map({ 'i', 'n' }, '<C-h>', browse_parent, {
        desc = 'Browse to parent folder',
      })
      map({ 'i', 'n' }, '<Tab>', complete_selected_prefix, {
        desc = 'Complete selected folder prefix',
      })
      map('n', 'l', browse_selected, { desc = 'Browse into selected folder' })
      map('n', 'h', browse_parent, { desc = 'Browse to parent folder' })
      if options.on_close then
        vim.api.nvim_create_autocmd('BufWipeout', {
          buffer = prompt_buffer,
          once = true,
          callback = function()
            vim.schedule(options.on_close)
          end,
          desc = 'Release folder picker',
        })
      end
      return true
    end,
  })
  browser.picker:find()
  return browser
end

return M
