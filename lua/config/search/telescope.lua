local M = {}
local float = require('config.ui.float')

local results_focused_preview_width = 0.55
local preview_focused_preview_width = 0.65
local results_focused_preview_height = 0.36
local preview_focused_preview_height = 0.58

-- Install only on file-result pickers. Project/theme/Git choices keep their owners.
function M.attach_file_actions(prompt_buffer)
  local picker = require('telescope.actions.state').get_current_picker(prompt_buffer)
  picker.navigation_context = picker.navigation_context
    or require('config.navigation').capture(picker.original_win_id)
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = prompt_buffer, once = true,
    callback = picker.navigation_context.restore_layout,
    desc = 'Keep native split proportions when file search closes',
  })
  local commands = { edit = 'edit', new = 'split', vnew = 'vsplit', tabedit = 'tabedit' }
  require('telescope.actions.set').edit:replace_if(function(_, command)
    return commands[command] ~= nil
  end, function(prompt_buffer, command)
    local action_state = require('telescope.actions.state')
    local picker = action_state.get_current_picker(prompt_buffer)
    local entry = action_state.get_selected_entry()
    if not entry then return end
    local path = entry.path or entry.filename
    if not path and not entry.bufnr then
      vim.notify('The selected result has no file or buffer', vim.log.levels.WARN)
      return
    end
    local open_command = commands[command]
    local Path = require('plenary.path')
    local entry_path = path and Path:new(path) or nil
    local resolved_path = entry_path and (entry_path:is_absolute() and entry_path:absolute()
      or Path:new(picker.cwd or vim.uv.cwd(), path):absolute()) or ''
    local open_options = {
      context = picker.navigation_context,
      command = open_command, buffer = entry.bufnr,
      line = entry.row or entry.lnum, column = entry.col,
      push_cursor = picker.push_cursor_on_edit, push_tagstack = picker.push_tagstack_on_edit,
    }
    require('telescope.actions').close(prompt_buffer)
    require('config.navigation').open(resolved_path, open_options)
  end)
  return true
end

-- Capture the launch surface before a builtin loads data or creates windows.
-- Prompt and preview Enter retain the same explicit edit/split intent.
function M.open_file_picker(name, options, command)
  local context = require('config.navigation').capture()
  local picker_options = vim.tbl_extend('force', {}, options or {})
  local attach = picker_options.attach_mappings
  picker_options.attach_mappings = function(prompt_buffer, map)
    local picker = require('telescope.actions.state').get_current_picker(prompt_buffer)
    picker.navigation_context = context
    M.attach_file_actions(prompt_buffer)
    local actions = require('telescope.actions')
    local select = command == 'vnew' and actions.file_vsplit or actions.select_default
    picker.preview_enter_action = select
    if command == 'vnew' then
      map('i', '<CR>', select)
      map('n', '<CR>', select)
    end
    if attach then return attach(prompt_buffer, map) end
    return true
  end
  require('telescope.builtin')[name](picker_options)
end

local function unlock_preview(buffer)
  if vim.api.nvim_buf_is_valid(buffer) and vim.b[buffer].telescope_preview_modifiable ~= nil then
    vim.bo[buffer].modifiable = vim.b[buffer].telescope_preview_modifiable
    vim.b[buffer].telescope_preview_modifiable = nil
  end
end

