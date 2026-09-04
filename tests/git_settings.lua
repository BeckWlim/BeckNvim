local original_user = package.loaded['config.user']
local original_settings = package.loaded['config.git.settings']

package.loaded['config.user'] = {
  get = function()
    return {}
  end,
}
package.loaded['config.git.settings'] = nil
local default_settings = require('config.git.settings').footer()
assert(
  default_settings.detail_batch_entries == 8
    and default_settings.detail_worker_count == 4
    and default_settings.list_batch_entries == 200
    and default_settings.list_max_entries == 600,
  'Git footer defaults lost the four-worker configuration'
)

package.loaded['config.user'] = {
  get = function()
    return {
      git = {
        footer = {
          detail_batch_entries = 12,
          detail_worker_count = 8,
          list_batch_entries = 100,
          list_margin_entries = 200,
          list_max_entries = 50,
          preview_headroom_entries = 1000,
          request_timeout_ms = 500,
        },
      },
    }
  end,
}
package.loaded['config.git.settings'] = nil
local custom_settings = require('config.git.settings').footer()
assert(
  custom_settings.detail_batch_entries == 12
    and custom_settings.detail_worker_count == 8
    and custom_settings.list_batch_entries == 100
    and custom_settings.list_margin_entries == 99
    and custom_settings.list_max_entries == 100
    and custom_settings.preview_headroom_entries == 99
    and custom_settings.request_timeout_ms == 10000,
  '~/.nvim Git footer overrides were not validated or normalized'
)

package.loaded['config.user'] = original_user
package.loaded['config.git.settings'] = original_settings
