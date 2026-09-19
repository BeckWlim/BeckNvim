local hierarchy_index = require('config.python.hierarchy_index')
local original_exepath = vim.fn.exepath
local environment = require('config.python.environment')
local original_resolve = environment.resolve
local original_system = vim.system
local root = vim.fn.tempname()
vim.fn.exepath = function(command)
  if command == 'python3' then return '' end
  return original_exepath(command)
end
environment.resolve = function() return nil end
vim.system = function() error('Missing Python must not be spawned') end
for _ = 1, 2 do
  local callback_called = false
  hierarchy_index.ensure(root, function(document, error_message)
    callback_called = true
    assert(#document.classes == 0 and error_message:find('requires python3', 1, true),
      'Missing Python did not return an actionable feature error')
  end)
  assert(callback_called and hierarchy_index.status(root).status == 'error',
    'Missing Python left hierarchy indexing stuck loading')
end
vim.fn.exepath = original_exepath
environment.resolve = original_resolve
vim.system = original_system
hierarchy_index.reset()
