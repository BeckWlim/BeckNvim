local M = {}

local function project_relative_path()
  local bufnr = vim.api.nvim_get_current_buf()
  local relative_path = require('config.project').relative_path(bufnr)
  local status_path = relative_path
  if vim.bo[bufnr].modified then
    status_path = status_path .. ' [+]'
  end
  if vim.bo[bufnr].readonly then
    status_path = status_path .. ' [RO]'
  end
  return status_path
end

function M.setup()
  require('lualine').setup({
    sections = {
      lualine_c = {
        { project_relative_path },
      },
    },
  })
end

return M
