local M = {}

M.marker_groups = {
  { 'pyrightconfig.json', 'basedpyrightconfig.json' },
  { '.git' },
  {
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

function M.detect(path)
  local normalized_path = vim.fs.normalize(path)
  for _, markers in ipairs(M.marker_groups) do
    local detected_root = vim.fs.root(normalized_path, markers)
    if detected_root then
      return vim.fs.normalize(detected_root)
    end
  end
end

function M.for_buffer(bufnr)
  local selected_buffer = bufnr or vim.api.nvim_get_current_buf()
  local buffer_path = normalized_buffer_path(selected_buffer)
  local most_specific_root

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = selected_buffer })) do
    local candidate_root = client_root(client)
    if candidate_root
        and (not buffer_path or M.contains(candidate_root, buffer_path))
        and (not most_specific_root or #candidate_root > #most_specific_root) then
      most_specific_root = candidate_root
    end
  end

  if most_specific_root then
    return most_specific_root
  end

  local search_path = buffer_path or vim.uv.cwd()
  return M.detect(search_path) or vim.fs.normalize(vim.uv.cwd())
end

function M.for_path(path)
  return M.detect(path) or vim.fs.normalize(vim.uv.cwd())
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

return M
