-- Integration tests use the same plugin selection as startup; an override lets
-- a renderer migration be verified before installing its reviewed changes.
local renderer_path = vim.env.NVIM_TEST_RENDER_MARKDOWN
if not renderer_path then
  local dev = require('config.user').get().dev or {}
  local selected = false
  for _, pattern in ipairs(dev.enabled == true and dev.patterns or {}) do
    if ('BeckWlim/render-markdown.nvim'):find(pattern, 1, true) then selected = true end
  end
  local parent = selected and vim.fn.expand(dev.path or '~/.config')
    or vim.fn.stdpath('data') .. '/lazy'
  renderer_path = parent .. '/render-markdown.nvim'
end
vim.opt.runtimepath:prepend(renderer_path)
vim.opt.runtimepath:append(renderer_path .. '/after')
