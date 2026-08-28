local original_lualine = package.loaded.lualine
local original_statusline = package.loaded['config.statusline']
local lualine_options
package.loaded.lualine = {
  setup = function(options)
    lualine_options = options
  end,
}
package.loaded['config.statusline'] = nil

local statusline = require('config.statusline')
statusline.setup()
assert(lualine_options, 'statusline did not configure lualine')
local project_component = lualine_options.sections.lualine_c[1]
assert(type(project_component[1]) == 'function', 'project statusline component is not dynamic')
assert(statusline.project_icons.git == '', 'generic Git project icon is not repository-shaped')
assert(statusline.project_icons.workspace == '', 'workspace fallback icon is not project-shaped')
local project_identity = project_component[1]()
assert(not project_identity:find('PROJECT', 1, true), 'statusline retained the literal PROJECT label')
assert(project_identity:match(' nvim$'), 'statusline did not render the repository name')

package.loaded.lualine = original_lualine
package.loaded['config.statusline'] = original_statusline
