-- Live preview must match direct selection for every shared UI surface.
-- nvim --headless -u NONE -i NONE -l tests/ui/theme_preview_installed.lua
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local child = vim.fn.jobstart({
  vim.v.progpath, '--headless', '--embed', '-n', '-u', 'init.lua', '-i', 'NONE',
}, { rpc = true, env = { XDG_STATE_HOME = directory } })
local function evaluate(source, arguments)
  return vim.rpcrequest(child, 'nvim_exec_lua', source, arguments or {})
end
local function wait_for(source, message)
  assert(vim.wait(3000, function() return evaluate(source) end, 10), message)
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  evaluate([[
    require('telescope').setup({ defaults = { history = { path = ... } } })
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Theme preview fixture' })
    vim.g.theme_comparison_buffer = vim.api.nvim_get_current_buf()
    _G.theme_comparison_snapshot = function()
      local groups = {}
      for _, name in ipairs({ 'Normal', 'NormalNC', 'NormalFloat', 'FloatBorder',
          'TelescopeNormal', 'TelescopePromptNormal', 'TelescopeResultsNormal', 'TelescopePreviewNormal',
          'TelescopeBorder', 'TelescopeSelection', 'TreesitterContext', 'TreesitterContextBottom',
          'TreesitterContextPreview', 'StatusLine', 'StatusLineNC',
          'lualine_c_normal', 'lualine_c_inactive', 'CurrentCodeScope' }) do
        local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
        highlight.ctermfg = nil
        highlight.ctermbg = nil
        highlight.cterm = nil
        groups[name] = highlight
      end
      return groups
    end
  ]], { directory .. '/history' })
  for _, name in ipairs({ 'monokai', 'vscode-dark', 'darcula-dark', 'tokyonight-night',
      'catppuccin-mocha', 'catppuccin-latte', 'gruvbox-dark', 'paper-light' }) do
    evaluate([[assert(require('config.ui.theme').select(...))]], { name })
    vim.wait(40)
    evaluate([[
      vim.g.theme_comparison_expected = _G.theme_comparison_snapshot()
      vim.g.theme_comparison_target = ...
      assert(require('config.ui.theme').select(vim.o.background == 'light' and 'monokai' or 'paper-light'))
      require('config.ui.theme').pick()
      local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
      picker:set_prompt(vim.g.theme_comparison_target)
    ]], { name })
    wait_for([[
      local entry = require('telescope.actions.state').get_selected_entry()
      return entry and entry.value == vim.g.theme_comparison_target
        and require('config.ui.theme').current().name == vim.g.theme_comparison_target
    ]], name .. ': live preview did not load')
    vim.wait(40)
    evaluate([[
      local actual = _G.theme_comparison_snapshot()
      for name, expected in pairs(vim.g.theme_comparison_expected) do
        assert(vim.deep_equal(actual[name], expected), name .. ': live preview differs from applied theme: '
          .. vim.inspect({ theme = vim.g.theme_comparison_target, background = vim.o.background, preview = actual[name], applied = expected, current_normal = actual.Normal, expected_normal = vim.g.theme_comparison_expected.Normal }))
      end
    ]])
    vim.rpcrequest(child, 'nvim_input', '<CR>')
    wait_for([[return vim.api.nvim_get_current_buf() == vim.g.theme_comparison_buffer]],
      name .. ': confirmation did not close the picker')
    wait_for([[
      local path = require('config.ui.theme').state_path()
      return vim.fn.filereadable(path) == 1
        and vim.json.decode(table.concat(vim.fn.readfile(path))).name == vim.g.theme_comparison_target
    ]], name .. ': confirmation did not save the previewed theme')
  end
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(directory, 'rf')
assert(passed, failure)
print('Installed preview/applied module parity and confirmation passed for all eight themes')
