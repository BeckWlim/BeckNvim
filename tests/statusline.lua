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
