local events = require('config.git.events')

assert(events.supports('ready'), 'Git event port did not publish its stable ready event')
assert(not events.supports('diffview_file_open_post'), 'Git event port leaked a renderer callback')

local received_payload
local unsubscribe = events.on('editor_rendered', function(payload)
  received_payload = payload
end)
assert(events.emit('editor_rendered', { generation = 7, rendered = true }))
assert(vim.wait(100, function()
  return received_payload ~= nil
end, 5), 'Git event port did not deliver its asynchronous callback')
assert(
  received_payload.generation == 7 and received_payload.rendered,
  'Git event port changed its callback payload'
)

unsubscribe()
received_payload = nil
events.emit('editor_rendered', { generation = 8, rendered = true })
vim.wait(20)
assert(received_payload == nil, 'Git event port did not release its subscription')
