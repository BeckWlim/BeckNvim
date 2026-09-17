-- Presentation setup only; feature behavior comes from BeckNvim.
local work = assert(vim.env.BECKNVIM_DEMO_WORK)
local mooncake = work .. '/Mooncake/'
local notes = work .. '/WorkspaceNotes/'

-- The clone has no generated C++ headers or compilation database.
vim.diagnostic.enable(false)

-- Existing files seed recent projects in this isolated editor session.
vim.v.oldfiles = {
  mooncake .. 'mooncake-transfer-engine/include/transfer_engine.h',
  mooncake .. 'mooncake-transfer-engine/src/transfer_engine.cpp',
  mooncake .. 'mooncake-store/include/master_service.h',
  mooncake .. 'README.md',
  notes .. 'docs/table.md',
  notes .. 'docs/mermaid.md',
  notes .. 'src/cache.lua',
  notes .. 'README.md',
}
