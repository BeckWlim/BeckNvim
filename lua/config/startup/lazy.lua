local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- GitHub-backed plugin bootstrap and updates inherit the same proxy that
-- outbound application modules use. Discovery is static: ~/.bashrc is parsed
-- for assignments but is never sourced or executed.
require('config.network.proxy').enable()

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
