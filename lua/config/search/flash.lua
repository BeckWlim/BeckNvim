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

return M
