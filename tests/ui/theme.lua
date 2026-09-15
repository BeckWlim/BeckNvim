-- Theme persistence, failed selection, and asynchronous startup races.
local theme = require('config.ui.theme')
local original = {
  name = vim.g.colors_name or 'default',
  background = vim.o.background,
}
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local path = directory .. '/theme.json'
local runtime = directory .. '/runtime'
vim.fn.mkdir(runtime .. '/themes/default', 'p')
vim.opt.runtimepath:prepend(runtime)
vim.fn.writefile({ "return { colorscheme = 'habamax', background = 'dark' }" },
  runtime .. '/themes/default/personal.lua')
vim.fn.writefile({ "return { colorscheme = 'morning', background = 'light' }" },
  runtime .. '/themes/personal.lua')
local function saved(name)
  return vim.wait(1000, function()
    if vim.fn.filereadable(path) == 0 then return false end
    local decoded, selection = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    return decoded and selection.name == name
  end, 10)
end
local function assert_theme(name)
  assert(vim.wait(1000, function() return vim.g.colors_name == name end, 10), 'Expected theme ' .. name)
end
-- An absent preference uses the configured default.
theme.setup({ default = 'habamax', state_file = path })
vim.wait(30)
assert(vim.g.colors_name == 'habamax')
assert(theme.select('morning'))
assert(saved('morning'), 'Confirmed theme was not saved')
assert(vim.json.decode(table.concat(vim.fn.readfile(path))).background == 'light', 'Saved theme lost its variant')
theme.setup({ default = 'habamax', state_file = path })
assert_theme('morning')
assert(vim.tbl_contains(theme.names(), 'personal'), 'New user theme was not discovered')
assert(theme.select('personal') and vim.g.colors_name == 'morning', 'User theme did not override its default')
assert(saved('personal') and theme.current().name == 'personal', 'Preset identity was replaced by its native theme')
vim.fn.delete(runtime .. '/themes/personal.lua')
assert(theme.select('personal') and vim.g.colors_name == 'habamax', 'Removed user theme hid the bundled default')
assert(saved('personal'))
vim.fn.writefile(vim.split([[return {
  colorscheme = 'habamax', background = 'dark',
  palette = { background = 0x202020, foreground = 0xEEEEEE,
    red = 0xDD5577, green = 0x99CC77, yellow = 0xDDCC77,
    blue = 0x77BBDD, purple = 0xBB99DD, orange = 0xDDAA77 },
}]], '\n', { plain = true }), runtime .. '/themes/custom.lua')
assert(theme.select('custom') and saved('custom'), 'Custom palette selection failed')
assert(vim.api.nvim_get_hl(0, { name = 'Normal' }).bg == 0x202020
  and vim.api.nvim_get_hl(0, { name = 'NormalFloat' }).bg == 0x202020,
  'Custom base palette was not shared with project surfaces')
vim.fn.writefile({ 'return { colorscheme = "habamax", palette = { background = -1 } }' },
  runtime .. '/themes/broken.lua')
assert(not theme.select('broken') and theme.current().name == 'custom',
  'Invalid palette did not restore the previous preset')
-- Only the last confirmation survives a burst of asynchronous writes.
assert(theme.select('habamax'))
assert(theme.select('morning'))
assert(theme.select('habamax'))
assert(saved('habamax'), 'An older write replaced the latest selection')
-- Native :colorscheme is transient; a pending restore must not supersede it.
theme.setup({ default = 'habamax', state_file = path })
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { 'morning' } }, {})
vim.wait(50)
assert(vim.g.colors_name == 'morning', 'Startup restore superseded an explicit colorscheme change')
assert(saved('habamax'), 'Native colorscheme unexpectedly persisted a preference')
-- Invalid and unavailable names retain both the active and persisted choices.
assert(not theme.select('habamax | quit'))
assert(not theme.select('becknvim_missing_theme'))
assert(vim.g.colors_name == 'morning' and saved('habamax'))
-- Malformed, oversized, and removed preferences fall back without blocking startup.
for _, document in ipairs({ '{', string.rep('x', 4097),
  vim.json.encode({ name = 'becknvim_missing_theme', background = 'light' }),
  vim.json.encode({ name = 'morning', background = 'invalid' }),
}) do
  vim.fn.writefile({ document }, path)
  theme.setup({ default = 'habamax', state_file = path })
  vim.wait(50)
  assert(vim.g.colors_name == 'habamax', 'Invalid saved preference displaced the default')
end
-- A missing preferred default still starts with a built-in theme.
vim.fn.delete(path)
theme.setup({ default = 'becknvim_missing_theme', state_file = path })
assert_theme('habamax')
vim.wait(50)
vim.o.background = original.background
vim.api.nvim_cmd({ cmd = 'colorscheme', args = { original.name } }, {})
vim.opt.runtimepath:remove(runtime)
vim.fn.delete(directory, 'rf')
