local proxy = require('config.network.proxy')
local proxy_ui = require('config.network.ui')

local large_proxy_layout = proxy_ui.compact_layout(240, 80)
assert(
  large_proxy_layout.width == 72 and large_proxy_layout.height == 16,
  'Proxy manager exceeded its compact maximum dimensions'
)
local small_proxy_layout = proxy_ui.compact_layout(60, 14)
assert(
  small_proxy_layout.width == 56 and small_proxy_layout.height == 10,
  'Proxy manager did not shrink to the available editor dimensions'
)

local environment_proxy = proxy.from_environment({
  HTTP_PROXY = 'http://uppercase.example:8080',
  http_proxy = 'http://lowercase.example:8080',
  HTTPS_PROXY = 'https://secure.example:8443',
})
assert(
  environment_proxy.http_proxy == 'http://lowercase.example:8080',
  'Lowercase proxy variables did not take deterministic precedence'
)
assert(
  environment_proxy.https_proxy == 'https://secure.example:8443',
  'Uppercase HTTPS proxy was not normalized for subprocesses'
)
assert(proxy.from_environment({ http_proxy = '' }) == nil, 'Empty proxy values were retained')

local classified_proxy = proxy.classify('127.0.0.1:7890', 'localhost,127.0.0.1,.internal')
assert(
  classified_proxy.http_proxy == 'http://127.0.0.1:7890'
    and classified_proxy.https_proxy == 'http://127.0.0.1:7890',
  'Direct IP:port proxy configuration was not normalized for Git and curl'
)
assert(
  classified_proxy.NO_PROXY == 'localhost,127.0.0.1,.internal',
  'Direct no_proxy bypass configuration was lost'
)

local shell_proxy = proxy.from_shell_lines({
  'proxy_address="127.0.0.1:7890"',
  'proxy_on() {',
  '  export http_proxy=$proxy_address',
  '  export https_proxy="${proxy_address}" # preferred network route',
  "  export ALL_PROXY='socks5://127.0.0.1:7891'",
  '}',
})
assert(shell_proxy.http_proxy == 'http://127.0.0.1:7890', 'Bash IP:port proxy was not normalized')
assert(shell_proxy.https_proxy == 'http://127.0.0.1:7890', 'Quoted Bash proxy was not detected')
assert(shell_proxy.ALL_PROXY == 'socks5://127.0.0.1:7891', 'Bash SOCKS proxy was not detected')

local temporary_bashrc = vim.fn.tempname()
vim.fn.writefile({
  'export http_proxy=http://bashrc.example:7890',
  'export https_proxy=http://bashrc.example:7890',
}, temporary_bashrc)
local resolved_proxy, proxy_label = proxy.resolve({
  bashrc_path = temporary_bashrc,
  environment = { http_proxy = 'http://environment.example:9000' },
})
assert(
  resolved_proxy.http_proxy == 'http://environment.example:9000',
  'Process environment did not override ~/.bashrc proxy discovery'
)
assert(
  resolved_proxy.https_proxy == 'http://bashrc.example:7890',
  '~/.bashrc did not fill a missing process proxy variable'
)
assert(proxy_label == 'bashrc.example:7890', 'Resolved proxy label was not sanitized')
vim.fn.delete(temporary_bashrc)

local previous_http_proxy = vim.env.http_proxy
local enabled_proxy = proxy.enable({
  bashrc_path = '/missing/bashrc',
  environment = { http_proxy = 'http://enabled.example:8080' },
})
assert(enabled_proxy.http_proxy == 'http://enabled.example:8080', 'Proxy enable lost its result')
assert(
  vim.env.http_proxy == 'http://enabled.example:8080',
  'Proxy enable did not activate discovery for inherited GitHub processes'
)
vim.env.http_proxy = previous_http_proxy

assert(proxy.valid_address('127.0.0.1:7890'), 'Proxy UI rejected an IP:port address')
assert(proxy.valid_address('socks5h://localhost:7891'), 'Proxy UI rejected a SOCKS URL')
assert(not proxy.valid_address('not a proxy'), 'Proxy UI accepted an invalid address')

local parsed_custom_proxy = proxy_ui.parse_input(
  '127.0.0.1:7890 | localhost,127.0.0.1'
)
assert(parsed_custom_proxy.action == 'proxy', 'Proxy input did not select a custom address')
assert(
  parsed_custom_proxy.address == 'http://127.0.0.1:7890',
  'Proxy input did not normalize IP:port'
)
assert(
  parsed_custom_proxy.no_proxy == 'localhost,127.0.0.1',
  'Proxy input lost its bypass list'
)
assert(proxy_ui.parse_input('direct').action == 'direct', 'Direct proxy input was not recognized')
assert(proxy_ui.parse_input('invalid proxy').action == 'invalid', 'Invalid proxy input was accepted')
local parsed_no_proxy = proxy_ui.parse_input('NO_PROXY=localhost,.internal')
assert(
  parsed_no_proxy.action == 'bypass' and parsed_no_proxy.no_proxy == 'localhost,.internal',
  'Explicit NO_PROXY input was not recognized'
)
assert(
  proxy_ui.parse_input('no_proxy=').no_proxy == '',
  'Empty NO_PROXY input could not clear the bypass list'
)
local filtered_proxy_choice = { action = 'direct' }
assert(
  proxy_ui.resolve_choice('dir', filtered_proxy_choice) == filtered_proxy_choice,
  'Proxy list filtering overrode the selected action with invalid custom input'
)

