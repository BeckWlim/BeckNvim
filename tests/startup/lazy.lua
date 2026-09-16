-- Focused tests for personal development settings at plugin bootstrap.
local original_lazy = package.loaded.lazy
local original_user = package.loaded['config.user']
local original_proxy = package.loaded['config.network.proxy']
local original_runtimepath = vim.o.runtimepath
local original_fs_stat = vim.uv.fs_stat
local captured_options = {}
local current_user_config = {}

package.loaded.lazy = {
  setup = function(spec, options)
    assert(spec == 'plugins', 'Bootstrap lost the plugin import')
    captured_options = options
  end,
}
package.loaded['config.user'] = {
  get = function()
    return current_user_config
  end,
}
package.loaded['config.network.proxy'] = {
  initialize = function() end,
}
vim.uv.fs_stat = function(path)
  if path == vim.fn.stdpath('data') .. '/lazy/lazy.nvim' then
    return { type = 'directory' }
  end
  return original_fs_stat(path)
end

local function bootstrap(settings)
  current_user_config = settings
  dofile('lua/config/startup/lazy.lua')
  return captured_options.dev
end

local default_dev = bootstrap({})
assert(#default_dev.patterns == 0, 'Development mode must be opt-in')
assert(default_dev.path == vim.fn.expand('~/.config'), 'Unexpected default checkout parent')
assert(default_dev.fallback == false, 'Missing development checkouts must not silently fall back')

local enabled_dev = bootstrap({
  dev = { enabled = true, path = '~/plugin projects', patterns = { 'BeckWlim/termaid', 'folke/' } },
})
assert(enabled_dev.path == vim.fn.expand('~/plugin projects'), 'Checkout parent was not expanded')
assert(vim.deep_equal(enabled_dev.patterns, { 'BeckWlim/termaid', 'folke/' }), 'Plugin selection was lost')

local disabled_dev = bootstrap({ dev = { enabled = false, patterns = { 'BeckWlim/termaid' } } })
assert(#disabled_dev.patterns == 0, 'Disabled mode still selects local plugins')
local string_enabled_dev = bootstrap({ dev = { enabled = 'true', patterns = { 'BeckWlim/termaid' } } })
assert(#string_enabled_dev.patterns == 0, 'Development mode requires a boolean switch')

for _, invalid_dev in ipairs({ false, 'invalid', 42 }) do
  assert(#bootstrap({ dev = invalid_dev }).patterns == 0, 'Invalid settings enabled development mode')
end
local invalid_fields_dev = bootstrap({ dev = { enabled = true, path = 42, patterns = 'termaid' } })
assert(invalid_fields_dev.path == default_dev.path, 'Invalid path did not use the default')
assert(#invalid_fields_dev.patterns == 0, 'Invalid pattern list reached lazy.nvim')
local filtered_dev = bootstrap({ dev = { enabled = true, path = '', patterns = { '', false, 'termaid' } } })
assert(filtered_dev.path == default_dev.path, 'Empty path did not use the default')
assert(vim.deep_equal(filtered_dev.patterns, { 'termaid' }), 'Invalid patterns were not filtered')

local termaid_spec = dofile('lua/plugins/termaid.lua')[1]
assert(termaid_spec.dir == nil, 'Hardcoded Termaid checkout bypasses development mode')
assert(termaid_spec.branch == 'main' and termaid_spec.version == false, 'Termaid lost its remote source policy')
assert(termaid_spec.build:find('--reinstall -e .', 1, true), 'Termaid development builds must stay editable')

vim.uv.fs_stat = original_fs_stat
vim.o.runtimepath = original_runtimepath
package.loaded.lazy = original_lazy
package.loaded['config.user'] = original_user
package.loaded['config.network.proxy'] = original_proxy
