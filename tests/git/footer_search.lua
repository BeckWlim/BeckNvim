local search = require('config.git.footer_search')
local first = { commit = { hash = 'abc', subject = 'First commit' }, folded = true,
  files = { { path = 'src/needle.lua', oldpath = 'old/name.lua' } } }
local second = { commit = { hash = 'def', subject = 'Second commit' }, folded = true,
  files = { { path = 'tests/needle.lua' } } }
local targets = search.targets({ first, second })
assert(search.find(targets, first, 'needle', 1, 1, true).item == first.files[1])
assert(search.find(targets, first.files[1], 'needle', 1, 1, true).item == second.files[1])
assert(search.find(targets, first.files[1], 'needle', -1, 1, true).item == second.files[1])
assert(search.find(targets, first, 'needle', 1, 2, true).item == second.files[1])
assert(search.find(targets, first, 'old/name', 1, 1, true).item == first.files[1])
assert(search.find(targets, first, 'Second', 1, 1, true).item == second)
assert(not search.find(targets, second.files[1], 'needle', 1, 1, false))
assert(not search.find(targets, first, '\\(', 1, 1, true))
local ignorecase, smartcase = vim.o.ignorecase, vim.o.smartcase
vim.o.ignorecase, vim.o.smartcase = true, true
assert(search.find(targets, first, 'NEEDLE\\c', 1, 1, true))
assert(not search.find(targets, first, 'NEEDLE', 1, 1, true))
vim.o.ignorecase, vim.o.smartcase = ignorecase, smartcase
print('Git footer search tests passed')
