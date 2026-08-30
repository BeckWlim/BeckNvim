local symbols = require('config.search.workspace_symbols')

local definition_cases = {
  { 'example.py', 'class IndexedClass:', 'Class', 'IndexedClass' },
  { 'example.py', 'async def fetch_record():', 'Function', 'fetch_record' },
  { 'example.py', 'type Record[T] = list[T]', 'Type', 'Record' },
  { 'example.py', 'ModelT = TypeVar("ModelT")', 'TypeVar', 'ModelT' },
  { 'example.py', 'RecordId: TypeAlias = int', 'Type', 'RecordId' },
  { 'example.py', 'record_count: int = 0', 'Variable', 'record_count' },
  { 'example.lua', 'local function open_picker()', 'Function', 'open_picker' },
  { 'example.sh', 'load_project() {', 'Function', 'load_project' },
  { 'example.vim', 'def BuildIndex()', 'Function', 'BuildIndex' },
  { 'example.cpp', 'struct ProjectSymbol {', 'Type', 'ProjectSymbol' },
  { 'example.cpp', '#define SYMBOL_LIMIT 100', 'Macro', 'SYMBOL_LIMIT' },
  { 'example.cpp', 'static const int PROJECT_LIMIT = 10;', 'Variable', 'PROJECT_LIMIT' },
  {
    'example.cpp',
    'auto MasterService::PutStart(int value) -> bool {',
    'Function',
    'MasterService::PutStart',
  },
  {
    'example.cpp',
    'WrappedMasterService::PutStart(int value) {',
    'Function',
    'WrappedMasterService::PutStart',
  },
  { 'example.md', '## Project symbols', 'Section', 'Project symbols' },
}

for _, definition_case in ipairs(definition_cases) do
  local parsed_definition = symbols.definition(definition_case[1], definition_case[2])
  assert(parsed_definition, 'Failed to parse definition: ' .. definition_case[2])
  assert(parsed_definition.kind == definition_case[3], 'Parsed the wrong definition kind')
  assert(parsed_definition.name == definition_case[4], 'Parsed the wrong definition name')
end

local fixture_root = vim.fs.normalize(vim.fn.getcwd() .. '/tests/fixtures/symbol_project')
for _, expected_name in ipairs({
  'IndexedClass',
  'indexed_symbol',
  'ModelT',
  'RecordId',
  'open_picker',
  'load_project',
  'BuildIndex',
  'ProjectSymbol',
  'SYMBOL_LIMIT',
  'PROJECT_LIMIT',
  'MasterService::PutStart',
  'WrappedMasterService::PutStart',
  'Project symbols',
}) do
  local commands = symbols.commands(expected_name, fixture_root)
  assert(commands, 'Project definition search did not build query commands')
  local command_outputs = {}
  for _, command in ipairs(commands) do
    local command_result = vim.system(command, { text = true }):wait()
    assert(
      command_result.code == 0 or command_result.code == 1,
      'Project definition search failed: ' .. command_result.stderr
    )
    table.insert(command_outputs, command_result.stdout)
  end
  local combined_output = table.concat(command_outputs, '\n')
  assert(
    combined_output:find(expected_name, 1, true),
    'Project definition search omitted ' .. expected_name
  )
end
assert(symbols.commands('', fixture_root) == nil, 'Empty definition query triggered a full scan')
assert(symbols.commands('x', fixture_root) == nil, 'One-character query triggered a broad scan')

local original_notify = vim.notify
local loading_message
rawset(vim, 'notify', function(message, _level)
  loading_message = message
end)
symbols.open()
rawset(vim, 'notify', original_notify)
assert(loading_message == 'Project definition search is loading; retry shortly')

symbols.setup()
assert(vim.wait(1000, symbols.is_ready), 'Project definition search did not become ready')

local original_get_clients = vim.lsp.get_clients
local original_pickers = package.loaded['telescope.pickers']
local original_config = package.loaded['telescope.config']
local original_entry_display = package.loaded['telescope.pickers.entry_display']
local original_make_entry = package.loaded['telescope.make_entry']
local original_plenary_job = package.loaded['plenary.job']
local picker_finder
local picker_spec
local picker_opened = false
local fake_jobs = {}
local FakeJob = {}

function FakeJob:new(opts)
  local fake_job = {
    is_shutdown = false,
  }
  function fake_job:start() end
  function fake_job:shutdown()
    self.is_shutdown = true
    opts.on_exit()
  end
  table.insert(fake_jobs, fake_job)
  return fake_job
end

rawset(vim.lsp, 'get_clients', function()
  return {}
end)
package.loaded['telescope.pickers'] = {
  new = function(_, spec)
    picker_finder = spec.finder
    picker_spec = spec
    return {
      find = function()
        picker_opened = true
      end,
    }
  end,
}
package.loaded['telescope.config'] = {
  values = {
    grep_previewer = function()
      return {}
    end,
    generic_sorter = function()
      return {}
    end,
  },
}
package.loaded['telescope.pickers.entry_display'] = {
  create = function()
    return function(items)
      return items
    end
  end,
}
package.loaded['plenary.job'] = FakeJob
package.loaded['telescope.make_entry'] = {
  gen_from_vimgrep = function()
    return function()
      return {}
    end
  end,
}

symbols.open()

vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local indexed_target = 1' })
vim.api.nvim_win_set_cursor(0, { 1, 8 })
symbols.open_for_cursor()
assert(
  picker_spec.default_text == 'indexed_target',
  'Cursor-word definition search did not seed the cursor word'
)
vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

rawset(vim.lsp, 'get_clients', original_get_clients)
package.loaded['telescope.pickers'] = original_pickers
package.loaded['telescope.config'] = original_config
package.loaded['telescope.pickers.entry_display'] = original_entry_display
package.loaded['telescope.make_entry'] = original_make_entry
package.loaded['plenary.job'] = original_plenary_job

assert(picker_opened, 'Project definition picker did not open directly')
assert(type(picker_finder) == 'table', 'Project definitions did not use a live finder')
local empty_query_completed = false
picker_finder('', function() end, function()
  empty_query_completed = true
end)
assert(empty_query_completed, 'Opening the picker triggered a full project scan')

local first_query_completions = 0
local second_query_completions = 0
picker_finder('Indexed', function() end, function()
  first_query_completions = first_query_completions + 1
end)
picker_finder('Project', function() end, function()
  second_query_completions = second_query_completions + 1
end)
assert(first_query_completions == 0, 'Superseded definition query finalized a newer picker state')
for job_index = 1, 6 do
  assert(fake_jobs[job_index].is_shutdown, 'Superseded ripgrep job was not stopped')
end
picker_finder.close()
assert(second_query_completions == 0, 'Closed definition query finalized the picker')
