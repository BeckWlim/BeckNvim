local M = {}
local project = require('config.project')

local severity_filter = { min = vim.diagnostic.severity.WARN }
local files_by_path = {}
local paths_by_bufnr = {}
local setup_done = false

local function diagnostic_precedes(left, right)
  return left.severity < right.severity
    or (left.severity == right.severity and left.lnum < right.lnum)
    or (left.severity == right.severity and left.lnum == right.lnum and left.col < right.col)
end

-- DiagnosticChanged is the cache invalidation mechanism. The index stores only
-- file-level counts; Neovim remains the source of truth for actual diagnostics.
local function update_buffer(bufnr)
  local old_path = paths_by_bufnr[bufnr]
  local buffer_path = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ''
  local normalized_path = buffer_path ~= '' and vim.fs.normalize(buffer_path) or ''

  if old_path and old_path ~= normalized_path then
    files_by_path[old_path] = nil
    paths_by_bufnr[bufnr] = nil
  end
  if buffer_path == '' then
    return
  end

  paths_by_bufnr[bufnr] = normalized_path
  local diagnostics = vim.diagnostic.get(bufnr, { severity = severity_filter })
  if #diagnostics == 0 then
    files_by_path[normalized_path] = nil
    return
  end

  local file = {
    path = normalized_path,
    errors = 0,
    warnings = 0,
    first_diagnostic = diagnostics[1],
  }
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.severity == vim.diagnostic.severity.ERROR then
      file.errors = file.errors + 1
    elseif diagnostic.severity == vim.diagnostic.severity.WARN then
      file.warnings = file.warnings + 1
    end
    if diagnostic_precedes(diagnostic, file.first_diagnostic) then
      file.first_diagnostic = diagnostic
    end
  end
  files_by_path[normalized_path] = file
end

local function refresh_index()
  -- Diagnostics may be written to an unlisted, unloaded buffer by a batch
  -- analyzer. DiagnosticChanged is not guaranteed to refresh our secondary
  -- file index for that case, so reconcile it with Neovim's source of truth
  -- whenever the picker is requested.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    update_buffer(bufnr)
  end
end

function M.get_files(root)
  refresh_index()
  local selected_root = root or project.for_buffer(0)
  local normalized_root = vim.fs.normalize(selected_root)
  local files = {}
  for path, cached in pairs(files_by_path) do
    if project.contains(normalized_root, path) then
      files[#files + 1] = {
        path = path,
        relative_path = vim.fs.relpath(normalized_root, path) or path,
        errors = cached.errors,
        warnings = cached.warnings,
        first_diagnostic = cached.first_diagnostic,
      }
    end
  end
  table.sort(files, function(left, right)
    return left.relative_path < right.relative_path
  end)
  return files
end

function M.open()
  local root = project.for_buffer(0)
  local files = M.get_files(root)
  if #files == 0 then
    local message = vim.uv.fs_stat(vim.fs.joinpath(root, 'CMakeLists.txt'))
        and 'Project audit: no cached errors or warnings; C/C++ diagnostics are limited to files opened in clangd'
      or 'Project audit: no errors or warnings in the current diagnostic cache; run <Space>gs to scan the project'
    vim.notify(
      message,
      vim.log.levels.INFO
    )
    return
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local entry_display = require('telescope.pickers.entry_display')
  local conf = require('telescope.config').values
  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 6 },
      { width = 6 },
      { remaining = true },
    },
  })
  local opts = { cwd = root }

  pickers.new(opts, {
    prompt_title = 'Project files with errors or warnings',
    finder = finders.new_table({
      results = files,
      entry_maker = function(file)
        local first = file.first_diagnostic
        return {
          value = file,
          filename = file.path,
          lnum = first.lnum + 1,
          col = first.col + 1,
          ordinal = file.relative_path,
          display = function(entry)
            return displayer({
              { ('E:%d'):format(entry.value.errors), 'DiagnosticError' },
              { ('W:%d'):format(entry.value.warnings), 'DiagnosticWarn' },
              entry.value.relative_path,
            })
          end,
        }
      end,
    }),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end

        actions.close(prompt_bufnr)
        vim.cmd.edit(vim.fn.fnameescape(selection.filename))
        local line_count = vim.api.nvim_buf_line_count(0)
        local lnum = math.min(selection.lnum, line_count)
        local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ''
        local col = math.min(selection.col - 1, #line)
        vim.api.nvim_win_set_cursor(0, { lnum, col })
        vim.cmd.normal({ args = { 'zz' }, bang = true })
      end)
      return true
    end,
  }):find()
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    update_buffer(bufnr)
  end

  local group = vim.api.nvim_create_augroup('project_diagnostic_audit', { clear = true })
  vim.api.nvim_create_autocmd('DiagnosticChanged', {
    group = group,
    callback = function(event)
      update_buffer(event.buf)
    end,
    desc = 'Update the file-level project diagnostic index',
  })
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    callback = function(event)
      local path = paths_by_bufnr[event.buf]
      if path then
        files_by_path[path] = nil
        paths_by_bufnr[event.buf] = nil
      end
    end,
    desc = 'Remove deleted buffers from the project diagnostic index',
  })
end

return M
