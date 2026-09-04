local user = require('config.user')

local M = {}

local defaults = {
  detail_batch_entries = 8,
  detail_worker_count = 4,
  list_batch_entries = 200,
  list_margin_entries = 30,
  list_max_entries = 600,
  preview_headroom_entries = 60,
  request_timeout_ms = 10000,
}

local limits = {
  detail_batch_entries = { 1, 64 },
  detail_worker_count = { 1, 16 },
  list_batch_entries = { 20, 2000 },
  list_margin_entries = { 1, 500 },
  list_max_entries = { 50, 5000 },
  preview_headroom_entries = { 0, 1000 },
  request_timeout_ms = { 1000, 60000 },
}

local function bounded_integer(value, fallback, value_limits)
  if type(value) ~= 'number'
      or value % 1 ~= 0
      or value < value_limits[1]
      or value > value_limits[2] then
    return fallback
  end
  return value
end

function M.footer()
  local user_config = user.get()
  local git_config = type(user_config.git) == 'table' and user_config.git or {}
  local footer_config = type(git_config.footer) == 'table' and git_config.footer or {}
  local resolved_settings = {}
  for setting_name, default_value in pairs(defaults) do
    resolved_settings[setting_name] = bounded_integer(
      footer_config[setting_name],
      default_value,
      limits[setting_name]
    )
  end
  resolved_settings.list_max_entries = math.max(
    resolved_settings.list_batch_entries,
    resolved_settings.list_max_entries
  )
  resolved_settings.list_margin_entries = math.min(
    resolved_settings.list_margin_entries,
    math.max(1, resolved_settings.list_batch_entries - 1)
  )
  resolved_settings.preview_headroom_entries = math.min(
    resolved_settings.preview_headroom_entries,
    resolved_settings.list_batch_entries - 1
  )
  return resolved_settings
end

return M
