-- <Space>w window navigation: ijkl (up/left/down/right)
vim.keymap.set('n', '<Space>wi', '<C-w>k', { silent = true, desc = 'Window up' })
vim.keymap.set('n', '<Space>wj', '<C-w>h', { silent = true, desc = 'Window left' })
vim.keymap.set('n', '<Space>wk', '<C-w>j', { silent = true, desc = 'Window down' })
vim.keymap.set('n', '<Space>wl', '<C-w>l', { silent = true, desc = 'Window right' })

-- <Space>w split / close / only
vim.keymap.set('n', '<Space>wv', '<C-w>v', { silent = true, desc = 'Vertical split' })
vim.keymap.set('n', '<Space>ws', '<C-w>s', { silent = true, desc = 'Horizontal split' })
vim.keymap.set('n', '<Space>wq', '<C-w>q', { silent = true, desc = 'Close window' })
vim.keymap.set('n', '<Space>wo', '<C-w>o', { silent = true, desc = 'Only window' })

-- <Space>r resize: same ijkl intuition as window nav — push border in that direction
vim.keymap.set('n', '<Space>ri', '<C-w>3+', { silent = true, desc = 'Taller (push up)' })
vim.keymap.set('n', '<Space>rk', '<C-w>3-', { silent = true, desc = 'Shorter (push down)' })
vim.keymap.set('n', '<Space>rj', '<C-w>5<', { silent = true, desc = 'Narrower (push left)' })
vim.keymap.set('n', '<Space>rl', '<C-w>5>', { silent = true, desc = 'Wider (push right)' })
vim.keymap.set('n', '<Space>r=', '<C-w>=', { silent = true, desc = 'Equalize windows' })

-- Tab / S-Tab cycle through windows
vim.keymap.set('n', '<Tab>', '<C-w>w', { silent = true, desc = 'Next window' })
vim.keymap.set('n', '<S-Tab>', '<C-w>W', { silent = true, desc = 'Prev window' })

-- <Space>o/p: jump list backward/forward
vim.keymap.set('n', '<Space>o', '<C-o>', { silent = true, desc = 'Jump back' })
vim.keymap.set('n', '<Space>p', '<C-i>', { silent = true, desc = 'Jump forward' })

-- Treesitter-aware code folding
vim.keymap.set('n', '<Space>zz', 'za', { silent = true, desc = 'Toggle code fold' })
vim.keymap.set('n', '<Space>zc', 'zM', { silent = true, desc = 'Close all code folds' })
vim.keymap.set('n', '<Space>zo', 'zR', { silent = true, desc = 'Open all code folds' })

-- <Space>gf: jump to referenced file (include/import/require)
-- Priority: LSP → telescope fallback (works for C++, Python, Lua)
local function goto_referenced_file()
  local line = vim.api.nvim_get_current_line()

  local is_include = line:match('#include%s+["<](.-)[">]')
  local is_py_import = line:match('from%s+(%S+)%s+import') or line:match('import%s+(%S+)')
  local is_lua_req = line:match([=[require%s*%(?%s*["'](.-)["']]=])

  -- Any recognized reference: try LSP first for exact jump
  if is_include or is_py_import or is_lua_req then
    pcall(function() vim.lsp.buf.definition() end)
    -- Check if cursor actually moved (LSP succeeded)
    -- If LSP has no clients or fails, fall back to telescope
    if vim.lsp.get_clients({ bufnr = 0 }) and #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
      -- No LSP client: use telescope
      local path = nil
      if is_include then
        path = is_include
      elseif is_py_import then
        path = is_py_import:gsub('%.', '/') .. '.py'
      elseif is_lua_req then
        path = is_lua_req:gsub('%.', '/') .. '.lua'
      end
      if path then
        local builtin = require('telescope.builtin')
        builtin.find_files({ default_text = path:match('[^/]+$') or path })
      end
    end
  else
    vim.lsp.buf.definition()
  end
end

vim.keymap.set('n', '<Space>gf', goto_referenced_file, { silent = true, desc = 'Go to referenced file' })

-- <Space>gv: vertical-split then jump
vim.keymap.set('n', '<Space>gv', function()
  vim.cmd.vsplit()
  goto_referenced_file()
end, { silent = true, desc = 'Go to referenced file (vertical split)' })

-- <Space>gx: horizontal-split then jump
vim.keymap.set('n', '<Space>gx', function()
  vim.cmd.split()
  goto_referenced_file()
end, { silent = true, desc = 'Go to referenced file (horizontal split)' })

vim.keymap.set('n', '<F3>', ':NvimTreeToggle<CR>', { silent = true, desc = "Toggle file tree" })
vim.keymap.set('n', '<Space>mp', '<cmd>RenderMarkdown toggle<CR>', { silent = true, desc = 'Toggle markdown preview' })
vim.api.nvim_create_autocmd({"QuitPre"}, {
    callback = function()
      if vim.fn.exists(":NvimTreeClose") == 2 then
        vim.cmd("NvimTreeClose")
      end
    end,
})


vim.keymap.set('n', '<Space>e', vim.diagnostic.open_float, { noremap=true, silent=true, desc = "Show diagnostic float" })
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { noremap=true, silent=true, desc = "Previous diagnostic" })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { noremap=true, silent=true, desc = "Next diagnostic" })
vim.keymap.set('n', '<Space>q', vim.diagnostic.setloclist, { noremap=true, silent=true, desc = "Diagnostic list" })
vim.keymap.set('n', '<Space>i', vim.lsp.buf.implementation, { noremap=true, silent=true, desc = "Go to implementation" })
vim.keymap.set('n', '<Space>D', vim.lsp.buf.type_definition, { noremap=true, silent=true, desc = "Go to type definition" })
vim.keymap.set('n', '<Space>rn', vim.lsp.buf.rename, { noremap=true, silent=true, desc = "Rename symbol" })
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { noremap=true, silent=true, desc = "Show hover documentation" })

-- Toggle diagnostics related to unavailable third-party dependencies/type stubs.
local check_third_party_libraries = true
vim.keymap.set('n', '<Space>lp', function()
  check_third_party_libraries = not check_third_party_libraries
  local severities = check_third_party_libraries and {
    reportMissingImports = 'error',
    reportMissingModuleSource = 'warning',
    reportMissingTypeStubs = 'warning',
  } or {
    reportMissingImports = 'none',
    reportMissingModuleSource = 'none',
    reportMissingTypeStubs = 'none',
  }
  local settings = {
    basedpyright = {
      analysis = {
        diagnosticSeverityOverrides = severities,
      },
    },
  }
  vim.lsp.config('basedpyright', { settings = settings })
  local clients = vim.lsp.get_clients({ name = 'basedpyright' })

  for _, client in ipairs(clients) do
    client.settings = vim.tbl_deep_extend('force', client.settings or {}, settings)
    client:notify('workspace/didChangeConfiguration', { settings = client.settings })
  end

  vim.notify(
    ('basedpyright third-party dependency diagnostics: %s'):format(
      check_third_party_libraries and 'enabled' or 'disabled'
    )
  )
end, { noremap=true, silent=true, desc = 'Toggle basedpyright third-party checks' })
