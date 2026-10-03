local M = {}

---@param transition NavigationTransition
---@return boolean
function M.allow(transition)
  local buffer = transition.buffer
  if not buffer or vim.bo[buffer].buftype ~= '' or not vim.bo[buffer].modified then return true end
  local window = transition.window
  local view_buffer = vim.api.nvim_win_get_buf(window)
  local tabpage = vim.api.nvim_win_get_tabpage(window)
  local changedtick = vim.api.nvim_buf_get_changedtick(buffer)
  local answer = vim.fn.confirm('Unsaved changes. Write this file now? (y/n)', '&Yes\n&No', 2)
  if answer ~= 1 then return false end
  if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_tabpage(window) ~= tabpage
      or vim.api.nvim_win_get_buf(window) ~= view_buffer or not vim.api.nvim_buf_is_valid(buffer)
      or vim.api.nvim_buf_get_changedtick(buffer) ~= changedtick then
    vim.notify('The file changed while choosing; navigation cancelled.', vim.log.levels.WARN)
    return false
  end
  local written, failure = pcall(vim.api.nvim_buf_call, buffer, function() vim.cmd('silent write') end)
  if not written then vim.notify(tostring(failure), vim.log.levels.ERROR); return false end
  if vim.bo[buffer].modified then
    vim.notify('The file still has unsaved changes; navigation cancelled.', vim.log.levels.WARN)
    return false
  end
  return true
end

function M.setup()
  return require('config.navigation').register_boundary('write_guard', M.allow)
end

return M
