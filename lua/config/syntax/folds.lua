local M = {}

local function starts_python_alternative(source_line)
  return source_line:match('^%s*elif%f[%W]') ~= nil
    or source_line:match('^%s*else%f[%W]') ~= nil
end

function M.expression(line_number)
  local normalized_line_number = line_number or vim.v.lnum
  local treesitter_expression = vim.treesitter.foldexpr(normalized_line_number)

  if vim.bo.filetype ~= 'python' then
    return treesitter_expression
  end

  local source_lines = vim.api.nvim_buf_get_lines(
    0,
    normalized_line_number - 1,
    normalized_line_number,
    false
  )
  local source_line = source_lines[1] or ''
  if not starts_python_alternative(source_line) then
    return treesitter_expression
  end

  local branch_level = tonumber(treesitter_expression)
  if not branch_level or branch_level <= 0 then
    return treesitter_expression
  end

  -- Treesitter captures the complete if_statement, so elif/else normally stay
  -- inside the preceding fold. Start a sibling fold at each alternative instead.
  return '>' .. branch_level
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local line_number = vim.fn.line('.')

  if vim.fn.foldlevel(line_number) == 0 then
    vim.notify('No code fold under cursor', vim.log.levels.INFO)
    return
  end

  local was_closed = vim.fn.foldclosed(line_number) ~= -1
  local count_prefix = vim.v.count > 0 and tostring(vim.v.count) or ''
  vim.cmd.normal({ args = { count_prefix .. 'za' }, bang = true })

  if was_closed then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) and vim.treesitter.highlighter.active[bufnr] then
        vim.api.nvim__redraw({ buf = bufnr, valid = false, flush = true })
      end
    end)
  end
end

return M
