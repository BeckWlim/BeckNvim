local hierarchy = require('config.type_hierarchy')
local python_hierarchy_index = require('config.python.hierarchy_index')

local fixture_root = vim.fs.normalize(
  vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'fixtures', 'type_hierarchy_project')
)
local fixture_filename = vim.fs.joinpath(fixture_root, 'models.py')
local fixture_uri = vim.uri_from_fname(fixture_filename)
local original_buffer = vim.api.nvim_get_current_buf()
local fixture_buffer = vim.fn.bufadd(fixture_filename)
vim.fn.bufload(fixture_buffer)
vim.api.nvim_set_current_buf(fixture_buffer)
vim.bo[fixture_buffer].filetype = 'cpp'

local function type_item(name, line_number)
  local zero_based_line = line_number - 1
  return {
    name = name,
    kind = vim.lsp.protocol.SymbolKind.Class,
    uri = fixture_uri,
    range = {
      start = { line = zero_based_line, character = 6 },
      ['end'] = { line = zero_based_line, character = 6 + #name },
    },
    selectionRange = {
      start = { line = zero_based_line, character = 6 },
      ['end'] = { line = zero_based_line, character = 6 + #name },
    },
  }
end

local repository_item = type_item('Repository', 4)
local sql_repository_item = type_item('SqlRepository', 9)
local cached_repository_item = type_item('CachedRepository', 13)
local memory_repository_item = type_item('MemoryRepository', 17)
local active_root_item = repository_item

local subtype_items = {
  Repository = { sql_repository_item, memory_repository_item },
  SqlRepository = { cached_repository_item },
  CachedRepository = {},
  MemoryRepository = {},
}
local supertype_items = {
  Repository = {},
  SqlRepository = { repository_item },
  CachedRepository = { sql_repository_item },
  MemoryRepository = { repository_item },
}

local function item_location(item)
  return { uri = item.uri, range = item.selectionRange }
end

local standard_hierarchy_supported = true

local fake_client = {
  id = 91,
  offset_encoding = 'utf-16',
  config = { root_dir = fixture_root },
}
function fake_client:request(method, params, handler, _bufnr)
  if method == 'textDocument/definition' then
    local definition_location
    if params.position.line == 12 and params.position.character < 20 then
      definition_location = item_location(cached_repository_item)
    elseif params.position.line == 12 then
      definition_location = item_location(sql_repository_item)
    elseif params.position.line == 8 then
      definition_location = item_location(repository_item)
    end
    handler(nil, definition_location)
    return true, 1
  end

  local related_items = method == 'typeHierarchy/subtypes'
      and subtype_items[params.item.name]
    or supertype_items[params.item.name]
  handler(nil, related_items)
  return true, 1
end

local function location(line_number, character)
  local zero_based_line = line_number - 1
  return {
    uri = fixture_uri,
    range = {
      start = { line = zero_based_line, character = character },
      ['end'] = { line = zero_based_line, character = character + 4 },
    },
  }
end

local implementation_locations = {
  location(6, 8),
  location(10, 8),
  location(14, 8),
  location(18, 14),
}
local active_implementation_locations = implementation_locations

local original_get_clients = vim.lsp.get_clients
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_buf_request_all = vim.lsp.buf_request_all
local original_actions = package.loaded['telescope.actions']
local original_pickers = package.loaded['telescope.pickers']
local original_finders = package.loaded['telescope.finders']
local original_telescope_config = package.loaded['telescope.config']
local latest_picker_entries = {}
local latest_picker_title = ''

rawset(vim.lsp, 'get_clients', function(opts)
  if opts
      and opts.method == 'textDocument/prepareTypeHierarchy'
      and not standard_hierarchy_supported then
    return {}
  end
  return { fake_client }
end)
rawset(vim.lsp, 'get_client_by_id', function(client_id)
  return client_id == fake_client.id and fake_client or nil
end)
rawset(vim.lsp, 'buf_request_all', function(_bufnr, method, params, callback)
  params(fake_client)
  if method == 'textDocument/prepareTypeHierarchy' then
    callback({ [fake_client.id] = { result = { active_root_item } } })
  else
    callback({ [fake_client.id] = { result = active_implementation_locations } })
  end
  return function() end
end)
package.loaded['telescope.actions'] = { close = function() end }
package.loaded['telescope.finders'] = {
  new_table = function(spec)
    return vim.tbl_map(spec.entry_maker, spec.results)
  end,
}
package.loaded['telescope.pickers'] = {
  new = function(_, spec)
    latest_picker_entries = spec.finder
    latest_picker_title = spec.prompt_title
    return {
      find = function() end,
      refresh = function(_, finder)
        latest_picker_entries = finder
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

vim.api.nvim_win_set_cursor(0, { 4, 7 })
hierarchy.open_subtypes()
assert(latest_picker_title:match('^Derived Classes'), 'Derived-class picker did not open')
assert(#latest_picker_entries == 3, 'Derived-class search did not recurse through subclasses')
local derived_depths = {}
for _, entry in ipairs(latest_picker_entries) do
  derived_depths[entry.value.item.name] = entry.value.depth
end
assert(derived_depths.SqlRepository == 1, 'Direct subclass has the wrong hierarchy depth')
assert(derived_depths.MemoryRepository == 1, 'Sibling subclass was omitted')
assert(derived_depths.CachedRepository == 2, 'Indirect subclass was not recursively resolved')

active_root_item = cached_repository_item
vim.api.nvim_win_set_cursor(0, { 13, 7 })
hierarchy.open_supertypes()
assert(latest_picker_title:match('^Base Classes'), 'Base-class picker did not open')
assert(#latest_picker_entries == 2, 'Base-class search did not recurse through ancestors')
local base_depths = {}
for _, entry in ipairs(latest_picker_entries) do
  base_depths[entry.value.item.name] = entry.value.depth
end
assert(base_depths.SqlRepository == 1, 'Direct base class has the wrong hierarchy depth')
assert(base_depths.Repository == 2, 'Indirect base class was not recursively resolved')

standard_hierarchy_supported = false
vim.bo[fixture_buffer].filetype = 'python'
python_hierarchy_index.reset()
local python_index_ready = false
local indexed_document
python_hierarchy_index.ensure(fixture_root, function(index_document, error_message)
  assert(error_message == '', error_message)
  indexed_document = index_document
  python_index_ready = true
end)
assert(vim.wait(3000, function()
  return python_index_ready
end), 'Python hierarchy index did not become ready')
local index_status = python_hierarchy_index.status(fixture_root)
assert(index_status.class_count == 6, 'Python hierarchy index omitted fixture classes')
local imported_base_filename = vim.fs.joinpath(fixture_root, 'base_model.py')
local imported_base_class = python_hierarchy_index.find_class(
  indexed_document,
  imported_base_filename,
  1
)
local imported_descendants = python_hierarchy_index.derived(
  indexed_document,
  imported_base_class
)
assert(
  #imported_descendants == 1
    and imported_descendants[1].class_record.name == 'ImportedChild',
  'Python hierarchy index did not resolve an aliased multiline base class'
)
local derived_model_filename = vim.fs.joinpath(fixture_root, 'derived_model.py')
local referenced_imported_base = python_hierarchy_index.find_symbol_class(
  indexed_document,
  derived_model_filename,
  5,
  5,
  'RenamedBase'
)
assert(
  referenced_imported_base and referenced_imported_base.name == 'ImportedBase',
  'Python hierarchy index did not resolve a base-class symbol under the cursor'
)
python_hierarchy_index.refresh(fixture_root)
assert(
  python_hierarchy_index.status(fixture_root).status == 'refreshing',
  'Python hierarchy refresh did not preserve the ready index'
)

vim.api.nvim_win_set_cursor(0, { 4, 7 })
local indexed_query_started_at = vim.uv.hrtime()
hierarchy.open_subtypes()
local indexed_query_elapsed_ms = (vim.uv.hrtime() - indexed_query_started_at) / 1e6
assert(latest_picker_title:match('^Derived Classes'), 'Python derived fallback did not open')
assert(#latest_picker_entries == 3, 'Python derived fallback omitted class implementations')
assert(indexed_query_elapsed_ms < 100, 'Warm Python hierarchy query exceeded 100 ms')

vim.api.nvim_win_set_cursor(0, { 13, 7 })
hierarchy.open_supertypes()
assert(latest_picker_title:match('^Base Classes'), 'Python base fallback did not open')
assert(#latest_picker_entries == 2, 'Python base fallback did not resolve ancestors')
local fallback_base_depths = {}
for _, entry in ipairs(latest_picker_entries) do
  fallback_base_depths[entry.value.item.name] = entry.value.depth
end
assert(fallback_base_depths.SqlRepository == 1, 'Python direct base fallback depth is wrong')
assert(fallback_base_depths.Repository == 2, 'Python indirect base fallback was omitted')

vim.api.nvim_win_set_cursor(0, { 6, 9 })
hierarchy.open_implementations()
assert(latest_picker_title:match('^Implementations'), 'Implementation picker did not open')
assert(#latest_picker_entries == 3, 'Abstract declaration was not excluded from implementations')
local implementation_names = {}
for _, entry in ipairs(latest_picker_entries) do
  implementation_names[entry.value.name] = true
end
assert(implementation_names['SqlRepository.save'], 'Synchronous implementation was omitted')
assert(implementation_names['CachedRepository.save'], 'Derived override was omitted')
assert(implementation_names['MemoryRepository.save'], 'Async implementation was omitted')

local derived_model_buffer = vim.fn.bufadd(derived_model_filename)
vim.fn.bufload(derived_model_buffer)
vim.api.nvim_set_current_buf(derived_model_buffer)
vim.bo[derived_model_buffer].filetype = 'python'
vim.api.nvim_win_set_cursor(0, { 5, 6 })
hierarchy.open_implementations()
assert(
  #latest_picker_entries == 1
    and latest_picker_entries[1].value.name == 'ImportedChild',
  'base-class implementation query fell back to the expensive LSP request'
)
vim.api.nvim_set_current_buf(fixture_buffer)
assert(vim.wait(3000, function()
  return python_hierarchy_index.status(fixture_root).status == 'ready'
end), 'Python hierarchy background refresh did not complete')

local cpp_fixture_filename = vim.fs.joinpath(fixture_root, 'models.cpp')
local cpp_fixture_uri = vim.uri_from_fname(cpp_fixture_filename)
local cpp_fixture_buffer = vim.fn.bufadd(cpp_fixture_filename)
vim.fn.bufload(cpp_fixture_buffer)
vim.api.nvim_set_current_buf(cpp_fixture_buffer)
vim.bo[cpp_fixture_buffer].filetype = 'cpp'
local function cpp_location(line_number, character)
  local zero_based_line = line_number - 1
  return {
    uri = cpp_fixture_uri,
    range = {
      start = { line = zero_based_line, character = character },
      ['end'] = { line = zero_based_line, character = character + 4 },
    },
  }
end
active_implementation_locations = {
  cpp_location(4, 15),
  cpp_location(9, 7),
  cpp_location(14, 7),
  cpp_location(19, 7),
}
vim.api.nvim_win_set_cursor(0, { 4, 16 })
hierarchy.open_implementations()
assert(#latest_picker_entries == 3, 'C++ pure virtual declaration was not excluded')
local cpp_implementation_names = {}
for _, entry in ipairs(latest_picker_entries) do
  cpp_implementation_names[entry.value.name] = true
end
assert(cpp_implementation_names['SqlRepository::save'], 'C++ implementation owner was omitted')
assert(cpp_implementation_names['CachedRepository::save'], 'C++ derived override was omitted')
assert(cpp_implementation_names['MemoryRepository::save'], 'C++ sibling override was omitted')

rawset(vim.lsp, 'get_clients', original_get_clients)
rawset(vim.lsp, 'get_client_by_id', original_get_client_by_id)
rawset(vim.lsp, 'buf_request_all', original_buf_request_all)
package.loaded['telescope.pickers'] = original_pickers
package.loaded['telescope.finders'] = original_finders
package.loaded['telescope.config'] = original_telescope_config
package.loaded['telescope.actions'] = original_actions
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(fixture_buffer, { force = true })
vim.api.nvim_buf_delete(derived_model_buffer, { force = true })
vim.api.nvim_buf_delete(cpp_fixture_buffer, { force = true })
