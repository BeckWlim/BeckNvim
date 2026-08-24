local M = {}
local project = require('config.project')

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

      local python_environment = require('config.python_environment').resolve(root_dir)
      if python_environment then
        client_config.settings = vim.tbl_deep_extend('force', client_config.settings or {}, {
          python = { pythonPath = python_environment.python },
        })
      end
    end,
    settings = {
      basedpyright = {
        analysis = {
          typeCheckingMode = 'basic',
          diagnosticMode = 'openFilesOnly',
          indexing = true,
          useLibraryCodeForTypes = true,
          diagnosticSeverityOverrides = {
            reportMissingImports = 'error',
            reportMissingModuleSource = 'none',
            reportMissingTypeStubs = 'none',
            reportUnannotatedClassAttribute = 'none',
          },
        },
      },
    },
  })
end

local function configure_clangd()
  vim.lsp.config('clangd', {
    cmd = {
      'clangd',
      '--background-index',
      '--background-index-priority=background',
      '-j=2',
      '--pch-storage=disk',
    },
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

return M
