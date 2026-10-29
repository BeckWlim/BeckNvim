-- Run with -u init.lua. Exercise each installed server through native activation.
local fixture_root = vim.fn.tempname()
vim.fn.mkdir(fixture_root, 'p')
local scenarios = {
  { name = 'clangd', package = 'clangd', extension = 'cpp', source = 'int value = 1;' },
  { name = 'basedpyright', package = 'basedpyright', extension = 'py', source = 'value = 1' },
  { name = 'lua_ls', package = 'lua-language-server', extension = 'lua', source = 'return 1' },
  { name = 'bashls', package = 'bash-language-server', extension = 'sh', source = '#!/bin/bash\necho value' },
  { name = 'vimls', package = 'vim-language-server', extension = 'vim', source = 'let value = 1' },
  { name = 'marksman', package = 'marksman', extension = 'md', source = '# Value' },
}

local function drain_callbacks()
  local drained = false
  vim.schedule(function() drained = true end)
  assert(vim.wait(1000, function() return drained end), 'Event-loop callbacks did not run')
end

local function open_file(path, server_name)
  vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.wait(30000, function()
    local clients = vim.lsp.get_clients({ bufnr = buffer, name = server_name })
    return #clients == 1 and clients[1].initialized
  end, 20), server_name .. ': native activation did not attach exactly one server')
  return buffer, assert(vim.lsp.get_clients({ bufnr = buffer, name = server_name })[1])
end

local function assert_running(client, buffer, message)
  assert(not client:is_stopped() and client.attached_buffers[buffer], client.name .. ': ' .. message)
end

local function wait_for_exit(client)
  local exited = vim.wait(15000, function()
    return vim.lsp.get_client_by_id(client.id) == nil
  end, 20)
  local remaining_buffers = {}
  for buffer in pairs(client.attached_buffers) do
    remaining_buffers[#remaining_buffers + 1] = vim.api.nvim_buf_get_name(buffer)
  end
  assert(exited, client.name .. ': process did not exit after its final buffer closed: '
    .. vim.inspect({ stopped = client:is_stopped(), buffers = remaining_buffers, requests = client.requests }))
end

-- Load the installed registry without opening any language-specific file first.
require('lazy').load({ plugins = { 'mason-lspconfig.nvim' } })
local registry = require('mason-registry')
local checked_servers = 0
for _, scenario in ipairs(scenarios) do
  if #arg > 0 and not vim.list_contains(arg, scenario.name) then
    -- Optional filters allow retesting a server without restarting every fixture.
  elseif registry.is_installed(scenario.package) then
    local first_root = fixture_root .. '/' .. scenario.name .. '/first'
    local second_root = fixture_root .. '/' .. scenario.name .. '/second'
    for _, root in ipairs({ first_root, second_root }) do
      vim.fn.mkdir(root, 'p')
      vim.fn.system({ 'git', 'init', '--quiet', root })
      assert(vim.v.shell_error == 0, 'Could not initialize disposable project')
      -- Keep Lua's test workspace bounded and avoid interactive third-party setup.
      if scenario.name == 'lua_ls' then
        vim.fn.writefile({ '{"workspace.checkThirdParty":false}' }, root .. '/.luarc.json')
      end
      for _, stem in ipairs({ 'main', 'other' }) do
        vim.fn.writefile(vim.split(scenario.source, '\n'), root .. '/' .. stem .. '.' .. scenario.extension)
      end
    end
    local first_path = first_root .. '/main.' .. scenario.extension
    local other_path = first_root .. '/other.' .. scenario.extension
    local second_path = second_root .. '/main.' .. scenario.extension
    local first_buffer, first_client = open_file(first_path, scenario.name)

    -- Two windows displaying one buffer do not create two server instances.
    vim.cmd('vsplit')
    drain_callbacks()
    local split_clients = vim.lsp.get_clients({ bufnr = first_buffer, name = scenario.name })
    assert(#split_clients == 1 and split_clients[1].id == first_client.id,
      scenario.name .. ': splitting a window duplicated the server')
    vim.cmd('close')
    drain_callbacks()
    assert_running(first_client, first_buffer, 'closing one window stopped the server')

    -- Another file in another tab shares the same project server.
    vim.cmd('tabnew')
    local other_buffer, other_client = open_file(other_path, scenario.name)
    assert(other_client.id == first_client.id, scenario.name .. ': tabs duplicated a project server')
    vim.cmd('tabnew')
    local second_buffer, second_client = open_file(second_path, scenario.name)
    assert(second_client.id ~= first_client.id, scenario.name .. ': unrelated roots shared a client')
    vim.cmd('tabclose')
    drain_callbacks()
    assert_running(second_client, second_buffer, 'closing a tab stopped a hidden project buffer')

    vim.api.nvim_buf_delete(first_buffer, { force = true })
    drain_callbacks()
    assert_running(first_client, other_buffer, 'closing one buffer disrupted another tab')
    vim.api.nvim_buf_delete(other_buffer, { force = true })
    wait_for_exit(first_client)
    assert_running(second_client, second_buffer, 'closing the first project stopped the second')

    local reopened_buffer, reopened_client = open_file(first_path, scenario.name)
    assert(reopened_client.id ~= first_client.id, scenario.name .. ': reopening did not restart')
    -- :bunload must release a server even though the buffer remains listed.
    vim.api.nvim_buf_delete(second_buffer, { unload = true })
    wait_for_exit(second_client)
    assert_running(reopened_client, reopened_buffer, 'unloading the second project stopped the first')
    vim.api.nvim_buf_delete(second_buffer, { force = true })
    vim.api.nvim_buf_delete(reopened_buffer, { force = true })
    wait_for_exit(reopened_client)
    vim.cmd('tabonly')
    checked_servers = checked_servers + 1
    print(scenario.name .. ': split/tab reuse, hidden buffers, project isolation, unload, and restart passed')
  else
    print(scenario.name .. ': skipped (not installed through Mason)')
  end
end
assert(checked_servers > 0, 'No installed language server was tested')
vim.fn.delete(fixture_root, 'rf')
print(('Installed server lifecycle checks passed for %d servers'):format(checked_servers))
vim.cmd('qa!')
