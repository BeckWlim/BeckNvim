local M = {}
local rainbow_attached_buffers = {}

-- Parsers the config features depend on beyond Neovim's bundled set.
local required_parsers = { 'python', 'cpp' }

local function start_highlighting(buffer_number)
  if not vim.api.nvim_buf_is_valid(buffer_number)
      or not vim.api.nvim_buf_is_loaded(buffer_number)
      or vim.treesitter.highlighter.active[buffer_number] then
    return
  end
  local buffer_name = vim.api.nvim_buf_get_name(buffer_number)
  if vim.startswith(buffer_name, 'diffview://')
      and #vim.fn.win_findbuf(buffer_number) == 0 then
    return
  end
  pcall(vim.treesitter.start, buffer_number)
end

function M.ensure_highlighting(buffer_number)
  start_highlighting(buffer_number)
  if not vim.g.loaded_rainbow_delimiters or rainbow_attached_buffers[buffer_number] then
    return
  end
  local rainbow_loaded, rainbow = pcall(require, 'rainbow-delimiters.lib')
  if rainbow_loaded and type(rainbow.attach) == 'function' then
    local attach_succeeded = pcall(rainbow.attach, buffer_number)
    if attach_succeeded then
      rainbow_attached_buffers[buffer_number] = true
    end
  end
end

local function start_loaded_buffers(parser_languages)
  for _, buffer_number in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer_number) then
      local buffer_filetype = vim.bo[buffer_number].filetype
      local parser_language = vim.treesitter.language.get_lang(buffer_filetype)
        or buffer_filetype
      if vim.list_contains(parser_languages, parser_language) then
        start_highlighting(buffer_number)
      end
    end
  end
end

function M.setup()
  local treesitter = require('nvim-treesitter')
  treesitter.setup()

  -- The main branch no longer starts highlighting itself; Neovim owns it.
  local highlight_group = vim.api.nvim_create_augroup('config-treesitter-highlight', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = highlight_group,
    callback = function(event)
      start_highlighting(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = highlight_group,
    callback = function(event)
      rainbow_attached_buffers[event.buf] = nil
    end,
  })

  local installed_parsers = treesitter.get_installed('parsers')
  local missing_parsers = vim.tbl_filter(function(language)
    return not vim.list_contains(installed_parsers, language)
  end, required_parsers)
  if #missing_parsers == 0 then
    return
  end

  local installation_task = treesitter.install(missing_parsers)
  installation_task:await(function(install_error, installation_succeeded)
    vim.schedule(function()
      if install_error then
        vim.notify(
          'Treesitter parser installation failed: ' .. tostring(install_error),
          vim.log.levels.ERROR
        )
        return
      end
      if not installation_succeeded then
        vim.notify('Treesitter parser installation failed', vim.log.levels.ERROR)
      end
      start_loaded_buffers(missing_parsers)
    end)
  end)
end

return M
