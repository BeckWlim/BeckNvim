local M = {}

local cached_config
local warned = false

local function warn_once(message)
  if warned then
    return
  end
  warned = true
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN)
  end)
end

local function user_config_path()
  return vim.fs.normalize(vim.fn.expand('~/.nvim'))
end

local function read_config()
  local config_path = user_config_path()
  local config_stat = vim.uv.fs_stat(config_path)
  if not config_stat or config_stat.type ~= 'file' then
    return {}
  end
  local read_succeeded, config_lines = pcall(vim.fn.readfile, config_path)
  if not read_succeeded then
    warn_once('Could not read user Neovim settings from ' .. config_path)
    return {}
  end
  local config_source = table.concat(config_lines, '\n')
  local config_chunk, syntax_error = loadstring(config_source, '@' .. config_path)
  if not config_chunk then
    warn_once('Invalid user Neovim settings syntax: ' .. tostring(syntax_error))
    return {}
  end
  setfenv(config_chunk, {})
  local executed, loaded_config = pcall(config_chunk)
  if not executed or type(loaded_config) ~= 'table' then
    warn_once(config_path .. ' must return a Lua table')
    return {}
  end
  return loaded_config
end

function M.get()
  if cached_config == nil then
    cached_config = read_config()
  end
  return cached_config
end

function M.reset()
  cached_config = nil
  warned = false
end

return M
