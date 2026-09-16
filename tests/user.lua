-- Read personal assignment settings without executing a shell.
local original_user = package.loaded['config.user']
local original_expand = vim.fn.expand
local original_notify = vim.notify
local config_path = vim.fn.tempname()
local notifications = {}
vim.fn.expand = function(path, ...)
  if path == '~/.nvim' then
    return config_path
  end
  return original_expand(path, ...)
end
rawset(vim, 'notify', function(message)
  notifications[#notifications + 1] = message
end)
package.loaded['config.user'] = nil
local user = require('config.user')

local function read_lines(lines)
  vim.fn.writefile(lines, config_path)
  user.reset()
  return user.get()
end

local assignment_config = read_lines({
  'http_proxy=http://172.25.160.1:7890',
  'https_proxy=http://172.25.160.1:7890',
  '# NO_PROXY=localhost,127.0.0.1',
  '',
  'NVIM_DEV=true # local development',
  'export NVIM_DEV_PATH="~/plugin projects" # checkout parent',
  "NVIM_DEV_PLUGINS='BeckWlim/termaid, folke/'",
})
assert(assignment_config.proxy_environment.http_proxy == 'http://172.25.160.1:7890')
assert(assignment_config.proxy_environment.https_proxy == 'http://172.25.160.1:7890')
assert(assignment_config.proxy_environment.NO_PROXY == nil, 'Commented proxy setting was enabled')
assert(assignment_config.proxy_environment.NVIM_DEV == nil, 'Dev settings leaked into proxy settings')
assert(assignment_config.dev.enabled == true)
assert(assignment_config.dev.path == '~/plugin projects')
assert(vim.deep_equal(assignment_config.dev.patterns, { 'BeckWlim/termaid', 'folke/' }))

local literal_config = read_lines({
  'NVIM_DEV_PATH="$(touch /tmp/should-not-exist)"',
  "http_proxy='http://example.test:7890/#fragment' # retain quoted hash",
})
assert(literal_config.dev.path == '$(touch /tmp/should-not-exist)', 'Shell expression was expanded')
assert(literal_config.proxy_environment.http_proxy == 'http://example.test:7890/#fragment')
assert(read_lines({ 'NVIM_DEV=1' }).dev.enabled == true)
for _, disabled_value in ipairs({ 'false', '0', 'invalid', '' }) do
  assert(read_lines({ 'NVIM_DEV=' .. disabled_value }).dev.enabled == false)
end
assert(#read_lines({ 'NVIM_DEV_PLUGINS=""' }).dev.patterns == 0)

local json_config = read_lines({ '{"dev":{"enabled":true},"git":{"footer":{"detail_worker_count":8}}}' })
assert(json_config.dev.enabled == true and json_config.git.footer.detail_worker_count == 8)
local empty_config = read_lines({ '', '# Only comments' })
assert(next(empty_config.proxy_environment) == nil)
vim.wait(10)
assert(#notifications == 0, 'Valid assignment settings produced a warning')

local invalid_config = read_lines({ '{broken json' })
assert(next(invalid_config) == nil)
vim.wait(100, function() return #notifications == 1 end)
assert(#notifications == 1 and notifications[1]:find('NAME=value', 1, true))

local template_config = read_lines(vim.fn.readfile('.nvim.template'))
assert(template_config.dev.enabled == false, 'Template must keep dev mode opt-in')
assert(template_config.dev.path == '~/.config')
assert(vim.deep_equal(template_config.dev.patterns, { 'BeckWlim/termaid' }))

vim.fn.delete(config_path)
vim.fn.expand = original_expand
rawset(vim, 'notify', original_notify)
package.loaded['config.user'] = original_user
