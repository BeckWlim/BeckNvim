local python_environment = require('config.python.environment')
local repository_root = vim.fs.normalize(vim.fn.getcwd())
local expected_python = vim.fs.joinpath(repository_root, '.venv', 'bin', 'python')
local original_executable = vim.fn.executable

vim.fn.executable = function(path)
  return path == expected_python and 1 or 0
end
local resolved_environment = python_environment.resolve(repository_root)
vim.fn.executable = original_executable

assert(resolved_environment, 'Python environment was not resolved')
assert(
  resolved_environment.directory == vim.fs.joinpath(repository_root, '.venv'),
  'Python environment used the wrong directory'
)
assert(
  resolved_environment.python == expected_python,
  'Python environment used the wrong interpreter'
)

local original_lsp_config = vim.lsp.config
local original_get_clients = vim.lsp.get_clients
local original_notify = vim.notify
local configured_settings
local notified_method
local notified_settings
local notification_message
local client = {
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = 'basic',
      },
    },
  },
}

function client:notify(method, params)
  notified_method = method
  notified_settings = params.settings
end

vim.lsp.config = function(name, config)
  assert(name == 'basedpyright', 'Python diagnostic toggle configured the wrong server')
  configured_settings = config.settings
end
rawset(vim.lsp, 'get_clients', function(opts)
  assert(opts.name == 'basedpyright', 'Python diagnostic toggle queried the wrong clients')
  return { client }
end)
rawset(vim, 'notify', function(message, _level)
  notification_message = message
end)

local lsp = require('config.lsp')
lsp.toggle_third_party_checks()

local enabled_overrides = configured_settings.basedpyright.analysis.diagnosticSeverityOverrides
assert(
  enabled_overrides.reportMissingModuleSource == 'warning',
  'Third-party checks were not enabled'
)
assert(
  client.settings.basedpyright.analysis.typeCheckingMode == 'basic',
  'Python diagnostic toggle discarded existing client settings'
)
assert(notified_method == 'workspace/didChangeConfiguration', 'LSP client was not notified')
assert(notified_settings == client.settings, 'LSP client received stale settings')
assert(notification_message:find('enabled', 1, true), 'Enable notification was not emitted')

lsp.toggle_third_party_checks()
local disabled_overrides = configured_settings.basedpyright.analysis.diagnosticSeverityOverrides
assert(
  disabled_overrides.reportMissingModuleSource == 'none',
  'Third-party checks were not disabled'
)
assert(notification_message:find('disabled', 1, true), 'Disable notification was not emitted')

vim.lsp.config = original_lsp_config
rawset(vim.lsp, 'get_clients', original_get_clients)
rawset(vim, 'notify', original_notify)
