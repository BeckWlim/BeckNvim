-- Configure native/plugin log destinations before their first write.
local M = {}

function M.directory()
  return vim.fs.joinpath(vim.fn.stdpath('state'), 'logs')
end

function M.path(name)
  return vim.fs.joinpath(M.directory(), name .. '.log')
end

-- Call before each plugin's setup; keep its own logger and rotation policy.
function M.configure(plugin)
  if plugin == 'mason' then
    require('mason-core.log').outfile = M.path('mason')
  elseif plugin == 'telescope' then
    -- Telescope exposes no path option, but uses Plenary's configurable logger.
    package.loaded['telescope.log'] = require('plenary.log').new({
      plugin = 'telescope', level = 'info', outfile = M.path('telescope'),
    })
  elseif plugin == 'overseer' then
    -- Overseer resolves this provider when opening/rotating its native log.
    require('overseer.log').get_logfile = function() return M.path('overseer') end
  end
end

function M.setup()
  -- These paths must exist before a logger is loaded during plugin bootstrap.
  vim.fn.mkdir(M.directory(), 'p', 448)
  vim.env.NVIM_LOG_FILE = M.path('nvim')
  vim.env.LUASNIP_OVERRIDE_LOGPATH = M.directory()
  -- Neovim currently exposes its filename setter as an internal API.
  if vim.lsp.log._set_filename then vim.lsp.log._set_filename(M.path('lsp')) end
end

return M
