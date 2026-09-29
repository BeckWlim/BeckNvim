-- Real startup: the saved scheme must be the only scheme applied before VimEnter.
-- Run with -u NONE -i NONE '+luafile tests/ui/theme_startup_installed.lua'.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/nvim', 'p')
local store = require('config.state').open('theme', { directory = directory .. '/nvim' })
local startup = directory .. '/init.lua'
vim.fn.writefile(vim.split([[
local schemes = {}
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function(event) schemes[#schemes + 1] = event.match end,
})
dofile('init.lua')
local expected_name = vim.env.BECK_TEST_THEME
local expected_scheme = vim.env.BECK_TEST_SCHEME
assert(require('config.ui.theme').current().name == expected_name, 'Saved theme is not ready after setup')
assert(#schemes > 0, 'No theme was applied')
for _, name in ipairs(schemes) do
  assert(name == expected_scheme, 'Startup flashed another scheme: ' .. name)
end
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      -- Runtime setup remains asynchronous and must respect newer user input.
      require('config.ui.theme').setup()
      vim.cmd.colorscheme('habamax')
      vim.defer_fn(function()
        assert(vim.g.colors_name == 'habamax', 'Late restore replaced explicit user selection')
        vim.cmd('qa!')
      end, 100)
    end)
  end,
})
]], '\n', { plain = true }), startup)
local choices = {
  { name = 'paper-light', scheme = 'morning', background = 'light' },
  { name = 'catppuccin-mocha', scheme = 'catppuccin-mocha', background = 'dark' },
}
local function check(index)
  local choice = choices[index]
  if not choice then
    vim.fn.delete(directory, 'rf')
    print('Saved light/dark themes apply before VimEnter; runtime choices survive late reads')
    vim.cmd('qa!')
    return
  end
  assert(store:write_sync({ name = choice.name, background = choice.background }))
  vim.system({ vim.v.progpath, '--headless', '-u', startup, '-i', 'NONE' }, {
    text = true, timeout = 15000,
    env = { XDG_STATE_HOME = directory, XDG_CACHE_HOME = directory .. '/cache',
      BECK_TEST_THEME = choice.name, BECK_TEST_SCHEME = choice.scheme },
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.api.nvim_err_writeln(result.stderr .. result.stdout)
        vim.fn.delete(directory, 'rf')
        vim.cmd('cquit 1')
      else check(index + 1) end
    end)
  end)
end
check(1)
