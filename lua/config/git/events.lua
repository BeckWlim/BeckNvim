local M = {}

local listeners = {}

local supported_events = {
  anchor_finished = true,
  editor_rendered = true,
  phase = true,
  ready = true,
  return_finished = true,
  return_started = true,
}

function M.on(event_name, callback)
  if not supported_events[event_name] then
    error(('Unsupported Git event: %s'):format(tostring(event_name)))
  end
  if type(callback) ~= 'function' then
    error('Git event callback must be a function')
  end
  local event_listeners = listeners[event_name] or {}
  event_listeners[#event_listeners + 1] = callback
  listeners[event_name] = event_listeners
  local subscribed = true
  return function()
    if not subscribed then
      return
    end
    subscribed = false
    for listener_index, registered_callback in ipairs(event_listeners) do
      if registered_callback == callback then
        table.remove(event_listeners, listener_index)
        return
      end
    end
  end
end

function M.emit(event_name, payload)
  if not supported_events[event_name] then
    return false
  end
  local event_listeners = vim.list_slice(listeners[event_name] or {})
  if #event_listeners == 0 then
    return true
  end
  vim.schedule(function()
    for _, callback in ipairs(event_listeners) do
      local callback_succeeded, callback_error = pcall(callback, payload)
      if not callback_succeeded then
        vim.schedule(function()
          vim.notify(
            ('Git event %s callback failed: %s'):format(event_name, callback_error),
            vim.log.levels.ERROR
          )
        end)
      end
    end
  end)
  return true
end

function M.supports(event_name)
  return supported_events[event_name] == true
end

return M
