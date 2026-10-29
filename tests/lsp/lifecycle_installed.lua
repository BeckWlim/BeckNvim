-- Run with -u init.lua: exercise native activation, clangd, and its disk index.
local fixture_root = vim.fn.tempname()
vim.fn.mkdir(fixture_root, 'p')
local first_path = fixture_root .. '/first.cpp'
local second_path = fixture_root .. '/second.cpp'
local indexed_path = fixture_root .. '/indexed.cpp'
vim.fn.writefile({ 'int first() { return 1; }' }, first_path)
vim.fn.writefile({ 'int second() { return 2; }' }, second_path)
vim.fn.writefile({ 'int CacheOnlySymbol() { return 3; }' }, indexed_path)
local compile_commands = {}
for _, path in ipairs({ first_path, second_path, indexed_path }) do
  compile_commands[#compile_commands + 1] = {
    directory = fixture_root,
    file = path,
    arguments = { 'clang++', '-c', path },
  }
end
vim.fn.writefile({ vim.json.encode(compile_commands) }, fixture_root .. '/compile_commands.json')

local function open_file(path)
  vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.wait(15000, function()
    local clients = vim.lsp.get_clients({ bufnr = buffer, name = 'clangd' })
    return #clients == 1 and clients[1].initialized
  end, 20), 'Native activation did not attach clangd')
  return buffer, assert(vim.lsp.get_clients({ bufnr = buffer, name = 'clangd' })[1])
end

local function has_cached_symbol(client)
  local response = client:request_sync('workspace/symbol', { query = 'CacheOnlySymbol' }, 5000)
  if not response or response.err then return false end
  for _, symbol in ipairs(response.result or {}) do
    if symbol.name == 'CacheOnlySymbol' then return true end
  end
  return false
end

local first_buffer, first_client = open_file(first_path)
assert(vim.list_contains(first_client.config.cmd, '--pch-storage=disk'),
  'Installed clangd did not receive disk precompiled-header storage')
local second_buffer, second_client = open_file(second_path)
assert(first_client.id == second_client.id, 'Same-project buffers started duplicate servers')
assert(vim.wait(15000, function() return has_cached_symbol(first_client) end, 100),
  'Background index did not find an unopened translation unit')
local index_directory = fixture_root .. '/.cache/clangd/index'
assert(vim.wait(5000, function()
  return #vim.fn.glob(index_directory .. '/*.idx', false, true) >= 3
end, 50), 'Clangd did not persist background index shards')

vim.api.nvim_buf_delete(second_buffer, { force = true })
vim.wait(100, function() return false end)
assert(not first_client:is_stopped() and first_client.attached_buffers[first_buffer],
  'Closing one file stopped the shared server')
vim.api.nvim_buf_delete(first_buffer, { force = true })
assert(vim.wait(10000, function()
  return vim.lsp.get_client_by_id(first_client.id) == nil
end, 20), 'Closing the last buffer did not terminate the server process')

local cached_modification_times = {}
for _, path in ipairs(vim.fn.glob(index_directory .. '/*.idx', false, true)) do
  local file_stat = assert(vim.uv.fs_stat(path))
  cached_modification_times[path] = file_stat.mtime
end
local reopened_buffer, reopened_client = open_file(first_path)
assert(reopened_client.id ~= first_client.id, 'Reopening did not create a fresh server')
assert(vim.wait(15000, function() return has_cached_symbol(reopened_client) end, 100),
  'Reopened server could not query the cached index')
for path, modified_at in pairs(cached_modification_times) do
  local file_stat = assert(vim.uv.fs_stat(path))
  assert(file_stat.mtime.sec == modified_at.sec and file_stat.mtime.nsec == modified_at.nsec,
    'Reopening rewrote an unchanged background index shard')
end
vim.api.nvim_buf_delete(reopened_buffer, { force = true })
assert(vim.wait(10000, function()
  return vim.lsp.get_client_by_id(reopened_client.id) == nil
end, 20), 'Reopened server did not shut down after its last buffer closed')
vim.fn.delete(fixture_root, 'rf')
print('Installed clangd: client reuse, last-buffer exit, restart, and disk index reuse passed')
vim.cmd('qa!')
