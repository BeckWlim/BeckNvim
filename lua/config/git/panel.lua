local float = require('config.ui.float')

local M = {
  close_key = float.input_close_key,
}

local state = {
  git_layer = nil,
  search_layer = nil,
}

local function layer(owner, close_callback)
  return {
    close = close_callback,
    owner = owner,
  }
end

function M.enter_git(owner, close_callback)
  state.git_layer = layer(owner, close_callback)
  state.search_layer = nil
end

function M.leave_git(owner)
  local git_layer = state.git_layer
  if not git_layer or git_layer.owner ~= owner then
    return false
  end
  state.git_layer = nil
  state.search_layer = nil
  return true
end

function M.enter_search(owner, close_callback)
  state.search_layer = layer(owner, close_callback)
end

function M.leave_search(owner)
  local search_layer = state.search_layer
  if not search_layer or search_layer.owner ~= owner then
    return false
  end
  state.search_layer = nil
  return true
end

function M.pop()
  local search_layer = state.search_layer
  if search_layer then
    state.search_layer = nil
    search_layer.close()
    return 'search'
  end

  local git_layer = state.git_layer
  if git_layer then
    state.git_layer = nil
    git_layer.close()
    return 'git'
  end
  return nil
end

function M.reset()
  state.git_layer = nil
  state.search_layer = nil
end

function M.level()
  if state.search_layer then
    return 'search'
  end
  if state.git_layer then
    return 'git'
  end
  return 'editor'
end

return M
