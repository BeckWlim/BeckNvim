-- Real tree mappings replace a renderer-owned file in the existing editor pane.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/project/.git', 'p')
local project = root .. '/project'
vim.fn.writefile({ '# Existing file', '', 'Rendered Markdown.' }, project .. '/README.md')
vim.fn.writefile({ 'replacement' }, project .. '/target.txt')
local init_path = root .. '/init.lua'
vim.fn.writefile({
  ('vim.opt.runtimepath:prepend(%q)'):format(vim.fn.getcwd()),
  [[local lazy = vim.fn.stdpath('data') .. '/lazy/']],
  [[for _, plugin in ipairs({ 'nvim-tree.lua', 'nvim-web-devicons', 'nvim-treesitter' }) do vim.opt.runtimepath:append(lazy .. plugin) end]],
  [[dofile('tests/markdown_runtime.lua')]],
  [[require('config.startup.options')]],
  [[require('config.ui.window_state').setup()]],
  [[require('render-markdown').setup({ preview = { enabled = true } })]],
  [[local opts = require('plugins.extra')[2].opts]],
  [[opts.git = { enable = false }; opts.filesystem_watchers = { enable = false }]],
  [[require('nvim-tree').setup(opts)]],
  [[require('config.ui.filetree').setup()]],
}, init_path)
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '-n', '-u', init_path, '-i', 'NONE' }, {
  rpc = true, env = { XDG_CACHE_HOME = root .. '/cache', XDG_STATE_HOME = root .. '/state' },
})
local function evaluate(source)
  assert(not vim.rpcrequest(child, 'nvim_get_mode').blocking, 'Unexpected editor prompt')
  return vim.rpcrequest(child, 'nvim_exec_lua', source, { project })
end
local function preview()
  evaluate([[
    if _G.editor then vim.api.nvim_set_current_win(editor) end
    _G.editor = vim.api.nvim_get_current_win()
    vim.cmd.edit((...) .. '/README.md')
    vim.bo.filetype = 'markdown'
  ]])
  assert(vim.wait(2000, function()
    return evaluate([[return vim.b.markdown_preview_source ~= nil]])
  end, 20), 'Markdown did not display its generated preview')
end
local function check()
  vim.rpcrequest(child, 'nvim_ui_attach', 120, 40, { rgb = true })
  preview()
  evaluate([[
    local api = require('nvim-tree.api')
    api.tree.open({ path = ... })
    _G.tree = api.tree.winid()
    _G.layout = vim.fn.winlayout()
  ]])
  for _, key in ipairs({ '<CR>', 'o', 'O', '<2-LeftMouse>' }) do
    evaluate(([=[
      require('nvim-tree.api').tree.find_file({ buf = (...) .. '/target.txt', focus = true })
      local mapping = vim.fn.maparg(%q, 'n', false, true)
      assert(type(mapping.callback) == 'function', 'Missing tree open adapter')
      mapping.callback()
      assert(vim.api.nvim_get_current_win() == tree, 'Tree open lost tree focus')
      assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Ordinary tree open created a split')
      assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == (...) .. '/target.txt',
        'Ordinary tree open did not replace the current rendered file')
    ]=]):format(key))
    preview()
  end
  for _, key in ipairs({ '<C-x>', '<C-v>' }) do
    evaluate(([=[
      local preview_buffer = vim.api.nvim_win_get_buf(editor)
      require('nvim-tree.api').tree.find_file({ buf = (...) .. '/target.txt', focus = true })
      vim.fn.maparg(%q, 'n', false, true).callback()
      assert(vim.api.nvim_get_current_win() == tree, 'Explicit split lost tree focus')
      assert(#vim.api.nvim_tabpage_list_wins(0) == 3, 'Explicit command did not add one split')
      assert(vim.api.nvim_win_get_buf(editor) == preview_buffer, 'Explicit split replaced the original file')
      for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if window ~= editor and window ~= tree then
          assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) == (...) .. '/target.txt')
          vim.api.nvim_win_close(window, true)
        end
      end
      assert(vim.deep_equal(vim.fn.winlayout(), layout), 'Closing the explicit split changed the layout')
    ]=]):format(key))
  end
end
local passed, failure = xpcall(check, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(root, 'rf')
assert(passed, failure)
print('Installed tree opens replace rendered files; only explicit commands split')
