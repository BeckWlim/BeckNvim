local M = {}
local repository_provider_cache = {}

-- Root authority, from strongest to weakest:
--   1. The nearest Git repository root.
--   2. The most specific attached LSP root for a buffer.
--   3. The nearest ancestor containing a workspace marker.
--   4. The current working directory as a final fallback.
M.root_marker_tiers = {
  repository = { '.git' },
  workspace = {
    '.venv',
    'pyrightconfig.json',
    'basedpyrightconfig.json',
    'pyproject.toml',
    'setup.py',
    'package.json',
    'Cargo.toml',
    'go.mod',
    'CMakeLists.txt',
    'compile_commands.json',
    'Makefile',
  },
}

M.provider_icons = {
  github = '',
  gitlab = '',
  bitbucket = '',
  git = '',
  workspace = '',
}

M.python_markers = {
  'pyrightconfig.json',
  'basedpyrightconfig.json',
  'pyproject.toml',
  'setup.py',
}

local function normalized_buffer_path(bufnr)
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  if buffer_path == '' then
    return
  end
  return vim.fs.normalize(buffer_path)
end

local function client_root(client)
  local client_config = client.config or {}
  local configured_root = client.root_dir or client_config.root_dir
  if type(configured_root) ~= 'string' or configured_root == '' then
    return
  end
  return vim.fs.normalize(configured_root)
end

function M.contains(root, path)
  local normalized_root = vim.fs.normalize(root)
  local normalized_path = vim.fs.normalize(path)
  return normalized_path == normalized_root
    or normalized_path:sub(1, #normalized_root + 1) == normalized_root .. '/'
end

local function detect_with_markers(path, markers)
  local normalized_path = vim.fs.normalize(path)
  local detected_root = vim.fs.root(normalized_path, markers)
  if detected_root then
    return vim.fs.normalize(detected_root)
  end
end

function M.detect_repository(path)
  return detect_with_markers(path, M.root_marker_tiers.repository)
end

function M.detect(path)
  return M.detect_repository(path)
    or detect_with_markers(path, M.root_marker_tiers.workspace)
end

local function most_specific_client_root(path, clients)
  local selected_root
  for _, client in ipairs(clients) do
    local candidate_root = client_root(client)
    if candidate_root
        and (not path or M.contains(candidate_root, path))
        and (not selected_root or #candidate_root > #selected_root) then
      selected_root = candidate_root
    end
  end
  return selected_root
end

function M.resolve_path(path)
  local normalized_path = vim.fs.normalize(path)
  return M.detect_repository(normalized_path)
    or most_specific_client_root(normalized_path, vim.lsp.get_clients())
    or detect_with_markers(normalized_path, M.root_marker_tiers.workspace)
end

function M.for_buffer(bufnr)
  local selected_buffer = bufnr or vim.api.nvim_get_current_buf()
  local buffer_path = normalized_buffer_path(selected_buffer)

  if buffer_path then
    local repository_root = M.detect_repository(buffer_path)
    if repository_root then
      return repository_root
    end
  end

  local attached_client_root = most_specific_client_root(
    buffer_path,
    vim.lsp.get_clients({ bufnr = selected_buffer })
  )
  if attached_client_root then
    return attached_client_root
  end

  local search_path = buffer_path or vim.uv.cwd()
  return M.detect(search_path) or vim.fs.normalize(vim.uv.cwd())
end

function M.for_path(path)
  return M.resolve_path(path) or vim.fs.normalize(vim.uv.cwd())
end

function M.has_marker(root, markers)
  for _, marker in ipairs(markers) do
    if vim.uv.fs_stat(vim.fs.joinpath(root, marker)) then
      return true
    end
  end
  return false
end

function M.is_python(root)
  return M.has_marker(root, M.python_markers)
end

function M.relative_path(bufnr)
  local selected_buffer = bufnr or vim.api.nvim_get_current_buf()
  local buffer_path = normalized_buffer_path(selected_buffer)
  if not buffer_path then
    return '[No Name]'
  end
  local root = M.for_buffer(selected_buffer)
  return vim.fs.relpath(root, buffer_path) or buffer_path
end

function M.name(root)
  local normalized_root = vim.fs.normalize(root)
  return vim.fs.basename(normalized_root)
end

local function git_config_path(root)
  local git_marker = vim.fs.joinpath(root, '.git')
  local marker_stat = vim.uv.fs_stat(git_marker)
  if not marker_stat then
    return
  end
  if marker_stat.type == 'directory' then
    return vim.fs.joinpath(git_marker, 'config')
  end
  if marker_stat.type ~= 'file' then
    return
  end

  local marker_lines = vim.fn.readfile(git_marker, '', 1)
  local git_directory = marker_lines[1] and marker_lines[1]:match('^gitdir:%s*(.+)%s*$')
  if not git_directory then
    return
  end
  local absolute_git_directory = git_directory:match('^/')
      and git_directory
    or vim.fs.joinpath(root, git_directory)
  return vim.fs.joinpath(vim.fs.normalize(absolute_git_directory), 'config')
end

local function provider_from_config(config_path)
  if not config_path or not vim.uv.fs_stat(config_path) then
    return 'git'
  end
  local remote_url
  local fallback_url
  local reading_origin = false
  for _, config_line in ipairs(vim.fn.readfile(config_path)) do
    local section_name = config_line:match('^%s*%[([^%]]+)%]%s*$')
    if section_name then
      reading_origin = section_name:lower() == 'remote "origin"'
    else
      local configured_url = config_line:match('^%s*url%s*=%s*(.-)%s*$')
      if configured_url then
        if reading_origin then
          remote_url = configured_url
          break
        end
        fallback_url = fallback_url or configured_url
      end
    end
  end

  local provider_url = (remote_url or fallback_url or ''):lower()
  if provider_url:find('github', 1, true) then
    return 'github'
  end
  if provider_url:find('gitlab', 1, true) then
    return 'gitlab'
  end
  if provider_url:find('bitbucket', 1, true) then
    return 'bitbucket'
  end
  return 'git'
end

function M.repository_provider(root)
  local normalized_root = vim.fs.normalize(root)
  local cached_provider = repository_provider_cache[normalized_root]
  if cached_provider then
    return cached_provider
  end
  if not M.detect_repository(normalized_root) then
    repository_provider_cache[normalized_root] = 'workspace'
    return 'workspace'
  end
  local provider = provider_from_config(git_config_path(normalized_root))
  repository_provider_cache[normalized_root] = provider
  return provider
end

function M.provider_icon(provider)
  return M.provider_icons[provider] or M.provider_icons.workspace
end

return M
