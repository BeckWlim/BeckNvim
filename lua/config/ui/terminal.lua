local M = {}

function M.setup_buffer(bufnr)
  require('config.ui.window_state').register('toggleterm', function()
    return { number = vim.go.number, relativenumber = vim.go.relativenumber }
  end)
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'Leave terminal input mode',
  })
end

return M