local function bind_pane(buffer, prompt_buffer, picker, is_preview)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then return end
  local function close_picker()
    if picker.ctrl_q_action then picker.ctrl_q_action()
    else require('telescope.actions').close(prompt_buffer) end
  end
  require('config.navigation').register_close(buffer, close_picker)
  vim.keymap.set({ 'n', 'i', 'x', 's', 'o', 't' }, '<C-q>', close_picker,
    { buffer = buffer, silent = true, nowait = true, desc = 'Close Telescope' })
  vim.keymap.set('c', '<C-q>', function()
    vim.schedule(function()
      if require('telescope.state').get_status(prompt_buffer).picker == picker then close_picker() end
    end)
    return '<C-c>'
  end, { buffer = buffer, expr = true, desc = 'Close Telescope' })
  vim.keymap.set('n', 'q', '<Nop>', { buffer = buffer, silent = true })
  for _, key in ipairs({ '<Esc>', 'ZZ', 'ZQ' }) do
    vim.keymap.set('n', key, '<Nop>', { buffer = buffer, silent = true })
  end
  vim.keymap.set('i', '<C-c>', '<Esc>', { buffer = buffer, silent = true, desc = 'Return to Normal mode' })
  if not vim.b[buffer].telescope_quit_guard then
    vim.b[buffer].telescope_quit_guard = true
    vim.api.nvim_create_autocmd('QuitPre', {
      buffer = buffer,
      command = 'throw "Use Ctrl-Q to close the whole Telescope picker"',
    })
  end
  if is_preview then
    -- These scratch buffers belong to an asynchronous renderer. 'readonly'
    -- warns on its next write (including moving the result selection).
    for _, key in ipairs({ 'i', 'I', 'a', 'A', 'o', 'O', 'R', 'gR', 'gi', 'gI' }) do
      vim.keymap.set('n', key, '<Nop>', { buffer = buffer, silent = true })
    end
    if not vim.b[buffer].telescope_preview_guard then
      vim.b[buffer].telescope_preview_guard = true
      vim.api.nvim_create_autocmd('InsertEnter', {
        buffer = buffer,
        callback = function()
          vim.schedule(function()
            if vim.api.nvim_get_current_buf() == buffer then vim.cmd('stopinsert') end
          end)
        end,
      })
      vim.api.nvim_create_autocmd('WinLeave', {
        buffer = buffer, callback = function() unlock_preview(buffer) end,
      })
    end
  end
end

local function set_current_window_without_autocommands(window)
  vim.cmd(('noautocmd call nvim_set_current_win(%d)'):format(window))
end

local function resize_for_focus(picker, preview_focused)
  local horizontal_layout = picker.layout_config.horizontal
  local vertical_layout = picker.layout_config.vertical
  local focus_layout = picker.focus_layout or {
    preview_height = preview_focused_preview_height,
    preview_width = preview_focused_preview_width,
    results_height = results_focused_preview_height,
    results_width = results_focused_preview_width,
  }
  if preview_focused then
    horizontal_layout.preview_width = focus_layout.preview_width
    vertical_layout.preview_height = focus_layout.preview_height
  else
    horizontal_layout.preview_width = focus_layout.results_width
    vertical_layout.preview_height = focus_layout.results_height
  end
  picker:full_layout_update()
end

local function return_to_prompt(picker, buffer)
  if not picker.prompt_win or not vim.api.nvim_win_is_valid(picker.prompt_win) then return end
  local previewer = picker.previewer
  local preview_buffer = buffer or (previewer and previewer.state and previewer.state.bufnr)
  if preview_buffer then unlock_preview(preview_buffer) end
  local return_to_insert_mode = picker.preview_focus_return_mode == 'i'
  picker.preview_focus_return_mode = nil
  resize_for_focus(picker, false)
  if not picker.prompt_win or not vim.api.nvim_win_is_valid(picker.prompt_win) then return end
  set_current_window_without_autocommands(picker.prompt_win)
  if return_to_insert_mode then vim.cmd('startinsert') end
end

local function bind_focused_preview(buffer, prompt_buffer, picker)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then return end
  bind_pane(buffer, prompt_buffer, picker, true)
  if vim.b[buffer].telescope_preview_modifiable == nil then
    vim.b[buffer].telescope_preview_modifiable = vim.bo[buffer].modifiable
  end
  vim.bo[buffer].modifiable = false
  vim.keymap.set('n', '<Tab>', function()
    return_to_prompt(picker, buffer)
  end, {
    buffer = buffer,
    nowait = true,
    silent = true,
    desc = 'Return to Telescope prompt',
  })
  vim.keymap.set('n', '<CR>', function()
    if picker.preview_enter_action then
      picker.preview_enter_action(prompt_buffer)
    else
      require('telescope.actions').select_default(prompt_buffer)
    end
  end, {
    buffer = buffer,
    silent = true,
    desc = 'Jump to selected Telescope result',
  })
end

local function bind_open_pickers()
  local state = require('telescope.state')
  for _, prompt_buffer in ipairs(state.get_existing_prompt_bufnrs()) do
    local picker = state.get_status(prompt_buffer).picker
    if picker then
      bind_pane(prompt_buffer, prompt_buffer, picker, false)
      bind_pane(picker.results_bufnr, prompt_buffer, picker, true)
      local previewer = picker.previewer
      local preview_buffer = previewer and previewer.state and previewer.state.bufnr
      bind_pane(preview_buffer, prompt_buffer, picker, true)
      if picker.preview_focus_return_mode and previewer and previewer.state
          and previewer.state.winid == vim.api.nvim_get_current_win() then
        bind_focused_preview(vim.api.nvim_win_get_buf(previewer.state.winid), prompt_buffer, picker)
      end
    end
  end
