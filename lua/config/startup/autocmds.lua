local M = {}

function M.setup()
  local jump_group = vim.api.nvim_create_augroup('current_instance_jumps', { clear = true })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = jump_group,
    once = true,
    callback = function()
      -- ShaDa has finished restoring here. Keep its recent files, marks, and
      -- registers, but begin each process with its own navigation history.
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        vim.api.nvim_win_call(window, function() vim.cmd('clearjumps') end)
      end
    end,
    desc = 'Start jump history in the current Neovim instance',
  })
  local external_change_group = vim.api.nvim_create_augroup(
    'reload_external_file_changes',
    { clear = true }
  )
  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
    group = external_change_group,
    nested = true,
    callback = function()
      vim.api.nvim_cmd({ cmd = 'checktime' }, {})
    end,
    desc = 'Reload files changed outside Neovim',
  })

  local tree_group = vim.api.nvim_create_augroup('close_file_tree_on_exit', { clear = true })
  vim.api.nvim_create_autocmd('QuitPre', {
    group = tree_group,
    callback = function()
      if vim.b.telescope_quit_guard then return end
      if vim.fn.exists(':NvimTreeClose') == 2 then
        vim.cmd.NvimTreeClose()
      end
    end,
    desc = 'Close nvim-tree before exiting',
  })
end

return M
