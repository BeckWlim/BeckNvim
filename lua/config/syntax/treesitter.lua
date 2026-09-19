local M = {}
local rainbow_attached_buffers = {}
local pending_starts = {}

local function start_highlighting(buffer_number)
  if not vim.api.nvim_buf_is_valid(buffer_number)
      or not vim.api.nvim_buf_is_loaded(buffer_number)
      or vim.treesitter.highlighter.active[buffer_number] then
    return
  end
  local buffer_name = vim.api.nvim_buf_get_name(buffer_number)
  if vim.startswith(buffer_name, 'diffview://')
      and #vim.fn.win_findbuf(buffer_number) == 0 then
    return
  end
  pcall(vim.treesitter.start, buffer_number)
end

local function attach_highlighting(buffer_number, include_rainbow)
  if not vim.api.nvim_buf_is_loaded(buffer_number) then return end
  if vim.startswith(vim.api.nvim_buf_get_name(buffer_number), 'diffview://')
      and #vim.fn.win_findbuf(buffer_number) == 0 then return end
  start_highlighting(buffer_number)
  if not include_rainbow or not vim.g.loaded_rainbow_delimiters
      or rainbow_attached_buffers[buffer_number]
      or not require('config.syntax.visuals').rainbow_config().condition(buffer_number) then
    return
  end
  local rainbow_loaded, rainbow = pcall(require, 'rainbow-delimiters.lib')
  if rainbow_loaded and type(rainbow.attach) == 'function' then
    -- FileType may already have attached it; reattachment invalidates and parses
    -- the entire tree synchronously in the plugin.
    if rainbow.buffers and rainbow.buffers[buffer_number] then
      rainbow_attached_buffers[buffer_number] = true
      return
    end
    local attach_succeeded = pcall(rainbow.attach, buffer_number)
    if attach_succeeded then
      rainbow_attached_buffers[buffer_number] = true
    end
  end
end

local function schedule_highlighting(buffer_number, include_rainbow)
  local pending = pending_starts[buffer_number]
  if pending then
    pending.include_rainbow = pending.include_rainbow or include_rainbow
    return
  end
  local request = { include_rainbow = include_rainbow }
  pending_starts[buffer_number] = request
  vim.defer_fn(function()
    if pending_starts[buffer_number] ~= request then return end
    pending_starts[buffer_number] = nil
    attach_highlighting(buffer_number, request.include_rainbow)
  end, 10)
end

function M.ensure_highlighting(buffer_number)
  schedule_highlighting(buffer_number, true)
end

function M.setup()
  local treesitter = require('nvim-treesitter')
  treesitter.setup()

  -- The main branch no longer starts highlighting itself; Neovim owns it.
  local highlight_group = vim.api.nvim_create_augroup('config-treesitter-highlight', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = highlight_group,
    callback = function(event)
      schedule_highlighting(event.buf, false)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
    group = highlight_group,
    callback = function(event)
      rainbow_attached_buffers[event.buf] = nil
      pending_starts[event.buf] = nil
    end,
  })
end

return M
