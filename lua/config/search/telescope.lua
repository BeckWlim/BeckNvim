local M = {}
local float = require('config.ui.float')

local results_focused_preview_width = 0.55
local preview_focused_preview_width = 0.65
local results_focused_preview_height = 0.36
local preview_focused_preview_height = 0.58

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
  vim.keymap.set('i', '<C-c>', '<Nop>', { buffer = buffer, silent = true })
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
  resize_for_focus(picker, true)
  local focused_preview_window = previewer.state.winid
  if not focused_preview_window or not vim.api.nvim_win_is_valid(focused_preview_window) then
    return
  end
  local preview_buffer = vim.api.nvim_win_get_buf(focused_preview_window)
  bind_pane(preview_buffer, prompt_buffer, picker, true)
  if vim.b[preview_buffer].telescope_preview_modifiable == nil then
    vim.b[preview_buffer].telescope_preview_modifiable = vim.bo[preview_buffer].modifiable
  end
  vim.bo[preview_buffer].modifiable = false
  vim.wo[focused_preview_window].cursorline = true
  vim.wo[focused_preview_window].cursorlineopt = 'line'
  vim.keymap.set('n', '<Tab>', function()
    local active_prompt_window = picker.prompt_win
    if not active_prompt_window or not vim.api.nvim_win_is_valid(active_prompt_window) then
      return
    end
    unlock_preview(preview_buffer)
    resize_for_focus(picker, false)
    local resized_prompt_window = picker.prompt_win
    if not resized_prompt_window or not vim.api.nvim_win_is_valid(resized_prompt_window) then
      return
    end
    set_current_window_without_autocommands(resized_prompt_window)
    if return_to_insert_mode then
      vim.cmd('startinsert')
    end
  end, {
    buffer = preview_buffer,
    nowait = true,
    silent = true,
    desc = 'Return to Telescope results',
  })
  vim.keymap.set('n', '<CR>', function()
    if picker.preview_enter_action then
      picker.preview_enter_action(prompt_buffer)
    else
      require('telescope.actions').select_default(prompt_buffer)
    end
  end, {
    buffer = preview_buffer,
    silent = true,
    desc = 'Jump to selected Telescope result',
  })

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
  local pane_group = vim.api.nvim_create_augroup('telescope_pane_policy', { clear = true })
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
        local previewer = picker and picker.previewer
        local preview_window = previewer and previewer.state and previewer.state.winid
        if picker and (closed_window == picker.prompt_win or closed_window == picker.results_win
            or closed_window == preview_window) then
          vim.schedule(function()
            if state.get_status(prompt_buffer).picker == picker then
              require('telescope.actions').close(prompt_buffer)
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
        i = {
          [float.input_close_key] = actions.close,
          ['<C-c>'] = false,
          ['<Tab>'] = M.focus_preview,
        },
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
      file_ignore_patterns = { '.git/', 'node_modules/', '__pycache__/' },
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
