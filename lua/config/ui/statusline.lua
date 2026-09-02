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

function M.refresh_git_branch()
  local branch_component_available, branch_component = pcall(
    require,
    'lualine.components.branch.git_branch'
  )
  if branch_component_available and type(branch_component.find_git_dir) == 'function' then
    pcall(branch_component.find_git_dir)
  end

  local lualine_available, lualine = pcall(require, 'lualine')
  if lualine_available and type(lualine.refresh) == 'function' then
    pcall(lualine.refresh, { force = true, place = { 'statusline' } })
  end
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