local listed_proxies = proxy_ui.entries({
  http_proxy = 'http://active.example:8080',
  https_proxy = 'http://active.example:8080',
  NO_PROXY = 'localhost',
}, {
  ALL_PROXY = 'socks5h://shell.example:1080',
}, {
  'http://recent.example:9000',
})
assert(listed_proxies[1].display:match('PROXY ON'), 'Proxy UI lost its primary ON status')
assert(
  listed_proxies[1].display:match('active%.example:8080'),
  'Proxy UI did not put the active endpoint in its primary status'
)
assert(listed_proxies[1].action == 'status', 'Proxy UI exposed active status as an action')
assert(
  proxy_ui.current_status({
    http_proxy = 'http://shared.example:8080',
    https_proxy = 'http://shared.example:8080',
  }) == 'PROXY ON · shared.example:8080 · NO_PROXY OFF',
  'Proxy UI did not expose one clear active endpoint'
)
assert(
  proxy_ui.current_status({
    http_proxy = 'http://web.example:8080',
    ALL_PROXY = 'socks5h://all.example:1080',
  }) == 'PROXY ON · web.example:8080 + all.example:1080 · NO_PROXY OFF',
  'Proxy UI did not list distinct active endpoints clearly'
)
assert(
  proxy_ui.current_status({
    http_proxy = 'http://shared.example:8080',
    ALL_PROXY = 'socks5h://shared.example:8080',
  }) == 'PROXY ON · shared.example:8080 · NO_PROXY OFF',
  'Proxy UI treated different schemes on one endpoint as separate proxies'
)
assert(
  vim.iter(listed_proxies):any(function(entry)
    return entry.action == 'edit_no_proxy'
      and entry.display:match('NO_PROXY')
      and entry.display:match('localhost')
  end),
  'Proxy UI did not list the bypass configuration'
)
assert(
  vim.iter(listed_proxies):any(function(entry)
    return entry.action == 'bypass' and entry.no_proxy == proxy_ui.default_no_proxy
  end),
  'Proxy UI did not provide the default NO_PROXY choice'
)
assert(
  vim.iter(proxy_ui.entries({}, {}, {})):any(function(entry)
    return entry.display:match('HTTP') and entry.display:match('%(direct%)')
  end),
  'Proxy UI could not render direct-route child details'
)
assert(
  vim.iter(listed_proxies):any(function(entry)
    return entry.address == 'socks5h://shell.example:1080'
  end),
  'Proxy UI did not list a discovered shell proxy'
)

local proxy_environment_names = {
  'http_proxy',
  'HTTP_PROXY',
  'https_proxy',
  'HTTPS_PROXY',
  'all_proxy',
  'ALL_PROXY',
  'no_proxy',
  'NO_PROXY',
}
local saved_proxy_environment = {}
for _, environment_name in ipairs(proxy_environment_names) do
  saved_proxy_environment[environment_name] = vim.env[environment_name]
  vim.env[environment_name] = nil
end

vim.env.http_proxy = 'http://web.example:8080'
vim.env.https_proxy = 'http://secure.example:8443'
vim.env.ALL_PROXY = 'socks5h://fallback.example:1080'
proxy.reset_session_override()
local bypass_only_proxy = proxy.set_no_proxy('localhost,.internal')
assert(
  bypass_only_proxy.http_proxy == 'http://web.example:8080'
    and bypass_only_proxy.https_proxy == 'http://secure.example:8443'
    and bypass_only_proxy.ALL_PROXY == 'socks5h://fallback.example:1080',
  'NO_PROXY update changed the active protocol routes'
)
assert(
  bypass_only_proxy.NO_PROXY == 'localhost,.internal',
  'NO_PROXY update did not activate the bypass list'
)

local session_proxy = proxy.set_session('session.example:8123', 'localhost,.internal')
assert(
  session_proxy.http_proxy == 'http://session.example:8123'
    and session_proxy.https_proxy == 'http://session.example:8123',
  'Session proxy did not set HTTP and HTTPS consistently'
)
assert(proxy.resolve().NO_PROXY == 'localhost,.internal', 'Session bypass was not activated')
local direct_proxy = proxy.set_session(nil, '')
assert(
  not direct_proxy.http_proxy and not direct_proxy.https_proxy,
  'Direct mode retained an active session proxy'
)
assert(
  proxy.resolve().http_proxy == nil,
  'Direct mode fell back to a discovered proxy instead of honoring the session choice'
)

proxy.reset_session_override()
for _, environment_name in ipairs(proxy_environment_names) do
  vim.env[environment_name] = saved_proxy_environment[environment_name]
end
