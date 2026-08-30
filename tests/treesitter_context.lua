local treesitter_context = require('config.syntax.treesitter_context')

local context_ranges = {
  { 0, 0, 1, 0 },
  { 1, 0, 2, 0 },
  { 2, 0, 3, 0 },
  { 3, 0, 4, 0 },
  { 4, 0, 5, 0 },
  { 5, 0, 6, 0 },
  { 6, 0, 7, 0 },
}
local context_lines = {
  'class Service:',
  '    def run(self):',
  '        if configured:',
  '            with connection:',
  '                if ready:',
  '                    for item in items:',
  '                        while pending:',
}

local function is_structural(context_range)
  return context_range[1] == 0 or context_range[1] == 1
end

local prioritized_ranges, prioritized_lines = treesitter_context.prioritize(
  context_ranges,
  context_lines,
  6,
  is_structural
)

assert(#prioritized_ranges == 6, 'context prioritization did not honor the larger line budget')
assert(prioritized_ranges[1][1] == 0, 'class context was displaced by a block context')
assert(prioritized_ranges[2][1] == 1, 'function context was displaced by a block context')
assert(prioritized_ranges[#prioritized_ranges][1] == 6, 'nearest context was discarded')
assert(prioritized_ranges[3][1] == 3, 'the wrong intermediate block context was omitted')
assert(prioritized_lines[1] == 'class Service:', 'class context text was not preserved')
assert(
  prioritized_lines[#prioritized_lines] == '                        while pending:',
  'nearest context text was not preserved'
)

local mandatory_ranges, mandatory_lines = treesitter_context.prioritize(
  context_ranges,
  context_lines,
  2,
  is_structural
)
assert(#mandatory_ranges == 3, 'mandatory contexts were constrained by the soft line budget')
assert(mandatory_ranges[1][1] == 0, 'class context was omitted under a tight budget')
assert(mandatory_ranges[2][1] == 1, 'function context was omitted under a tight budget')
assert(mandatory_ranges[3][1] == 6, 'nearest context was omitted under a tight budget')
assert(#mandatory_lines == 3, 'mandatory context lines were assembled incorrectly')

local multiline_ranges = {
  { 0, 0, 2, 0 },
  { 2, 0, 3, 0 },
  { 3, 0, 4, 0 },
}
local multiline_lines = {
  'def collect(',
  '    values,',
  '    if ready:',
  '        with source:',
}
local selected_multiline_ranges, selected_multiline_lines = treesitter_context.prioritize(
  multiline_ranges,
  multiline_lines,
  2,
  function(context_range)
    return context_range[1] == 0
  end
)
assert(#selected_multiline_ranges == 2, 'multiline structural and nearest contexts were not kept')
assert(#selected_multiline_lines == 3, 'multiline context text lost its range alignment')
assert(selected_multiline_lines[2] == '    values,', 'multiline function header was truncated')
assert(selected_multiline_lines[3] == '        with source:', 'nearest multiline context was lost')

local navigation_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(navigation_buffer)
vim.bo[navigation_buffer].filetype = 'python'
vim.api.nvim_buf_set_lines(navigation_buffer, 0, -1, false, {
  'class Service:',
  '    def run(self):',
  '        if ready:',
  '            with source:',
  '                consume(source)',
})

local original_query_get = vim.treesitter.query.get
local navigation_query = vim.treesitter.query.parse('python', [[
  (class_definition) @context
  (function_definition) @context
  (if_statement) @context
  (with_statement) @context
]])
vim.treesitter.query.get = function(language, query_name)
  if language == 'python' and query_name == 'context' then
    return navigation_query
  end
  return original_query_get(language, query_name)
end

vim.api.nvim_win_set_cursor(0, { 5, 16 })
local structural_labels = treesitter_context.structural_context_labels(
  navigation_buffer,
  4,
  16
)
assert(vim.deep_equal(structural_labels, { 'Service', 'run' }), 'structural labels included block scopes')
treesitter_context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(0)[1] == 4, 'nearest context did not jump to with')
treesitter_context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(0)[1] == 3, 'repeated context jump did not move to if')
treesitter_context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'repeated context jump did not move to function')
treesitter_context.go_to_nearest_context()
assert(vim.api.nvim_win_get_cursor(0)[1] == 1, 'repeated context jump did not move to class')

vim.treesitter.query.get = original_query_get
vim.api.nvim_buf_delete(navigation_buffer, { force = true })

local cpp_buffer = vim.api.nvim_create_buf(false, true)
vim.bo[cpp_buffer].filetype = 'cpp'
vim.api.nvim_buf_set_lines(cpp_buffer, 0, -1, false, {
  'namespace project::detail {',
  'template <typename T>',
  'Result<T> Service<T>::run(const Input& input) const noexcept {',
  '  return helper(input);',
  '}',
  '}',
})

local cpp_labels = treesitter_context.structural_context_labels(cpp_buffer, 3, 9)
assert(
  vim.deep_equal(cpp_labels, { 'project::detail', 'Service<T>::run' }),
  'C++ structural labels did not reduce a qualified definition to its readable declarator'
)
vim.api.nvim_buf_delete(cpp_buffer, { force = true })
