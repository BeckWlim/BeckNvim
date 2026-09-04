local M = {}
local project = require('config.project')
local third_party_checks_enabled = false

local function third_party_diagnostic_settings(enabled)
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

local function basedpyright_root_markers()
  local markers = vim.deepcopy(project.python_markers)
  markers[#markers + 1] = '.git'
  return markers
end

local function filtered_diagnostics_handler(error, result, context, handler_config)
  if result and result.diagnostics then
    local filtered_result = vim.tbl_extend('force', {}, result, {
      diagnostics = vim.tbl_filter(function(diagnostic)
        return diagnostic.code ~= 'reportUnannotatedClassAttribute'
      end, result.diagnostics),
    })
    return vim.lsp.handlers['textDocument/publishDiagnostics'](
      error,
      filtered_result,
      context,
      handler_config
    )
  end

  return vim.lsp.handlers['textDocument/publishDiagnostics'](
    error,
    result,
    context,
    handler_config
  )
end

local function configure_basedpyright()
  vim.lsp.config('basedpyright', {
    handlers = {
      ['textDocument/publishDiagnostics'] = filtered_diagnostics_handler,
    },
    root_markers = basedpyright_root_markers(),
    before_init = function(_, client_config)
      local root_dir = client_config.root_dir
      if type(root_dir) ~= 'string' then
        return
      end

      local python_environment = require('config.python.environment').resolve(root_dir)
      if python_environment then
        client_config.settings = vim.tbl_deep_extend('force', client_config.settings or {}, {
          python = { pythonPath = python_environment.python },
        })
      end
    end,
    settings = vim.tbl_deep_extend('force', {
      basedpyright = {
        analysis = {
          typeCheckingMode = 'basic',
          diagnosticMode = 'openFilesOnly',
          indexing = true,
          useLibraryCodeForTypes = true,
          diagnosticSeverityOverrides = {
            reportUnannotatedClassAttribute = 'none',
          },
        },
      },
    }, third_party_diagnostic_settings(false)),
  })
end

local function configure_clangd()
  local clangd_command = {}
  if vim.fn.executable('ionice') == 1 then
    vim.list_extend(clangd_command, { 'ionice', '--class', 'idle', '--ignore' })
  end
  if vim.fn.executable('nice') == 1 then
    vim.list_extend(clangd_command, { 'nice', '-n', '10' })
  end
  vim.list_extend(clangd_command, {
    'clangd',
    '--background-index',
    '--background-index-priority=background',
    '-j=1',
    '--pch-storage=memory',
  })
  vim.lsp.config('clangd', {
    cmd = clangd_command,
    filetypes = { 'c', 'cpp' },
    root_markers = {
      function(name, path)
        return name == 'build'
          and vim.uv.fs_stat(vim.fs.joinpath(path, name, 'compile_commands.json')) ~= nil
      end,
      '.clangd',
      'compile_commands.json',
      '.git',
    },
  })
end

function M.setup()
  require('mason').setup({
    ui = {
      icons = {
        package_installed = '✓',
        package_pending = '➜',
        package_uninstalled = '✗',
      },
    },
  })
  vim.lsp.config('*', {
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
  })
  configure_basedpyright()
  configure_clangd()
  require('mason-lspconfig').setup({
    ensure_installed = { 'bashls', 'basedpyright', 'clangd', 'lua_ls', 'marksman', 'vimls' },
    automatic_enable = true,
  })
end

function M.toggle_third_party_checks()
  third_party_checks_enabled = not third_party_checks_enabled
  local updated_settings = third_party_diagnostic_settings(third_party_checks_enabled)
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
