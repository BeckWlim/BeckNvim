return function(config)
  require('config.dashboard').attach(config.bufnr, config.winid)
end