end

function M.focus_preview(prompt_buffer)
  local action_state = require('telescope.actions.state')
  local picker = action_state.get_current_picker(prompt_buffer)
  local previewer = picker.previewer
  local initial_preview_window = previewer and previewer.state and previewer.state.winid
  local initial_prompt_window = picker.prompt_win
  if not initial_preview_window
    or not vim.api.nvim_win_is_valid(initial_preview_window)
    or not initial_prompt_window
    or not vim.api.nvim_win_is_valid(initial_prompt_window)
  then
    return
  end

  local return_to_insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
  picker.preview_focus_return_mode = return_to_insert_mode and 'i' or 'n'
  resize_for_focus(picker, true)
  local focused_preview_window = previewer.state.winid
  if not focused_preview_window or not vim.api.nvim_win_is_valid(focused_preview_window) then
    picker.preview_focus_return_mode = nil
    return
  end
  local preview_buffer = vim.api.nvim_win_get_buf(focused_preview_window)
  bind_focused_preview(preview_buffer, prompt_buffer, picker)
  vim.wo[focused_preview_window].cursorline = true
  vim.wo[focused_preview_window].cursorlineopt = 'line'

  -- Telescope normally closes when its prompt loses focus. Suppressing these
  -- two focus-transition events keeps the picker alive while inspecting its
  -- preview; the original close autocmd remains armed for a real picker exit.
  set_current_window_without_autocommands(focused_preview_window)
  vim.cmd('stopinsert')
end

-- File-backed project themes reuse Telescope's layout, preview buffer, focus
-- transitions, and close actions. The theme owner controls commit and rollback.
function M.theme_picker(options)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local source_buffer = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  local source_lines = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
  local source_filetype = vim.bo[source_buffer].filetype
  local closed = false
  local preview_request
  local function apply_preview(name)
    if vim.api.nvim_win_is_valid(source_window) then
      return vim.api.nvim_win_call(source_window, function() return options.preview(name) end)
    end
    return options.preview(name)
  end
  local function close_session()
    if closed then return end
    closed = true
    options.close()
  end
  local previewer = require('telescope.previewers').new_buffer_previewer({
    title = 'Theme preview',
    define_preview = function(self, entry)
      if closed then return end
      local request = {}
      preview_request = request
      local preview_buffer = self.state.bufnr
      -- Picker updates can run under :noautocmd / a non-nested autocmd.
      -- Apply outside that context so every ColorScheme consumer sees the
      -- same transition as an explicit confirmation (statusline, context, etc.).
      vim.schedule(function()
        if closed or preview_request ~= request or self.state.bufnr ~= preview_buffer
            or not vim.api.nvim_buf_is_valid(preview_buffer) then return end
        local failure = apply_preview(entry.value)
        if closed or not vim.api.nvim_buf_is_valid(preview_buffer) then return end
        local lines = failure and { 'Theme unavailable', '', failure } or source_lines
        local was_modifiable = vim.bo[preview_buffer].modifiable
        vim.bo[preview_buffer].modifiable = true
        vim.api.nvim_buf_set_lines(preview_buffer, 0, -1, false, lines)
        vim.bo[preview_buffer].modifiable = was_modifiable
        if not failure then
          require('telescope.previewers.utils').highlighter(preview_buffer, source_filetype)
        end
      end)
    end,
    teardown = close_session,
  })
  require('telescope.pickers').new({}, {
    prompt_title = 'Theme',
    finder = require('telescope.finders').new_table({ results = options.names }),
    sorter = require('telescope.config').values.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_buffer, map)
      local picker = action_state.get_current_picker(prompt_buffer)
      local function confirm()
        local entry = action_state.get_selected_entry()
        if entry and options.confirm(entry.value) then actions.close(prompt_buffer) end
      end
      actions.select_default:replace(confirm)
      local function cancel() actions.close(prompt_buffer) end
      map('i', '<C-q>', cancel)
      map('n', '<C-q>', cancel)
      picker.close_preview_with_ctrl_q = true
      picker.preview_enter_action = confirm
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = prompt_buffer, once = true, callback = close_session,
      })
      return true
    end,
  }):find()
