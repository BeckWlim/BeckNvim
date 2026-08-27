local original_telescope_builtin = package.loaded['telescope.builtin']
local original_diagnostics = package.loaded['config.diagnostics']

local picker_options
package.loaded['telescope.builtin'] = {
  diagnostics = function(options)
    picker_options = options
  end,
}
package.loaded['config.diagnostics'] = nil

local diagnostics = require('config.diagnostics')
diagnostics.open_picker()

assert(picker_options, 'diagnostic picker was not opened')
assert(picker_options.bufnr == 0, 'diagnostic picker did not target the current buffer')

package.loaded['telescope.builtin'] = original_telescope_builtin
package.loaded['config.diagnostics'] = original_diagnostics
