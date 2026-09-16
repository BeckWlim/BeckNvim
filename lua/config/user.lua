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

local function read_assignments(config_lines)
  local assignment_config = { proxy_environment = {}, dev = {} }
  local found_assignment = false
  local found_content = false
  for _, line in ipairs(config_lines) do
    if not line:match('^%s*$') and not line:match('^%s*#') then
      found_content = true
      local assignment_line = line:gsub('^%s*export%s+', '')
      local name, raw_value = assignment_line:match('^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$')
      if name then
        found_assignment = true
        local _, quoted_value = raw_value:match('^(["\'])(.-)%1%s*$')
        local _, commented_quoted_value = raw_value:match('^(["\'])(.-)%1%s*#.*$')
        local value = quoted_value
          or commented_quoted_value
          or vim.trim((raw_value:gsub('%s+#.*$', '')))
        if name == 'NVIM_DEV' then
          assignment_config.dev.enabled = value == 'true' or value == '1'
        elseif name == 'NVIM_DEV_PATH' then
          assignment_config.dev.path = value
        elseif name == 'NVIM_DEV_PLUGINS' then
          assignment_config.dev.patterns = {}
          for pattern in value:gmatch('[^,%s]+') do
            table.insert(assignment_config.dev.patterns, pattern)
          end
        elseif value ~= '' then
          assignment_config.proxy_environment[name] = value
        end
      end
    end
  end
  if found_assignment or not found_content then
    return assignment_config
  end
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
  local decoded, loaded_config = pcall(vim.json.decode, config_source)
  if decoded and type(loaded_config) == 'table' then
    return loaded_config
  end
  local assignment_config = not decoded and read_assignments(config_lines) or nil
  if assignment_config then
    return assignment_config
  end
  warn_once('Invalid user Neovim settings (expected NAME=value lines or a JSON object): ' .. config_path)
  return {}
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
