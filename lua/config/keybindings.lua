-- Shared key vocabulary. Features provide semantic handlers, never key suffixes.
local M = {}

local selection = {
  { '<cr>', 'select', 'Open or activate selection' },
  { 'o', 'select', 'Open or activate selection' },
}

local tree = vim.list_extend(vim.deepcopy(selection), {
  { 'zo', 'expand', 'Expand node' },
  { 'zc', 'collapse', 'Collapse node' },
  { 'za', 'toggle', 'Toggle node' },
  { 'zR', 'expand_all', 'Expand tree' },
  { 'zM', 'collapse_all', 'Collapse tree' },
  { '/', 'search_forward', 'Search tree forward' },
  { '?', 'search_backward', 'Search tree backward' },
  { 'n', 'next_match', 'Next tree match' },
  { 'N', 'previous_match', 'Previous tree match' },
})

local families = {
  selection = selection,
  tree = tree,
  directions = {
    { 'h', 'left', 'left' },
    { 'j', 'down', 'down' },
    { 'k', 'up', 'up' },
    { 'l', 'right', 'right' },
  },
}

function M.dispatch(adapter, action, ...)
  local handler = adapter[action]
  if type(handler) ~= 'function' then return false end
  if adapter.before_action then adapter.before_action(action) end
  handler(...)
  return true
end

function M.mappings(family, adapter, options)
  local policy = options or {}
  local mappings = {}
  for _, binding in ipairs(assert(families[family], 'Unknown keybinding family: ' .. family)) do
    local suffix, action, description = unpack(binding)
    local handler = adapter[action]
    if handler then
      local key = (policy.prefix or '') .. (policy.key_format or '%s'):format(suffix)
      local rhs = type(handler) == 'string' and handler or function(...) M.dispatch(adapter, action, ...) end
      mappings[#mappings + 1] = {
        policy.mode or 'n', key, rhs,
        { desc = (policy.description or '') .. description, silent = true },
      }
    end
  end
  return mappings
end

function M.attach(family, buffer, adapter, options)
  for _, mapping in ipairs(M.mappings(family, adapter, options)) do
    local map_options = vim.tbl_extend('force', mapping[4], { buffer = buffer })
    vim.keymap.set(mapping[1], mapping[2], mapping[3], map_options)
  end
end

return M
