local project = require('config.project')
local repository_root = vim.fs.normalize(vim.fn.getcwd())
local config_path = vim.fs.joinpath(repository_root, 'lua', 'config', 'project.lua')

assert(project.detect(config_path) == repository_root, 'project root detection ignored .git')
assert(project.contains(repository_root, config_path), 'project containment rejected a child path')
assert(
  not project.contains(repository_root, repository_root .. '-other/file.lua'),
  'project containment accepted a sibling path'
)

local original_get_clients = vim.lsp.get_clients
local current_bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(current_bufnr, config_path)
rawset(vim.lsp, 'get_clients', function(opts)
  assert(opts.bufnr == current_bufnr, 'project root queried the wrong buffer')
  return {
    { root_dir = repository_root },
    { root_dir = vim.fs.joinpath(repository_root, 'lua') },
  }
end)

local selected_root = project.for_buffer(current_bufnr)
rawset(vim.lsp, 'get_clients', original_get_clients)
assert(
  selected_root == vim.fs.joinpath(repository_root, 'lua'),
  'most specific LSP root was not selected'
)
