local search = require('config.ui.tree_search')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/nested', 'p')
vim.fn.writefile({ 'a' }, root .. '/nested/with space.txt')
vim.fn.writefile({ 'b' }, root .. '/nested/.hidden.txt')
local result, failure
search.scan(root, false, function(paths, _, err) result, failure = paths, err end)
assert(vim.wait(2000, function() return result ~= nil end, 10))
assert(not failure and #result == 1 and result[1] == root .. '/nested/with space.txt')
local cancelled_called = false
local cancel = search.scan(root, true, function() cancelled_called = true end)
cancel()
vim.wait(100)
assert(not cancelled_called, 'Cancelled discovery delivered stale paths')
local previous_limit = search.limit
search.limit = 1
local capped
result = nil
search.scan(root, true, function(paths, limited) result, capped = paths, limited end)
assert(vim.wait(2000, function() return result ~= nil end, 10))
assert(#result == 1 and capped, 'Tree discovery was not bounded')
search.limit = previous_limit
vim.fn.delete(root, 'rf')
