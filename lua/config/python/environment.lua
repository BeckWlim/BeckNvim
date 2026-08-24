local M = {}

local function path_is_inside(path, root)
  local normalized_path = vim.fs.normalize(path)
  local normalized_root = vim.fs.normalize(root)
  return normalized_path == normalized_root
    or normalized_path:sub(1, #normalized_root + 1) == normalized_root .. '/'
end

local function executable_path(candidates)
  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

local function inspect_environment(directory)
  local normalized_directory = vim.fs.normalize(directory)
  local python_path = executable_path({
    vim.fs.joinpath(normalized_directory, 'bin', 'python'),
    vim.fs.joinpath(normalized_directory, 'Scripts', 'python.exe'),
  })
  if not python_path then
    return
  end

  return {
    directory = normalized_directory,
    python = python_path,
    basedpyright = executable_path({
      vim.fs.joinpath(normalized_directory, 'bin', 'basedpyright'),
      vim.fs.joinpath(normalized_directory, 'Scripts', 'basedpyright.exe'),
    }),
  }
end

function M.resolve(root)
  local normalized_root = vim.fs.normalize(root)
  local candidate_directories = {
    vim.fs.joinpath(normalized_root, '.venv'),
    vim.fs.joinpath(normalized_root, 'venv'),
    vim.fs.joinpath(normalized_root, 'env'),
  }

  for _, environment_variable in ipairs({ 'VIRTUAL_ENV', 'CONDA_PREFIX' }) do
    local configured_directory = vim.env[environment_variable]
    if type(configured_directory) == 'string'
        and configured_directory ~= ''
        and path_is_inside(configured_directory, normalized_root) then
      candidate_directories[#candidate_directories + 1] = configured_directory
    end
  end

  local inspected_directories = {}
  for _, candidate_directory in ipairs(candidate_directories) do
    local normalized_candidate = vim.fs.normalize(candidate_directory)
    if not inspected_directories[normalized_candidate] then
      inspected_directories[normalized_candidate] = true
      local environment = inspect_environment(normalized_candidate)
      if environment then
        return environment
      end
    end
  end
end

return M
