local M = {}

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_number = vim.fn.line('.')

  if vim.fn.foldlevel(line_number) == 0 then
    vim.notify('No code fold under cursor', vim.log.levels.INFO)
    return
  end

  local was_closed = vim.fn.foldclosed(line_number) ~= -1
  local count_prefix = vim.v.count > 0 and tostring(vim.v.count) or ''
  vim.cmd.normal({ args = { count_prefix .. 'za' }, bang = true })

  if was_closed then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) and vim.treesitter.highlighter.active[bufnr] then
        vim.api.nvim__redraw({ buf = bufnr, valid = false, flush = true })
      end
    end)
  end
end

return M