end

function M.setup()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local workspace_symbols = require('config.search.workspace_symbols')
  local contextual_previewer = require('config.search.grep_preview').new
  local direction_mappings = {}
  for _, mapping in ipairs(require('config.keybindings').mappings('directions', {
    left = '<Left>',
    right = '<Right>',
    down = function(buffer) actions.move_selection_next(buffer) end,
    up = function(buffer) actions.move_selection_previous(buffer) end,
  }, { key_format = '<C-%s>' })) do
    direction_mappings[mapping[2]] = type(mapping[3]) == 'string'
      and { mapping[3], type = 'command' } or mapping[3]
  end
  local pane_group = vim.api.nvim_create_augroup('telescope_pane_policy', { clear = true })
  local function owns_window(picker, window)
    local preview_window = picker.layout and picker.layout.preview and picker.layout.preview.winid
    return (picker.navigation_context and window == picker.navigation_context.source_window)
      or window == picker.prompt_win or window == picker.results_win or window == preview_window
  end
  vim.api.nvim_create_autocmd('User', {
    group = pane_group,
    pattern = { 'TelescopeFindPre', 'TelescopePreviewerLoaded' },
    callback = function() vim.schedule(bind_open_pickers) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = pane_group,
    callback = function(event)
      local closed_window = tonumber(event.match)
      local state = package.loaded['telescope.state']
      if not state then return end
      for _, prompt_buffer in ipairs(state.get_existing_prompt_bufnrs()) do
        local picker = state.get_status(prompt_buffer).picker
        if picker and owns_window(picker, closed_window) then
          vim.schedule(function()
            -- A native layout update may intentionally retire the old preview.
            -- Recheck ownership after Telescope publishes the replacement panes.
            if state.get_status(prompt_buffer).picker ~= picker then return end
            if owns_window(picker, closed_window) then
              require('telescope.actions').close(prompt_buffer)
            elseif picker.preview_focus_return_mode then
              return_to_prompt(picker)
            end
          end)
        end
      end
    end,
  })
  telescope.setup({
    defaults = {
      grep_previewer = contextual_previewer,
      qflist_previewer = contextual_previewer,
      layout_strategy = 'flex',
      layout_config = {
        flex = {
          flip_columns = 150,
          flip_lines = 24,
        },
        horizontal = {
          width = 0.82,
          height = 0.9,
          preview_cutoff = 80,
          preview_width = results_focused_preview_width,
        },
        vertical = {
          width = 0.82,
          height = 0.95,
          preview_cutoff = 12,
          preview_height = results_focused_preview_height,
        },
      },
      mappings = {
        i = vim.tbl_extend('force', direction_mappings, {
          [float.input_close_key] = actions.close,
          ['<C-c>'] = { '<Esc>', type = 'command' },
          ['<C-Left>'] = { '<C-Left>', type = 'command' },
          ['<C-Right>'] = { '<C-Right>', type = 'command' },
          ['<Tab>'] = M.focus_preview,
        }),
        n = {
          [float.input_close_key] = actions.close,
          [float.normal_close_key] = false,
          ['<Esc>'] = false,
          ['<Tab>'] = M.focus_preview,
        },
      },
      path_display = { 'smart' },
      vimgrep_arguments = {
        'rg',
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
        '--smart-case',
        '--hidden',
        '--no-ignore-vcs',
      },
      -- Telescope interprets these as Lua patterns; escape the dot so a
      -- project directory named `git/` remains searchable.
      file_ignore_patterns = { '%.git/', 'node_modules/', '__pycache__/' },
    },
    pickers = {
      find_files = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      oldfiles = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      buffers = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      live_grep = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      grep_string = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      diagnostics = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
      lsp_document_symbols = { layout_strategy = 'flex', attach_mappings = M.attach_file_actions },
    },
    extensions = {
      ['ui-select'] = require('telescope.themes').get_dropdown({
        previewer = false,
        layout_config = { width = 0.55, height = 0.45 },
      }),
    },
  })
  pcall(telescope.load_extension, 'fzf')
  telescope.load_extension('ui-select')
  require('config.python.hierarchy_index').setup()
  workspace_symbols.setup()
end

return M
