local M = {}

function M.setup()
  require('config.options')
  require('config.autocmds').setup()
  require('config.lazy')
  require('config.keybindings').setup()
end

return M
