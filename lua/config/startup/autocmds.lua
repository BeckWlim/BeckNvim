local M = {}

function M.setup()
  local external_change_group = vim.api.nvim_create_augroup(
    'reload_external_file_changes',
    { clear = true }
  )
  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
    group = external_change_group,
    nested = true,
    callback = function()
      vim.cmd.checktime()
    end,
    desc = 'Reload files changed outside Neovim',
  })

  local tree_group = vim.api.nvim_create_augroup('close_file_tree_on_exit', { clear = true })
  vim.api.nvim_create_autocmd('QuitPre', {
    group = tree_group,
    callback = function()
      if vim.fn.exists(':NvimTreeClose') == 2 then
        vim.cmd.NvimTreeClose()
      end
    end,
    desc = 'Close nvim-tree before exiting',
  })
end

return M
