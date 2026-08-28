local M = {}
M.project_icons = require('config.project').provider_icons

function M.project_name()
  local bufnr = vim.api.nvim_get_current_buf()
  local project = require('config.project')
  local root = project.for_buffer(bufnr)
  return project.name(root)
end

function M.project_identity()
  local bufnr = vim.api.nvim_get_current_buf()
  local project = require('config.project')
  local root = project.for_buffer(bufnr)
  local provider = project.repository_provider(root)
  local provider_icon = project.provider_icon(provider)
  return provider_icon .. ' ' .. project.name(root)
end

function M.project_relative_path()
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
        {
          M.project_identity,
          color = { gui = 'bold' },
        },
        { M.project_relative_path },
      },
    },
  })
end

return M
