local M = {}

function M.setup()
  require('config.startup.options')
  require('config.startup.autocmds').setup()
  require('config.startup.lazy')
  require('config.startup.keybindings').setup()
  require('config.network.ui').setup()
end

return M
