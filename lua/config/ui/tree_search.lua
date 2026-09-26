-- Bounded filesystem discovery and temporary reveal policy for filesystem trees.
local M = { limit = 5000 }

function M.find(targets, origin, pattern, direction, count, wrap)
  local case_prefix = vim.o.ignorecase
      and not (vim.o.smartcase and pattern:find('%u')) and '\\c' or '\\C'
  local valid, expression = pcall(vim.regex, case_prefix .. pattern)
  if not valid then
    return nil, 'Invalid search pattern'
  end
  local start = direction == 1 and 0 or #targets + 1
  for index, target in ipairs(targets) do
    if target.item == origin then
      start = index
      break
    end
  end
  local remaining = count
  for offset = 1, #targets * count do
    local position = start + direction * offset
    if not wrap and (position < 1 or position > #targets) then
      break
    end
    local target = targets[(position - 1) % #targets + 1]
    if expression:match_str(target.text) ~= nil then
      remaining = remaining - 1
      if remaining == 0 then
        return target
      end
    end
  end
  return nil, 'Pattern not found in tree: ' .. pattern
end

function M.scan(root, hidden, callback)
  local command = { 'rg', '--files', '--null', '--glob', '!.git', '.' }
  if hidden then table.insert(command, 2, '--hidden') end
  local paths, pending, stopped, capped = {}, '', false, false
  local process
  process = vim.system(command, {
    cwd = root,
    timeout = 5000,
    stdout = function(_, data)
      if stopped or not data or capped then return end
      pending = pending .. data
      while true do
        local ending = pending:find('\0', 1, true)
        if not ending then break end
        local relative = pending:sub(1, ending - 1):gsub('^%./', '')
        pending = pending:sub(ending + 1)
        paths[#paths + 1] = vim.fs.joinpath(root, relative)
        if #paths >= M.limit then
          capped = true
          pending = ''
          if process then process:kill(15) end
          break
        end
      end
    end,
  }, function(result)
    vim.schedule(function()
      if not stopped then
        callback(paths, capped, not capped and result.code > 1 and (result.stderr or 'Search failed') or nil)
      end
    end)
  end)
  return function()
    stopped = true
    process:kill(15)
  end
end

function M.attach(buffer, adapter)
  local generation, direction = 0, 1
  local cancel_scan
  local baseline
  local cached_root, cached_paths
  local function cancel()
    generation = generation + 1
    if cancel_scan then cancel_scan(); cancel_scan = nil end
    if adapter.cancel then adapter.cancel() end
  end
  local function manual()
    cancel()
    baseline = nil
    cached_root, cached_paths = nil, nil
  end
  local function search(pattern, step, count, origin, preview)
    generation = generation + 1
    local token = generation
    local root = adapter.root()
    if cached_root ~= root then
      if cancel_scan then cancel_scan(); cancel_scan = nil end
      cached_root, cached_paths, baseline = root, nil, nil
    end
    local function deliver(paths)
      if generation ~= token or not vim.api.nvim_buf_is_valid(buffer)
          or vim.api.nvim_get_current_buf() ~= buffer or adapter.root() ~= root then return end
      local targets, seen = {}, {}
      local function add(path)
        if path ~= root and not seen[path] then
          seen[path] = true
          targets[#targets + 1] = { item = path, text = path:sub(#root + 2) }
        end
      end
      for _, path in ipairs(adapter.paths()) do add(path) end
      for _, path in ipairs(paths) do
        add(path)
        local parent = vim.fs.dirname(path)
        while parent and parent ~= root and #parent > #root do
          add(parent)
          parent = vim.fs.dirname(parent)
        end
      end
      table.sort(targets, function(left, right) return left.item < right.item end)
      local match, err = M.find(targets, origin, pattern, step, count, vim.o.wrapscan)
      if match then
        baseline = baseline or adapter.snapshot()
        adapter.restore(baseline)
        adapter.reveal(match.item)
      elseif not preview then
        vim.notify((err or ''):gsub('loaded Git history', 'tree'), vim.log.levels.INFO)
      end
    end
    if cached_paths then
      deliver(cached_paths)
    elseif preview then
      deliver({})
    else
      if cancel_scan then cancel_scan() end
      local cursor_target = adapter.current()
      cancel_scan = M.scan(root, adapter.hidden and adapter.hidden() or false, function(paths, capped, err)
        if generation ~= token then return end
        cancel_scan = nil
        if adapter.current() ~= cursor_target then return end
        if err then vim.notify(err, vim.log.levels.WARN); return end
        cached_paths = paths
        if capped then vim.notify('Tree search limited to ' .. M.limit .. ' files', vim.log.levels.INFO) end
        deliver(paths)
      end)
    end
  end
  local function prompt(step)
    cancel()
    cached_paths = nil
    local origin, snapshot, previous_baseline = adapter.current(), adapter.snapshot(), baseline
    local count, previous = vim.v.count1, vim.fn.getreg('/')
    local change = vim.api.nvim_create_autocmd('CmdlineChanged', {
      callback = function()
        local query = vim.fn.getcmdline()
        if vim.o.incsearch and query ~= '' then search(query, step, count, origin, true) end
      end,
    })
    local ok, result = pcall(vim.fn.input, { prompt = step == 1 and '/' or '?', cancelreturn = '\27' })
    vim.api.nvim_del_autocmd(change)
    cancel()
    if not ok or result == '\27' then
      adapter.restore(snapshot)
      if origin then adapter.reveal(origin) end
      adapter.restore(snapshot)
      baseline = previous_baseline
      return
    end
    local pattern = result ~= '' and result or previous
    if pattern == '' then return end
    direction = step
    vim.v.searchforward = step == 1 and 1 or 0
    vim.fn.setreg('/', pattern)
    vim.fn.histadd('search', pattern)
    search(pattern, step, count, origin, false)
  end
  local function repeat_search(factor)
    local pattern = vim.fn.getreg('/')
    if pattern ~= '' then search(pattern, direction * factor, vim.v.count1, adapter.current(), false) end
  end
  require('config.keybindings').attach('tree', buffer, {
    search_forward = function() prompt(1) end,
    search_backward = function() prompt(-1) end,
    next_match = function() repeat_search(1) end,
    previous_match = function() repeat_search(-1) end,
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
    buffer = buffer,
    group = vim.api.nvim_create_augroup('ConfigTreeSearch' .. buffer, { clear = true }),
    callback = cancel,
  })
  return { manual = manual, cancel = cancel }
end

return M
