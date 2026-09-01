local M = {}
local float = require('config.ui.float')

local function style_window(winid, options)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  local cursorline_enabled = options.cursorline ~= false
  vim.wo[winid].breakindent = true
  vim.wo[winid].breakindentopt = 'shift:2,min:20'
  vim.wo[winid].cursorline = cursorline_enabled
  vim.wo[winid].linebreak = true
  vim.wo[winid].showbreak = '↳ '
  vim.wo[winid].smoothscroll = true
  vim.wo[winid].wrap = true
  local window_highlights = { 'Normal:NormalFloat' }
  if cursorline_enabled then
    window_highlights[#window_highlights + 1] = 'CursorLine:TypeInformationCursorLine'
  end
  vim.wo[winid].winhighlight = table.concat(window_highlights, ',')

end

local function copy_contents(bufnr)
  local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.setreg('"', content_lines, 'l')
  require('vim.ui.clipboard.osc52').copy('+')(content_lines)
  vim.notify('Details copied to clipboard')
end

function M.attach(options)
  local bufnr = options.bufnr
  local winid = options.winid
  local close_window = options.close

  style_window(winid, options)

  float.bind_close({
    buffer = bufnr,
    close = close_window,
    description = 'Close detail window',
  })
  vim.keymap.set('n', options.toggle_key, close_window, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'Close detail window',
  })
  vim.keymap.set('n', 'y', function()
    copy_contents(bufnr)
  end, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'Copy detail window',
  })

  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
  end
end

return M
