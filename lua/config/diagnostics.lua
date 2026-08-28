local M = {}

function M.open_float()
  local float_bufnr, float_winid = vim.diagnostic.open_float({
    border = 'rounded',
    focus = true,
    header = {
      '  <Space>e/q close  ·  y copy',
      'TypeInformationHint',
    },
    max_height = 30,
    max_width = 88,
    prefix = function(_diagnostic, index)
      return ('  %d  '):format(index), 'TypeInformationIndex'
    end,
    source = 'if_many',
    title = ' Diagnostic details ',
    title_pos = 'center',
    wrap = true,
  })
  if not float_bufnr or not float_winid then
    return
  end

  local function close_float()
    if vim.api.nvim_win_is_valid(float_winid) then
      vim.api.nvim_win_close(float_winid, true)
    end
  end
  require('config.detail_window').attach({
    bufnr = float_bufnr,
    winid = float_winid,
    toggle_key = '<Space>e',
    cursorline = false,
    close = close_float,
  })
end

function M.open_picker()
  require('telescope.builtin').diagnostics({ bufnr = 0 })
end

function M.setup()
  require('config.audit.diagnostic').setup()
end

return M
