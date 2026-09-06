local M = {}
local persistence_path
local session_override
local recent_proxy_addresses = {}
local persistence_version = 1

local proxy_names = {
  ALL_PROXY = 'ALL_PROXY',
  HTTP_PROXY = 'http_proxy',
  HTTPS_PROXY = 'https_proxy',
  NO_PROXY = 'NO_PROXY',
  all_proxy = 'ALL_PROXY',
  http_proxy = 'http_proxy',
  https_proxy = 'https_proxy',
  no_proxy = 'NO_PROXY',
}

local environment_candidates = {
  { canonical_name = 'http_proxy', names = { 'http_proxy', 'HTTP_PROXY' } },
  { canonical_name = 'https_proxy', names = { 'https_proxy', 'HTTPS_PROXY' } },
  { canonical_name = 'ALL_PROXY', names = { 'all_proxy', 'ALL_PROXY' } },
  { canonical_name = 'NO_PROXY', names = { 'no_proxy', 'NO_PROXY' } },
}

local persisted_environment_names = {
  'http_proxy',
  'https_proxy',
  'ALL_PROXY',
  'NO_PROXY',
}

local function nonempty(value)
  return type(value) == 'string' and vim.trim(value) ~= ''
end

local function normalized_proxy_url(value)
  if not nonempty(value) then
    return nil
  end
  local trimmed_value = vim.trim(value)
  if trimmed_value:match('^%a[%w+.-]*://') then
    return trimmed_value
  end
  if trimmed_value:match('^[%w._-]+:%d+$') or trimmed_value:match('^%[[%x:]+%]:%d+$') then
    return 'http://' .. trimmed_value
  end
  return trimmed_value
end

local function proxy_label(proxy_url)
  if not proxy_url then
    return nil
  end
  local authority = proxy_url:gsub('^%a[%w+.-]*://', ''):match('^[^/]+') or proxy_url
  return authority:gsub('^.-@', '')
end

local function default_persistence_path()
  return vim.fs.joinpath(vim.fn.stdpath('state'), 'proxy.json')
end

local function active_persistence_path()
  return persistence_path or default_persistence_path()
end

local function normalized_persisted_environment(raw_environment)
  if type(raw_environment) ~= 'table'
      or (vim.islist(raw_environment) and next(raw_environment) ~= nil) then
    return nil, 'saved proxy environment is not an object'
  end
  local proxy_environment = {}
  for _, environment_name in ipairs(persisted_environment_names) do
    local environment_value = raw_environment[environment_name]
    if environment_value ~= nil then
      if type(environment_value) ~= 'string' then
        return nil, ('saved %s value is not text'):format(environment_name)
      end
      if environment_name == 'NO_PROXY' then
        if nonempty(environment_value) then
          proxy_environment.NO_PROXY = vim.trim(environment_value)
        end
      else
        local normalized_address = normalized_proxy_url(environment_value)
        if not normalized_address
            or not normalized_address:match('^%a[%w+.-]*://[^%s]+$') then
          return nil, ('saved %s proxy address is invalid'):format(environment_name)
        end
        proxy_environment[environment_name] = normalized_address
      end
    end
  end
  return proxy_environment, nil
end

local function load_persisted_environment(state_path)
  if not vim.uv.fs_stat(state_path) then
    return nil, nil
  end
  local read_succeeded, state_lines = pcall(vim.fn.readfile, state_path)
  if not read_succeeded then
    return nil, ('could not read %s'):format(state_path)
  end
  local decode_succeeded, state_document = pcall(
    vim.json.decode,
    table.concat(state_lines, '\n')
  )
  if not decode_succeeded or type(state_document) ~= 'table' then
    return nil, ('could not parse %s'):format(state_path)
  end
  if state_document.version ~= persistence_version then
    return nil, ('unsupported proxy state version in %s'):format(state_path)
  end
  return normalized_persisted_environment(state_document.environment)
end

local function persist_environment(proxy_environment)
  local state_path = active_persistence_path()
  local state_directory = vim.fs.dirname(state_path)
  local directory_created = vim.fn.mkdir(state_directory, 'p')
  if directory_created == 0 and not vim.uv.fs_stat(state_directory) then
    return ('could not create %s'):format(state_directory)
  end
  local serialized_environment = next(proxy_environment) == nil
      and vim.empty_dict()
    or proxy_environment
  local encode_succeeded, encoded_state = pcall(vim.json.encode, {
    environment = serialized_environment,
    version = persistence_version,
  })
  if not encode_succeeded then
    return 'could not encode proxy state'
  end
  local temporary_path = ('%s.tmp.%d'):format(state_path, vim.fn.getpid())
  local write_succeeded, write_result = pcall(
    vim.fn.writefile,
    { encoded_state },
    temporary_path,
    'b'
  )
  if not write_succeeded or write_result ~= 0 then
    return ('could not write %s'):format(temporary_path)
  end
  vim.uv.fs_chmod(temporary_path, 384)
  local renamed, rename_error = vim.uv.fs_rename(temporary_path, state_path)
  if not renamed then
    vim.uv.fs_unlink(temporary_path)
    return ('could not replace %s: %s'):format(state_path, rename_error or 'unknown error')
  end
  return nil
