-- Serialized documents shared only within this Neovim process.
local M = { persistent = false }
local documents = {}

function M.read_sync(store)
  return documents[store.memory_key]
end

function M.write_sync(store, source)
  documents[store.memory_key] = source
  return true
end

function M.read(store, callback)
  local cancelled = false
  vim.schedule(function()
    if not cancelled then callback(M.read_sync(store)) end
  end)
  return function() cancelled = true end
end

function M.write(store, source)
  return M.write_sync(store, source)
end

function M.when_idle(_, callback)
  vim.schedule(function() callback(true) end)
end

function M.setup()
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('memory_state_storage', { clear = true }),
    callback = function() documents = {} end,
    desc = 'Release process-local preference documents',
  })
end

return M
