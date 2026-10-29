local lifecycle = require('config.lsp.lifecycle')
local original_get_client = vim.lsp.get_client_by_id
local original_has = vim.fn.has
local original_defer = vim.defer_fn
local buffer = vim.api.nvim_create_buf(true, false)
local other_buffer = vim.api.nvim_create_buf(true, false)
local stop_calls = 0
local stopped = false
local supports_shutdown_timeout = true
local shutdown_modes = {}
local client = {
  attached_buffers = { [buffer] = true },
  id = 42,
  is_stopped = function() return stopped end,
  stop = function(_, force)
    if not supports_shutdown_timeout then
      shutdown_modes[#shutdown_modes + 1] = force
      return
    end
    assert(force == 5000, 'Unused servers must receive a bounded graceful shutdown')
    stop_calls = stop_calls + 1
  end,
}
local client_exists = true
vim.fn.has = function(feature)
  if feature == 'nvim-0.12' then return supports_shutdown_timeout and 1 or 0 end
  return original_has(feature)
end
vim.lsp.get_client_by_id = function(client_id)
  assert(client_id == 42, 'Cleanup queried an unrelated client')
  return client_exists and client or nil
end

local function detach()
  vim.api.nvim_exec_autocmds('LspDetach', {
    buffer = buffer,
    modeline = false,
    data = { client_id = 42 },
  })
end

local function drain_callbacks()
  local drained = false
  vim.schedule(function() drained = true end)
  assert(vim.wait(1000, function() return drained end), 'Scheduled cleanup did not run')
end

lifecycle.setup()
detach()
assert(stop_calls == 0, 'Cleanup ran before Neovim could remove the attachment')
client.attached_buffers[buffer] = nil
drain_callbacks()
assert(stop_calls == 1, 'Closing the last buffer did not stop its server')

-- A hidden buffer is still open and must retain its server.
client.attached_buffers[other_buffer] = true
detach()
drain_callbacks()
assert(stop_calls == 1, 'Cleanup stopped a server with another hidden buffer')
client.attached_buffers[other_buffer] = nil

-- Reattachment between notification and the deferred check cancels cleanup.
detach()
client.attached_buffers[buffer] = true
drain_callbacks()
assert(stop_calls == 1, 'Cleanup ignored an intervening attachment')
client.attached_buffers[buffer] = nil

detach()
detach()
drain_callbacks()
assert(stop_calls == 2, 'Concurrent detach events should request one shutdown')

stopped = true
detach()
drain_callbacks()
assert(stop_calls == 2, 'Cleanup repeated a shutdown already in progress')
stopped = false
client_exists = false
detach()
drain_callbacks()
assert(stop_calls == 2, 'Cleanup did not tolerate an exited client')
client_exists = true

detach()
lifecycle.setup()
drain_callbacks()
assert(stop_calls == 2, 'A callback from an earlier setup remained active')
detach()
drain_callbacks()
assert(stop_calls == 3, 'Repeated setup duplicated or disabled cleanup')

-- The 0.11 compatibility path must request graceful shutdown before escalation.
supports_shutdown_timeout = false
local deferred_shutdown
vim.defer_fn = function(callback, timeout_ms)
  assert(timeout_ms == 5000, 'Compatibility shutdown omitted its grace period')
  deferred_shutdown = callback
end
detach()
drain_callbacks()
assert(#shutdown_modes == 1 and shutdown_modes[1] == false,
  'Neovim 0.11 must begin with a graceful shutdown')
assert(deferred_shutdown)
deferred_shutdown()
assert(#shutdown_modes == 2 and shutdown_modes[2] == true,
  'A server remaining after the grace period was not terminated')
client_exists = false
deferred_shutdown()
assert(#shutdown_modes == 2, 'Shutdown timeout did not tolerate a server that already exited')
client_exists = true
client.attached_buffers[other_buffer] = true
deferred_shutdown()
assert(#shutdown_modes == 2, 'Compatibility timeout killed a reattached server')

vim.api.nvim_del_augroup_by_name('release_unused_language_servers')
vim.lsp.get_client_by_id = original_get_client
vim.fn.has = original_has
vim.defer_fn = original_defer
vim.api.nvim_buf_delete(buffer, { force = true })
vim.api.nvim_buf_delete(other_buffer, { force = true })
print('Language-server last-buffer shutdown and reattachment checks passed')
