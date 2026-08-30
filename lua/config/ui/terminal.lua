local M = {}

function M.setup_buffer(bufnr)
  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = 'Leave terminal input mode',
  })
end

return M
