local M = {}
local features = {
  require('config.syntax.markdown.table'),
  require('config.syntax.mermaid'),
}

function M.project(context)
  return require('config.syntax.markdown_features').project(features, context)
end

function M.detach(buffer)
  for _, feature in ipairs(features) do
    if feature.detach then feature.detach(buffer) end
  end
end

function M.toggle()
  require('config.syntax.markdown.preview').toggle()
end

function M.setup()
  require('config.syntax.markdown.preview').setup()
end

return M
