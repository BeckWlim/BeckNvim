local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Restore the last explicit :Proxy choice before any plugin network request.
-- A fresh installation and an invalid or missing state both remain direct.
local proxy_state_error = select(3, require('config.network.proxy').initialize())
if proxy_state_error then
  vim.schedule(function()
    vim.notify('Proxy state ignored: ' .. proxy_state_error, vim.log.levels.WARN)
  end)
end

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")
