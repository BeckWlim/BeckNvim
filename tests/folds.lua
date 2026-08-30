local folds = require('config.syntax.folds')

local test_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(test_buffer)
vim.bo[test_buffer].filetype = 'python'
vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
  'if ready:',
  '    run()',
  'elif waiting:',
  '    pause()',
  'else:',
  '    stop()',
  'result = first if ready else second',
})

local original_foldexpr = vim.treesitter.foldexpr
local treesitter_levels = {
  '>1',
  '1',
  '1',
  '1',
  '1',
  '1',
  '0',
}
vim.treesitter.foldexpr = function(line_number)
  return treesitter_levels[line_number] or '0'
end

assert(folds.expression(1) == '>1', 'if fold start should remain unchanged')
assert(folds.expression(2) == '1', 'if body fold level should remain unchanged')
assert(folds.expression(3) == '>1', 'elif should start a sibling fold')
assert(folds.expression(5) == '>1', 'else should start a sibling fold')
assert(folds.expression(7) == '0', 'conditional expressions should not become folds')

vim.bo[test_buffer].filetype = 'lua'
assert(folds.expression(3) == '1', 'non-Python fold expressions should remain unchanged')

vim.treesitter.foldexpr = original_foldexpr
vim.api.nvim_buf_delete(test_buffer, { force = true })
