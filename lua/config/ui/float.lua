local M = {
  input_close_key = '<C-q>',
  input_close_hint = 'Ctrl-Q',
  normal_close_key = 'q',
}

function M.bind_close(options)
  local close_callback = options.close
  local mapping_function = options.map
  local accepts_input = options.accepts_input == true

  if mapping_function then
    mapping_function('n', M.normal_close_key, close_callback)
    if accepts_input then
      mapping_function('i', M.input_close_key, close_callback)
    end
    return
  end

  local buffer_number = options.buffer
  local description = options.description or 'Close floating window'
  vim.keymap.set('n', M.normal_close_key, close_callback, {
    buffer = buffer_number,
    nowait = true,
    silent = true,
    desc = description,
  })
  if accepts_input then
    vim.keymap.set('i', M.input_close_key, close_callback, {
      buffer = buffer_number,
      nowait = true,
      silent = true,
      desc = description,
    })
  end
end

return M