end

local function remember_proxy_address(proxy_url)
  if not proxy_url then
    return
  end
  for _, recent_address in ipairs(recent_proxy_addresses) do
    if recent_address == proxy_url then
      return
    end
  end
  table.insert(recent_proxy_addresses, 1, proxy_url)
  if #recent_proxy_addresses > 10 then
    table.remove(recent_proxy_addresses)
  end
end

function M.classify(proxy_address, no_proxy)
  local normalized_address = normalized_proxy_url(proxy_address)
  local proxy_environment = {}
  if normalized_address then
    proxy_environment.http_proxy = normalized_address
    proxy_environment.https_proxy = normalized_address
  end
  if nonempty(no_proxy) then
    proxy_environment.NO_PROXY = vim.trim(no_proxy)
  end
  if next(proxy_environment) == nil then
    return nil
  end
  return proxy_environment
end

function M.normalize_address(proxy_address)
  return normalized_proxy_url(proxy_address)
end

function M.valid_address(proxy_address)
  local normalized_address = normalized_proxy_url(proxy_address)
  return normalized_address ~= nil
    and normalized_address:match('^%a[%w+.-]*://[^%s]+$') ~= nil
end

function M.primary_address(proxy_environment)
  local selected_environment = proxy_environment or {}
  return selected_environment.https_proxy
    or selected_environment.http_proxy
    or selected_environment.ALL_PROXY
end

local function clean_shell_value(raw_value)
  local uncommented_value = raw_value:gsub('%s+#.*$', '')
  local trimmed_value = vim.trim(uncommented_value)
  local quote_character = trimmed_value:sub(1, 1)
  if (quote_character == '"' or quote_character == "'")
      and trimmed_value:sub(-1) == quote_character then
    return trimmed_value:sub(2, -2)
  end
  return trimmed_value
end

local function expand_simple_variables(raw_value, variables)
  local expanded_braces = raw_value:gsub('%${([%a_][%w_]*)}', function(variable_name)
    return variables[variable_name] or ''
  end)
  return expanded_braces:gsub('%$([%a_][%w_]*)', function(variable_name)
    return variables[variable_name] or ''
  end)
end

local function assignment(line)
  local assignment_text = line:match('^%s*export%s+(.+)$')
    or line:match('^%s*declare%s+%-x%s+(.+)$')
    or line:match('^%s*([%a_][%w_]*%s*=.+)$')
  if not assignment_text then
    return nil, nil
  end
  return assignment_text:match('^([%a_][%w_]*)%s*=%s*(.-)%s*$')
end

function M.from_environment(environment)
  local proxy_environment = {}
  for _, candidate in ipairs(environment_candidates) do
    for _, environment_name in ipairs(candidate.names) do
      local environment_value = environment[environment_name]
      if nonempty(environment_value) then
        if candidate.canonical_name == 'NO_PROXY' then
          proxy_environment.NO_PROXY = vim.trim(environment_value)
        else
          proxy_environment[candidate.canonical_name] = normalized_proxy_url(environment_value)
        end
        break
      end
    end
  end
  if next(proxy_environment) == nil then
    return nil
  end
  return proxy_environment
end

function M.from_shell_lines(lines)
  local shell_variables = {}
  local proxy_environment = {}
  for _, line in ipairs(lines) do
    local variable_name, raw_value = assignment(line)
    if variable_name and raw_value then
      local cleaned_value = clean_shell_value(raw_value)
      local expanded_value = expand_simple_variables(cleaned_value, shell_variables)
      if nonempty(expanded_value)
          and not expanded_value:find('`', 1, true)
          and not expanded_value:find('$(', 1, true) then
        shell_variables[variable_name] = expanded_value
        local canonical_name = proxy_names[variable_name]
        if canonical_name then
          proxy_environment[canonical_name] = canonical_name == 'NO_PROXY'
              and vim.trim(expanded_value)
            or normalized_proxy_url(expanded_value)
        end
      end
    end
  end
  local generic_proxy = shell_variables.proxy or shell_variables.PROXY
  local classified_proxy = M.classify(generic_proxy, nil) or {}
  local resolved_proxy_environment = vim.tbl_extend('keep', proxy_environment, classified_proxy)
  if next(resolved_proxy_environment) == nil then
    return nil
  end
  return resolved_proxy_environment
