local M = {}
local float = require('config.ui.float')

local results_focused_preview_width = 0.55
local preview_focused_preview_width = 0.65
local results_focused_preview_height = 0.36
local preview_focused_preview_height = 0.58

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
  vim.wo[focused_preview_window].cursorline = true
  vim.wo[focused_preview_window].cursorlineopt = 'line'
  vim.keymap.set('n', '<Tab>', function()
    local active_prompt_window = picker.prompt_win
    if not active_prompt_window or not vim.api.nvim_win_is_valid(active_prompt_window) then
      return
    end
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
  local function close_picker()
    require('telescope.actions').close(prompt_buffer)
  end
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
  float.bind_close({
    buffer = preview_buffer,
    close = close_picker,
    description = 'Close Telescope',
  })
  if picker.close_preview_with_ctrl_q then
    vim.keymap.set('n', float.input_close_key, picker.ctrl_q_action or close_picker, {
      buffer = preview_buffer,
      nowait = true,
      silent = true,
      desc = 'Close Telescope',
    })
  end

  -- Telescope normally closes when its prompt loses focus. Suppressing these
  -- two focus-transition events keeps the picker alive while inspecting its
  -- preview; the original close autocmd remains armed for a real picker exit.
  set_current_window_without_autocommands(focused_preview_window)
  vim.cmd('stopinsert')
end

function M.setup()
  local telescope = require('telescope')
  local actions = require('telescope.actions')
  local workspace_symbols = require('config.search.workspace_symbols')
  local contextual_previewer = require('config.search.grep_preview').new
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
          ['<Tab>'] = M.focus_preview,
        },
        n = {
          [float.input_close_key] = false,
          [float.normal_close_key] = actions.close,
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
