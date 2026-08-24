local M = {}

---@class QueryPickerHandle
---@field find fun(self: QueryPickerHandle)
---@field refresh fun(self: QueryPickerHandle, finder: table, options: table)
---@field layout? table

local function picker_title(title, status, active)
  local action = active and 'q: cancel' or 'q: close'
  return ('%s · %s · %s'):format(title, status, action)
end

function M.open(options)
  local actions = require('telescope.actions')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  ---@type { cancel_functions: function[], closed: boolean, finished: boolean, picker: QueryPickerHandle?, prompt_buffer: integer? }
  local state = {
    cancel_functions = {},
    closed = false,
    finished = false,
    picker = nil,
    prompt_buffer = nil,
  }
  local session = {}

  local function change_title(status)
    local picker = state.picker
    if not picker or not picker.layout or not picker.layout.prompt then
      return
    end
    local prompt_border = picker.layout.prompt.border
    if prompt_border and prompt_border.change_title then
      prompt_border:change_title(picker_title(options.title, status, not state.finished))
    end
  end

  local function finder(records)
    return finders.new_table({
      results = records,
      entry_maker = options.entry_maker,
    })
  end

  function session:is_closed()
    return state.closed
  end

  function session:add_cancel(cancel_function)
    if state.closed and not state.finished then
      cancel_function()
      return
    end
    table.insert(state.cancel_functions, cancel_function)
  end

  function session:set_status(status)
    if state.closed then
      return
    end
    change_title(status)
  end

  function session:update(records, status)
    if state.closed then
      return
    end
    state.picker:refresh(finder(records), { reset_prompt = false })
    change_title(status)
  end

  function session:finish(records)
    if state.closed then
      return
    end
    state.finished = true
    local status = #records == 0 and 'no results' or ('%d results'):format(#records)
    state.picker:refresh(finder(records), { reset_prompt = false })
    change_title(status)
  end

  function session:fail(message)
    if state.closed then
      return
    end
    state.finished = true
    state.picker:refresh(finder({}), { reset_prompt = false })
    change_title(message)
  end

  function session:cancel()
    if state.closed then
      return
    end
    state.closed = true
    if not state.finished then
      for _, cancel_function in ipairs(state.cancel_functions) do
        cancel_function()
      end
    end
  end

  local picker = pickers.new(options.picker_options or {}, {
    prompt_title = picker_title(options.title, 'querying…', true),
    finder = finder({}),
    previewer = options.previewer,
    sorter = options.sorter,
    push_cursor_on_edit = true,
    push_tagstack_on_edit = true,
    attach_mappings = function(prompt_buffer, map)
      state.prompt_buffer = prompt_buffer
      local function cancel_and_close()
        session:cancel()
        actions.close(prompt_buffer)
      end
      map('i', 'q', cancel_and_close)
      map('n', 'q', cancel_and_close)
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = prompt_buffer,
        once = true,
        callback = session.cancel,
      })
      return true
    end,
  })
  state.picker = picker
  picker:find()
  return session
end

return M
