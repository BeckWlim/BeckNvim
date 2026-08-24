local M = {}

function M.open_float()
  local float_bufnr, float_winid = vim.diagnostic.open_float({ focus = true })
  if not float_bufnr or not float_winid then
    return
  end

  local function close_float()
    if vim.api.nvim_win_is_valid(float_winid) then
      vim.api.nvim_win_close(float_winid, true)
    end
  end

  vim.keymap.set('n', '<Space>e', close_float, {
    buffer = float_bufnr,
    nowait = true,
    silent = true,
    desc = 'Close diagnostic float',
  })
  vim.keymap.set('n', 'y', function()
    local lines = vim.api.nvim_buf_get_lines(float_bufnr, 0, -1, false)
    vim.fn.setreg('"', lines, 'l')
    require('vim.ui.clipboard.osc52').copy('+')(lines)
    vim.notify('Diagnostic copied to clipboard')
  end, {
    buffer = float_bufnr,
    nowait = true,
    silent = true,
    desc = 'Copy diagnostic',
  })

  if vim.api.nvim_win_is_valid(float_winid) then
    vim.api.nvim_set_current_win(float_winid)
  end
end

function M.toggle_list()
  local loclist_winid = vim.fn.getloclist(0, { winid = 0 }).winid
  if loclist_winid and loclist_winid ~= 0 then
    vim.api.nvim_win_close(loclist_winid, true)
    return
  end
  vim.diagnostic.setloclist({ open = true })
end

function M.setup()
  require('config.audit.diagnostic').setup()
end

return M
