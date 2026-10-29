local M = {}
local setup_generation = 0
local shutdown_timeout_ms = 5000

local function stop_unused_client(client)
  if vim.fn.has('nvim-0.12') == 1 then
    -- Neovim owns the shutdown timer and cancels it when the process exits.
    client:stop(shutdown_timeout_ms)
    return
  end

  -- Neovim 0.11 accepts only a boolean here. Do not pass a numeric timeout:
  -- it would be treated as an immediate force-stop.
  client:stop(false)
  local client_id = client.id
  vim.defer_fn(function()
    local remaining_client = vim.lsp.get_client_by_id(client_id)
    if remaining_client and next(remaining_client.attached_buffers) == nil then
      remaining_client:stop(true)
    end
  end, shutdown_timeout_ms)
end

function M.setup()
  setup_generation = setup_generation + 1
  local current_generation = setup_generation
  local pending_clients = {}
  local group = vim.api.nvim_create_augroup('release_unused_language_servers', { clear = true })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      local client_id = event.data and event.data.client_id
      if not client_id or pending_clients[client_id] then
        return
      end
      pending_clients[client_id] = true
      -- LspDetach fires before Neovim removes the buffer from attached_buffers.
      -- Recheck after detachment, including any intervening buffer attachment.
      vim.schedule(function()
        pending_clients[client_id] = nil
        if current_generation ~= setup_generation then
          return
        end
        local client = vim.lsp.get_client_by_id(client_id)
        if client and not client:is_stopped() and next(client.attached_buffers) == nil then
          -- Allow native caches to flush, but do not retain a hung server forever.
          stop_unused_client(client)
        end
      end)
    end,
    desc = 'Release language servers after their last buffer detaches',
  })
end

return M
