local M = {}
local third_party_checks_enabled = false

local function diagnostic_settings(enabled)
  local severities = enabled and {
    reportMissingImports = 'error',
    reportMissingModuleSource = 'warning',
    reportMissingTypeStubs = 'warning',
  } or {
    reportMissingImports = 'error',
    reportMissingModuleSource = 'none',
    reportMissingTypeStubs = 'none',
  }
  return {
    basedpyright = {
      analysis = {
        diagnosticSeverityOverrides = severities,
      },
    },
  }
end

function M.toggle_third_party_checks()
  third_party_checks_enabled = not third_party_checks_enabled
  local updated_settings = diagnostic_settings(third_party_checks_enabled)
  vim.lsp.config('basedpyright', { settings = updated_settings })

  for _, client in ipairs(vim.lsp.get_clients({ name = 'basedpyright' })) do
    local merged_settings = vim.tbl_deep_extend(
      'force',
      client.settings or {},
      updated_settings
    )
    client.settings = merged_settings
    client:notify('workspace/didChangeConfiguration', { settings = merged_settings })
  end

  vim.notify(
    ('basedpyright third-party dependency diagnostics: %s'):format(
      third_party_checks_enabled and 'enabled' or 'disabled'
    )
  )
end

return M
