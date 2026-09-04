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
local enclosing_structure = treesitter_context.enclosing_structure(navigation_buffer, 4, 16)
assert(enclosing_structure, 'enclosing function structure was not found')
assert(enclosing_structure.label == 'Service › run', 'enclosing structure lost its hierarchy label')
assert(enclosing_structure.first_line == 2, 'enclosing structure started on the wrong line')
assert(enclosing_structure.last_line == 5, 'enclosing structure ended on the wrong line')
assert(
  enclosing_structure.node_type == 'function_definition',
  'enclosing structure selected a block instead of the nearest symbol'
)
local async_structure
local async_structure_error
treesitter_context.enclosing_structure_async(
  navigation_buffer,
  4,
  16,
  function(resolved_structure, resolution_error)
    async_structure = resolved_structure
    async_structure_error = resolution_error
  end
)
assert(vim.wait(500, function()
  return async_structure ~= nil or async_structure_error ~= nil
end, 5), 'Cooperative enclosing-structure resolution did not complete')
assert(
  async_structure_error == nil
    and async_structure
    and async_structure.label == 'Service › run'
    and async_structure.first_line == 2,
  'Cooperative enclosing-structure resolution changed the selected symbol'
)
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

local original_context_plugin = package.loaded['treesitter-context']
local original_context_provider = package.loaded['treesitter-context.context']
local configured_context_options
package.loaded['treesitter-context'] = {
  setup = function(options)
    configured_context_options = options
  end,
}
package.loaded['treesitter-context.context'] = {
  get = function()
    return nil, nil
  end,
}
treesitter_context.setup()
assert(
  configured_context_options and configured_context_options.on_attach == nil,
  'Pinned code context still excludes Diffview buffers instead of reusing the editor renderer'
)
package.loaded['treesitter-context'] = original_context_plugin
package.loaded['treesitter-context.context'] = original_context_provider

-- Declaration matching reuses the buffer parser when available and otherwise
-- falls back to a light word-boundary text scan.
local declaration_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(declaration_buffer, 0, -1, false, {
  'local helper = 1',
  '',
  'local function changed_scope()',
  '  return helper',
  'end',
  '',
  'local function changed_scope_duplicate()',
  '  return helper',
  'end',
  '',
  'local function changed_scope()',
  '  return helper + 1',
  'end',
})
vim.bo[declaration_buffer].filetype = 'lua'
assert(
  treesitter_context.match_declaration_line(declaration_buffer, {
    first_line = 7,
    label = 'changed_scope',
    node_type = 'function_declaration',
  }) == 3,
  'Parser declaration match did not prefer the nearest exact declaration'
)
assert(
  treesitter_context.match_declaration_line(declaration_buffer, {
    first_line = 12,
    label = 'changed_scope',
    node_type = 'function_declaration',
  }) == 11,
  'Parser declaration match did not follow the hint toward the later declaration'
)
assert(
  treesitter_context.match_declaration_line(declaration_buffer, {
    first_line = 1,
    label = 'changed_scope_duplicate',
    node_type = 'function_declaration',
  }) == 7,
  'Parser declaration match confused a name prefix with the full declaration'
)

local plain_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(plain_buffer, 0, -1, false, {
  'int changed_scope_marker(int x) {',
  '  return x;',
  '}',
  'int changed_scope(int x);',
  'int changed_scope(int x) {',
  '  return x + 1;',
  '}',
})
assert(
  treesitter_context.match_declaration_line(plain_buffer, {
    first_line = 6,
    label = 'changed_scope',
  }) == 5,
  'Text declaration match did not honor word boundaries and the hint distance'
)
assert(
  treesitter_context.match_declaration_line(plain_buffer, {
    first_line = 1,
    label = 'absent_symbol',
  }) == nil,
  'Text declaration match invented a location for an absent symbol'
)
assert(
  treesitter_context.match_declaration_line(plain_buffer, nil) == nil,
  'Declaration matching accepted a missing structure'
)
vim.api.nvim_buf_delete(declaration_buffer, { force = true })
vim.api.nvim_buf_delete(plain_buffer, { force = true })
