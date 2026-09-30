-- Small view snapshots only. Git data and live handles belong to their views.
local M = {}

local function store(root)
  return require('config.state').open('git-view', {
    scope = 'session', session_id = vim.fs.normalize(root),
  })
end

function M.read(root)
  return store(root):read_sync() or {}
end

function M.update(root, changes)
  local document = M.read(root)
  for key, value in pairs(changes) do document[key] = value end
  store(root):write(document)
end

function M.capture_window(window)
  if window and vim.api.nvim_win_is_valid(window) then
    return vim.api.nvim_win_call(window, vim.fn.winsaveview)
  end
end

function M.restore_window(window, saved, row)
  if not saved or not window or not vim.api.nvim_win_is_valid(window) then return end
  local restored = vim.deepcopy(saved)
  if row then
    restored.topline = math.max(1, restored.topline + row - restored.lnum)
    restored.lnum = row
  end
  vim.api.nvim_win_call(window, function() vim.fn.winrestview(restored) end)
end

return M
