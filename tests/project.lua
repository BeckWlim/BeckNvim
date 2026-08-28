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
assert(
  selected_root == repository_root,
  'a narrower LSP root overrode the authoritative Git repository root'
)

local temporary_root = vim.fn.tempname()
local lsp_root = vim.fs.joinpath(temporary_root, 'workspace')
local nested_lsp_root = vim.fs.joinpath(lsp_root, 'python')
local lsp_file = vim.fs.joinpath(nested_lsp_root, 'module.py')
vim.fn.mkdir(nested_lsp_root, 'p')
vim.fn.writefile({ 'value = 1' }, lsp_file)
local lsp_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(lsp_buffer, lsp_file)
local original_detect_repository = project.detect_repository
rawset(project, 'detect_repository', function()
  return nil
end)
rawset(vim.lsp, 'get_clients', function(opts)
  local clients = {
    { root_dir = lsp_root },
    { root_dir = nested_lsp_root },
  }
  if not opts then
    return clients
  end
  assert(opts.bufnr == lsp_buffer, 'project root queried the wrong marker-free buffer')
  return clients
end)
local selected_lsp_root = project.for_buffer(lsp_buffer)
local selected_path_root = project.resolve_path(lsp_file)
rawset(project, 'detect_repository', original_detect_repository)
assert(
  selected_lsp_root == nested_lsp_root,
  'the most specific LSP root was not used outside a Git repository'
)
assert(
  selected_path_root == nested_lsp_root,
  'path resolution did not apply the active LSP root authority'
)
rawset(vim.lsp, 'get_clients', original_get_clients)
vim.api.nvim_buf_delete(lsp_buffer, { force = true })

local git_root = vim.fs.joinpath(temporary_root, 'repository')
local environment_root = vim.fs.joinpath(git_root, 'python')
local source_path = vim.fs.joinpath(environment_root, 'src', 'main.py')
vim.fn.mkdir(vim.fs.joinpath(git_root, '.git'), 'p')
vim.fn.mkdir(vim.fs.joinpath(environment_root, '.venv'), 'p')
vim.fn.mkdir(vim.fs.dirname(source_path), 'p')
vim.fn.writefile({ 'value = 1' }, source_path)
assert(
  project.detect(source_path) == git_root,
  'a closer .venv marker overrode the authoritative Git repository root'
)
assert(project.name(git_root) == 'repository', 'project name did not use the root basename')
assert(
  project.repository_provider(git_root) == 'git',
  'a repository without a recognized remote did not use the generic Git provider'
)

local provider_remotes = {
  github = 'git@github.com:example/project.git',
  gitlab = 'https://gitlab.com/example/project.git',
  bitbucket = 'ssh://git@bitbucket.org/example/project.git',
}
for provider, remote_url in pairs(provider_remotes) do
  local provider_root = vim.fs.joinpath(temporary_root, provider)
  local provider_git_directory = vim.fs.joinpath(provider_root, '.git')
  vim.fn.mkdir(provider_git_directory, 'p')
  vim.fn.writefile({
    '[remote "origin"]',
    '  url = ' .. remote_url,
  }, vim.fs.joinpath(provider_git_directory, 'config'))
  assert(
    project.repository_provider(provider_root) == provider,
    provider .. ' remote did not select its statusline provider icon'
  )
end

vim.fn.delete(temporary_root, 'rf')
