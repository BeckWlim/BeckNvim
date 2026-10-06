local M = {}

local function can_navigate()
  return vim.bo.buftype == '' or type(vim.b.markdown_preview_source) == 'number'
end

function M.jump()
  if not can_navigate() then return end
  require('flash').jump()
end

function M.treesitter()
  if not can_navigate() then return end

  -- Rendered Markdown hides syntax, so select nodes in its mapped source.
  if type(vim.b.markdown_preview_source) == 'number' then
    require('render-markdown').dispatch({
      target = 'source',
      run = function() require('flash').treesitter() end,
    })
  else
    require('flash').treesitter()
  end
end

---@param options table
function M.setup(options)
  require('flash').setup(options)
  local modes = { 'n', 'x', 'o' }
  vim.keymap.set(modes, '<Space>s', M.jump, {
    silent = true,
    desc = 'Flash jump to visible text',
  })
  vim.keymap.set(modes, '<Space>fn', M.treesitter, {
    silent = true,
    desc = 'Flash select syntax region',
  })
end

return M
