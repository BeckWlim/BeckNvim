local M = {}

local function referenced_path()
  local current_line = vim.api.nvim_get_current_line()
  local include_path = current_line:match('#include%s+["<](.-)[">]')
  if include_path then
    return include_path
  end

  local python_module = current_line:match('from%s+(%S+)%s+import')
    or current_line:match('import%s+(%S+)')
  if python_module then
    return python_module:gsub('%.', '/') .. '.py'
  end

  local lua_module = current_line:match([=[require%s*%(?%s*["'](.-)["']]=])
  if lua_module then
    return lua_module:gsub('%.', '/') .. '.lua'
  end
end

local function find_referenced_file(path)
  require('telescope.builtin').find_files({
    default_text = path:match('[^/]+$') or path,
  })
end

function M.goto_referenced_file()
  local referenced_file = referenced_path()
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/definition' })
  if #clients > 0 then
    vim.lsp.buf.definition()
    return
  end

  if referenced_file then
    find_referenced_file(referenced_file)
  else
    vim.notify('No LSP definition provider is attached', vim.log.levels.INFO)
  end
end

function M.goto_referenced_file_in_split(command)
  vim.cmd(command)
  M.goto_referenced_file()
end

return M
