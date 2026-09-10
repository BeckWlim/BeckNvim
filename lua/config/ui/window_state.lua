local M = {}
local option_resolvers_by_filetype = {}

function M.register(filetype, option_resolver)
  if type(filetype) ~= 'string' or filetype == '' then
    error('window-state filetype must be a non-empty string')
  end
  if type(option_resolver) ~= 'function' then
    error('window-state option resolver must be a function')
  end
  option_resolvers_by_filetype[filetype] = option_resolver
end

function M.resolve(winid, option_names)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  local window_buffer = vim.api.nvim_win_get_buf(winid)
  local window_filetype = vim.bo[window_buffer].filetype
  local option_resolver = option_resolvers_by_filetype[window_filetype]
  local registered_options = option_resolver and option_resolver(winid) or nil
  local resolved_options = {}
  for _, option_name in ipairs(option_names) do
    local registered_value = registered_options and registered_options[option_name]
    if registered_value ~= nil then
      resolved_options[option_name] = registered_value
    else
      resolved_options[option_name] = vim.wo[winid][option_name]
    end
  end
  return resolved_options
end

return M
