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

-- Personal development checkouts use lazy.nvim's native directory resolution.
local user_config = require('config.user').get()
local dev_config = type(user_config.dev) == 'table' and user_config.dev or {}
local dev_patterns = {}
if dev_config.enabled == true and type(dev_config.patterns) == 'table' then
  for _, pattern in ipairs(dev_config.patterns) do
    if type(pattern) == 'string' and pattern ~= '' then
      dev_patterns[#dev_patterns + 1] = pattern
    end
  end
end
local dev_path = type(dev_config.path) == 'string' and dev_config.path ~= ''
  and dev_config.path or '~/.config'

require("lazy").setup("plugins", {
  dev = {
    path = vim.fn.expand(dev_path),
    patterns = dev_patterns,
    fallback = false,
  },
})
