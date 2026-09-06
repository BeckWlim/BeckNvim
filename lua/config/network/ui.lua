local proxy = require('config.network.proxy')

local M = {}
local configured = false
local default_no_proxy = 'localhost,127.0.0.1,::1'
local maximum_picker_width = 72
local maximum_picker_height = 16

local function compact_layout(columns, lines)
  local available_width = math.max(columns - 4, 1)
  local available_height = math.max(lines - 4, 1)
  return {
    width = math.min(maximum_picker_width, available_width),
    height = math.min(maximum_picker_height, available_height),
  }
end

local function compact_address(proxy_address)
  if not proxy_address then
    return 'DIRECT'
  end
  local address_without_scheme = proxy_address:gsub('^%a[%w+.-]*://', '')
  local authority = address_without_scheme:match('^[^/]+') or address_without_scheme
  return authority:gsub('^.-@', '')
end

local function route_source(proxy_environment, environment_name, source_name)
  if proxy_environment[environment_name] then
    return source_name
  end
  if proxy_environment.ALL_PROXY then
    return 'ALL_PROXY fallback'
  end
  return 'direct'
end

local function active_route_groups(proxy_environment)
  local all_proxy = proxy_environment.ALL_PROXY
  local route_specs = {
    {
      name = 'HTTP',
      address = proxy_environment.http_proxy or all_proxy,
      source = route_source(proxy_environment, 'http_proxy', 'HTTP_PROXY'),
    },
    {
      name = 'HTTPS',
      address = proxy_environment.https_proxy or all_proxy,
      source = route_source(proxy_environment, 'https_proxy', 'HTTPS_PROXY'),
    },
    {
      name = 'OTHER',
      address = all_proxy,
      source = all_proxy and 'ALL_PROXY' or 'direct',
    },
  }
  local groups = {}
  local group_indexes = {}
  for _, route_spec in ipairs(route_specs) do
    local group_key = compact_address(route_spec.address)
    local group_index = group_indexes[group_key]
    if not group_index then
      groups[#groups + 1] = {
        address = route_spec.address,
        routes = {},
      }
      group_index = #groups
      group_indexes[group_key] = group_index
    end
    local group = groups[group_index]
    group.routes[#group.routes + 1] = route_spec
  end
  return groups
end

local function status_headlines(proxy_environment)
  local endpoint_labels = {}
  for _, route_group in ipairs(active_route_groups(proxy_environment)) do
    if route_group.address then
      endpoint_labels[#endpoint_labels + 1] = compact_address(route_group.address)
    end
  end
  local proxy_headline = 'PROXY OFF'
  if #endpoint_labels > 0 then
    proxy_headline = 'PROXY ON · ' .. table.concat(endpoint_labels, ' + ')
  end
  local no_proxy_headline = 'NO_PROXY OFF'
  if proxy_environment.NO_PROXY then
    no_proxy_headline = 'NO_PROXY ON · ' .. proxy_environment.NO_PROXY
  end
  return proxy_headline, no_proxy_headline
end

local function current_status(proxy_environment)
  local proxy_headline, no_proxy_headline = status_headlines(proxy_environment)
  return proxy_headline .. ' · ' .. no_proxy_headline
end

local function add_address_entry(entries, seen_addresses, address, source)
  if not address or seen_addresses[address] then
    return
  end
  seen_addresses[address] = true
  entries[#entries + 1] = {
    action = 'proxy',
    address = address,
    display = ('Use %-10s %s'):format(source, address),
    ordinal = ('proxy %s %s'):format(source, address),
  }
end

function M.entries(proxy_environment, shell_environment, recent_addresses)
  local active_proxy = proxy_environment or {}
  local shell_proxy = shell_environment or {}
  local known_recent_addresses = recent_addresses or {}
  local proxy_headline, no_proxy_headline = status_headlines(active_proxy)
  local route_groups = active_route_groups(active_proxy)
  local entries = {
    {
      action = 'status',
      display = '● ' .. proxy_headline,
      ordinal = 'current active proxy routes status ' .. current_status(active_proxy),
    },
    {
      action = 'edit_no_proxy',
      no_proxy = active_proxy.NO_PROXY or '',
      display = '✎ ' .. no_proxy_headline .. '  (Enter to edit)',
      ordinal = 'edit current no_proxy bypass hosts ' .. (active_proxy.NO_PROXY or 'none'),
    },
  }
  local show_group_parents = #route_groups > 1
  for _, route_group in ipairs(route_groups) do
    local route_names = vim.tbl_map(function(route)
      return route.name
    end, route_group.routes)
    if show_group_parents then
      entries[#entries + 1] = {
        action = 'status',
        display = ('  ● %s  [%s]'):format(
          compact_address(route_group.address),
          table.concat(route_names, ', ')
        ),
        ordinal = ('current proxy %s %s'):format(
          compact_address(route_group.address),
          table.concat(route_names, ' ')
        ),
      }
    end
    for route_index, route in ipairs(route_group.routes) do
      local branch = route_index == #route_group.routes and '└─' or '├─'
      local indentation = show_group_parents and '      ' or '  '
      entries[#entries + 1] = {
        action = 'status',
        display = ('%s%s %-5s %s  (%s)'):format(
          indentation,
          branch,
          route.name,
          route.address or 'DIRECT',
          route.source
        ),
        ordinal = ('current route %s %s %s'):format(
          route.name,
          route.address or 'direct',
          route.source
        ),
      }
    end
  end
  entries[#entries + 1] = {
    action = 'bypass',
    no_proxy = default_no_proxy,
    display = '○ Use default NO_PROXY  ' .. default_no_proxy,
    ordinal = 'default no_proxy bypass localhost loopback',
  }
  entries[#entries + 1] = {
    action = 'bypass',
    no_proxy = '',
    display = '○ Clear NO_PROXY',
    ordinal = 'clear no_proxy bypass none',
  }
  entries[#entries + 1] = {
    action = 'direct',
    display = '○ Direct connection',
    ordinal = 'direct connection off none',
  }
  local seen_addresses = {}
  add_address_entry(entries, seen_addresses, active_proxy.http_proxy, 'HTTP')
  add_address_entry(entries, seen_addresses, active_proxy.https_proxy, 'HTTPS')
  add_address_entry(entries, seen_addresses, active_proxy.ALL_PROXY, 'ALL')
  add_address_entry(entries, seen_addresses, shell_proxy.http_proxy, 'config')
  add_address_entry(entries, seen_addresses, shell_proxy.https_proxy, 'config')
  add_address_entry(entries, seen_addresses, shell_proxy.ALL_PROXY, 'config')
  for _, recent_address in ipairs(known_recent_addresses) do
    add_address_entry(entries, seen_addresses, recent_address, 'recent')
  end
  entries[#entries + 1] = {
    action = 'help',
    display = '+ Input: host:port | bypass-list, or NO_PROXY=bypass-list',
    ordinal = 'custom input proxy no_proxy help',
  }
  return entries
end

function M.parse_input(input)
  local normalized_input = vim.trim(input or '')
  if normalized_input == '' then
    return nil
  end
  if normalized_input:lower() == 'direct'
      or normalized_input:lower() == 'off'
      or normalized_input:lower() == 'none' then
    return { action = 'direct' }
  end
  local assignment_name, assignment_value = normalized_input:match('^([%a_]+)%s*=%s*(.*)$')
  if assignment_name and assignment_name:lower() == 'no_proxy' then
    return {
      action = 'bypass',
      no_proxy = assignment_value,
    }
  end
  local address_with_bypass, bypass = normalized_input:match('^(.-)%s*|%s*(.*)$')
  local address = vim.trim(address_with_bypass or normalized_input)
  if address == '' then
    return {
      action = 'bypass',
      no_proxy = bypass or '',
    }
  end
  if not proxy.valid_address(address) then
    return {
      action = 'invalid',
      address = address,
    }
  end
  return {
    action = 'proxy',
    address = proxy.normalize_address(address),
    no_proxy = bypass,
  }
end

function M.resolve_choice(input, selected_choice)
  local custom_choice = M.parse_input(input)
  if custom_choice and custom_choice.action ~= 'invalid' then
    return custom_choice
  end
  local normalized_input = vim.trim(input or '')
  if custom_choice
      and (normalized_input:find(':', 1, true)
        or normalized_input:find('|', 1, true)
        or normalized_input:find('%s')) then
    return custom_choice
  end
  return selected_choice or custom_choice
end

local function notify_status(proxy_environment)
  vim.notify(current_status(proxy_environment), vim.log.levels.INFO)
end

local function notify_persistence_error(persistence_error)
  if persistence_error then
    vim.notify(
      'Proxy is active for this session but could not be saved: ' .. persistence_error,
      vim.log.levels.WARN
    )
  end
end

local function refresh_consumers()
  local translation = package.loaded['config.translation']
  if translation and type(translation.refresh_proxy) == 'function' then
    translation.refresh_proxy()
  end
end

local function apply_choice(choice)
  if not choice then
    return false
  end
  if choice.action == 'status' then
    notify_status(proxy.resolve())
    return false
  end
  if choice.action == 'help' then
    vim.notify(
      'Type host:port or a proxy URL; append " | host1,host2" to set NO_PROXY',
      vim.log.levels.INFO
    )
    return false
  end
  if choice.action == 'invalid' then
    vim.notify(
      ('Invalid proxy address: %s (expected host:port or scheme://address)'):format(
        choice.address
      ),
      vim.log.levels.WARN
    )
    return false
  end
  if choice.action == 'direct' then
    local direct_environment, _direct_label, persistence_error = proxy.set_session(nil, nil)
    refresh_consumers()
    notify_status(direct_environment)
    notify_persistence_error(persistence_error)
    return true
  end
  if choice.action == 'bypass' then
    local updated_environment, _updated_label, persistence_error = proxy.set_no_proxy(
      choice.no_proxy
    )
    refresh_consumers()
    notify_status(updated_environment)
    notify_persistence_error(persistence_error)
    return true
  end
  if choice.action == 'proxy' then
    local updated_environment, _updated_label, persistence_error = proxy.set_session(
      choice.address,
      choice.no_proxy
    )
    refresh_consumers()
    notify_status(updated_environment)
    notify_persistence_error(persistence_error)
    return true
  end
  return false
end

local function shell_proxy()
  local local_config = require('config.user').get()
  return proxy.from_environment(local_config.proxy_environment or {}) or {}
end

function M.open()
  local picker_options = {
    layout_strategy = 'center',
    layout_config = compact_layout(vim.o.columns, vim.o.lines),
  }
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local telescope_config = require('telescope.config').values

  local function active_environment()
    return proxy.resolve()
  end

  local function entries()
    return M.entries(active_environment(), shell_proxy(), proxy.recent_addresses())
  end

  local function finder()
    return finders.new_table({
      entry_maker = function(entry)
        return entry
      end,
      results = entries(),
    })
  end

  local function title()
    return 'Proxy manager · Enter: apply/edit · q/Ctrl-Q: close'
  end

  local function refresh_picker(picker)
    picker:refresh(finder(), { reset_prompt = true })
    picker.prompt_title = title()
    local prompt_border = picker.layout and picker.layout.prompt and picker.layout.prompt.border
    if prompt_border and prompt_border.change_title then
      prompt_border:change_title(picker.prompt_title)
    end
  end

  pickers.new(picker_options, {
    prompt_title = title(),
    finder = finder(),
    previewer = false,
    sorter = telescope_config.generic_sorter(picker_options),
    attach_mappings = function(prompt_buffer)
      require('telescope.actions').select_default:replace(function()
        local action_state = require('telescope.actions.state')
        local selected_choice = action_state.get_selected_entry()
        local choice = M.resolve_choice(action_state.get_current_line(), selected_choice)
        local picker = action_state.get_current_picker(prompt_buffer)
        if choice and choice.action == 'edit_no_proxy' then
          picker:set_prompt('NO_PROXY=' .. choice.no_proxy)
          return
        end
        if apply_choice(choice) then
          refresh_picker(picker)
        end
      end)
      return true
    end,
  }):find()
end

function M.setup()
  if configured then
    return
  end
  configured = true
  vim.api.nvim_create_user_command('Proxy', M.open, {
    desc = 'Inspect or change the shared session proxy',
  })
end

M.apply_choice = apply_choice
M.active_route_groups = active_route_groups
M.compact_layout = compact_layout
M.current_status = current_status
M.default_no_proxy = default_no_proxy

return M