end

function M.from_bashrc(bashrc_path)
  if not bashrc_path or not vim.uv.fs_stat(bashrc_path) then
    return nil
  end
  local read_succeeded, bashrc_lines = pcall(vim.fn.readfile, bashrc_path)
  if not read_succeeded then
    return nil
  end
  return M.from_shell_lines(bashrc_lines)
end

local function default_bashrc_path()
  local home_directory = vim.uv.os_homedir()
  if not home_directory or home_directory == '' then
    return nil
  end
  return vim.fs.joinpath(home_directory, '.bashrc')
end

local function resolve_bashrc_path(requested_bashrc_path)
  if requested_bashrc_path ~= nil then
    return requested_bashrc_path
  end
  return default_bashrc_path()
end

function M.resolve(options)
  if options == nil and session_override ~= nil then
    local active_override = vim.deepcopy(session_override)
    return active_override, proxy_label(M.primary_address(active_override))
  end
  local resolve_options = options or {}
  local process_environment = resolve_options.environment or vim.env
  local local_config = require('config.user').get()
  local configured_proxy = M.from_environment(local_config.proxy_environment or {}) or {}
  local environment_proxy = M.from_environment(process_environment) or {}
  local legacy_proxy = {}
  if resolve_options.bashrc_path then
    legacy_proxy = M.from_bashrc(resolve_options.bashrc_path) or {}
  end
  local resolved_proxy = vim.tbl_extend('keep', environment_proxy, legacy_proxy, configured_proxy)
  if next(resolved_proxy) == nil then
    return {}, nil
  end
  local label = proxy_label(
    resolved_proxy.https_proxy or resolved_proxy.http_proxy or resolved_proxy.ALL_PROXY
  )
  return resolved_proxy, label
end

local function clear_process_proxy()
  for _, environment_name in ipairs({
    'http_proxy',
    'HTTP_PROXY',
    'https_proxy',
    'HTTPS_PROXY',
    'all_proxy',
    'ALL_PROXY',
    'no_proxy',
    'NO_PROXY',
  }) do
    vim.env[environment_name] = nil
  end
end

local function apply_process_proxy(proxy_environment)
  clear_process_proxy()
  for environment_name, environment_value in pairs(proxy_environment) do
    vim.env[environment_name] = environment_value
  end
end

local function activate_session(proxy_environment, should_persist)
  local selected_environment = vim.deepcopy(proxy_environment)
  session_override = selected_environment
  apply_process_proxy(selected_environment)
  remember_proxy_address(M.primary_address(selected_environment))
  local persistence_error = should_persist and persist_environment(selected_environment) or nil
  return vim.deepcopy(selected_environment),
    proxy_label(M.primary_address(selected_environment)),
    persistence_error
end

function M.initialize_direct()
  return activate_session({}, true)
end

function M.initialize(options)
  local initialize_options = options or {}
  persistence_path = initialize_options.state_path or default_persistence_path()
  local persisted_environment, persistence_error = load_persisted_environment(persistence_path)
  local initial_environment = persisted_environment or {}
  local active_environment, label = activate_session(initial_environment, false)
  return active_environment, label, persistence_error
end

function M.set_session(proxy_address, no_proxy)
  local current_proxy = M.resolve()
  local selected_no_proxy = no_proxy
  if selected_no_proxy == nil then
    selected_no_proxy = current_proxy.NO_PROXY
  end
  local selected_proxy = M.classify(proxy_address, selected_no_proxy) or {}
  return activate_session(selected_proxy, true)
end

function M.set_no_proxy(no_proxy)
  local current_proxy = M.resolve()
  local updated_proxy = vim.deepcopy(current_proxy)
  if nonempty(no_proxy) then
    updated_proxy.NO_PROXY = vim.trim(no_proxy)
  else
    updated_proxy.NO_PROXY = nil
  end
  return activate_session(updated_proxy, true)
end

function M.reset_session_override()
  session_override = nil
end

function M.recent_addresses()
  return vim.deepcopy(recent_proxy_addresses)
end

function M.enable(options)
  local resolved_proxy, label = M.resolve(options)
  for environment_name, environment_value in pairs(resolved_proxy) do
    vim.env[environment_name] = environment_value
  end
  return resolved_proxy, label
end

return M
