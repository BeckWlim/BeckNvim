-- Focused tests for config.ui.statusline.
local original_lualine = package.loaded.lualine
local original_statusline = package.loaded['config.ui.statusline']
local original_branch_component = package.loaded['lualine.components.branch.git_branch']
local lualine_options
local lualine_refresh_options
local branch_refreshes = 0
package.loaded.lualine = {
  refresh = function(options)
    lualine_refresh_options = options
  end,
  setup = function(options)
    lualine_options = options
  end,
}
package.loaded['lualine.components.branch.git_branch'] = {
  find_git_dir = function()
    branch_refreshes = branch_refreshes + 1
  end,
}
package.loaded['config.ui.statusline'] = nil

local statusline = require('config.ui.statusline')
statusline.setup()
assert(lualine_options, 'statusline did not configure lualine')
local project_component = lualine_options.sections.lualine_c[1]
assert(type(project_component[1]) == 'function', 'project statusline component is not dynamic')
assert(statusline.project_icons.git == '', 'generic Git project icon is not repository-shaped')
assert(statusline.project_icons.workspace == '', 'workspace fallback icon is not project-shaped')
local project_identity = project_component[1]()
assert(not project_identity:find('PROJECT', 1, true), 'statusline retained the literal PROJECT label')
assert(project_identity:match(' nvim$'), 'statusline did not render the repository name')

local original_buffer = vim.api.nvim_get_current_buf()
local project_directory = vim.fn.tempname()
vim.fn.mkdir(project_directory .. '/.git', 'p')
vim.fn.mkdir(project_directory .. '/docs/production', 'p')
local source_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(source_buffer, project_directory .. '/docs/production/report.md')
vim.api.nvim_set_current_buf(source_buffer)
local source_identity = statusline.project_identity()
assert(statusline.project_name() == vim.fs.basename(project_directory), 'Source project follows the working directory')
assert(statusline.project_relative_path() == 'docs/production/report.md', 'Source path is not project-relative')

local preview_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(preview_buffer, 'markdown-preview://' .. source_buffer)
vim.b[preview_buffer].markdown_preview_source = source_buffer
vim.bo[preview_buffer].readonly = true
vim.bo[preview_buffer].modifiable = false
vim.api.nvim_set_current_buf(preview_buffer)
assert(statusline.project_identity() == source_identity, 'Preview lost its source project identity')
assert(statusline.project_name() == vim.fs.basename(project_directory), 'Preview lost its source project name')
assert(statusline.project_relative_path() == 'docs/production/report.md', 'Preview exposes its scratch path or flags')
vim.bo[source_buffer].modified = true
assert(statusline.project_relative_path() == 'docs/production/report.md [+]', 'Preview hides unsaved source changes')
vim.bo[source_buffer].readonly = true
assert(statusline.project_relative_path() == 'docs/production/report.md [+] [RO]', 'Preview hides source read-only state')
vim.api.nvim_buf_delete(source_buffer, { force = true })
assert(pcall(statusline.project_relative_path), 'Stale preview source caused a statusline error')
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(preview_buffer, { force = true })
vim.fn.delete(project_directory, 'rf')

statusline.refresh_git_branch()
assert(branch_refreshes == 1, 'statusline did not refresh lualine branch state')
assert(
  lualine_refresh_options
    and lualine_refresh_options.force
    and vim.deep_equal(lualine_refresh_options.place, { 'statusline' }),
  'branch refresh did not redraw the statusline immediately'
)

package.loaded.lualine = original_lualine
package.loaded['lualine.components.branch.git_branch'] = original_branch_component
package.loaded['config.ui.statusline'] = original_statusline
