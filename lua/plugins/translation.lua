return {
  {
    'askfiy/smart-translate.nvim',
    cmd = { 'Translate' },
    dependencies = {
      'askfiy/http.nvim',
    },
    keys = {
      {
        '<Space>t',
        function()
          require('config.translation').open()
        end,
        mode = 'n',
        desc = 'Open translation query',
      },
    },
    opts = function()
      return require('config.translation').options()
    end,
    config = function(_, translation_options)
      require('smart-translate').setup(translation_options)

      -- The plugin builds completion candidates before setup registers custom
      -- handlers. Clear that early cache so the query result handler resolves.
      require('smart-translate.util')._handles = nil
    end,
  },
}
