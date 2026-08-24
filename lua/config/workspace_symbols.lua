local project = require('config.project')

local M = {}
local providers = {}

function M.register(provider)
  assert(type(provider) == 'table', 'symbol provider must be a table')
  assert(type(provider.supports) == 'function', 'symbol provider requires supports()')
  assert(type(provider.open) == 'function', 'symbol provider requires open()')
  providers[#providers + 1] = provider
end

local function workspace_symbol_buffer(root, current_bufnr)
  if #vim.lsp.get_clients({ bufnr = current_bufnr, method = 'workspace/symbol' }) > 0 then
    return current_bufnr
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buffer_path = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_buf_is_loaded(bufnr)
        and buffer_path ~= ''
        and project.contains(root, buffer_path)
        and #vim.lsp.get_clients({ bufnr = bufnr, method = 'workspace/symbol' }) > 0 then
      return bufnr
    end
  end
end

function M.open()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local root = project.for_buffer(current_bufnr)
  for _, provider in ipairs(providers) do
    if provider.supports(root, current_bufnr) then
      provider.open(root, current_bufnr)
      return
    end
  end

  local bufnr = workspace_symbol_buffer(root, current_bufnr)
  if not bufnr then
    vim.notify('No project-symbol provider is available for this project', vim.log.levels.WARN)
    return
  end
  require('telescope.builtin').lsp_dynamic_workspace_symbols({ bufnr = bufnr })
end

M.register({
  supports = function(root, bufnr)
    return vim.bo[bufnr].filetype == 'python' or project.is_python(root)
  end,
  open = function(root)
    require('config.python_symbols').open(root)
  end,
})

return M
