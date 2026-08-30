-- Diagnostic audit: file-level index over Neovim's diagnostic cache.
local diagnostic_audit = require('config.audit.diagnostic')
diagnostic_audit.setup()

local diagnostic_root = vim.fn.tempname()
vim.fn.mkdir(diagnostic_root, 'p')

local function named_scratch_buffer(path, lines)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local alpha_buffer = named_scratch_buffer(diagnostic_root .. '/alpha.py', { 'x = 1', 'y = 2' })
local beta_buffer = named_scratch_buffer(diagnostic_root .. '/beta.py', { 'z = 3' })

local audit_namespace = vim.api.nvim_create_namespace('audit_test')
vim.diagnostic.set(audit_namespace, alpha_buffer, {
  {
    lnum = 1,
    col = 2,
    severity = vim.diagnostic.severity.WARN,
    message = 'second line warning',
  },
  {
    lnum = 0,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    message = 'first line error',
  },
  {
    lnum = 0,
    col = 4,
    severity = vim.diagnostic.severity.HINT,
    message = 'hint below the severity filter',
  },
})
vim.diagnostic.set(audit_namespace, beta_buffer, {
  {
    lnum = 0,
    col = 1,
    severity = vim.diagnostic.severity.WARN,
    message = 'beta warning',
  },
})

local files = diagnostic_audit.get_files(diagnostic_root)
assert(#files == 2, 'Diagnostic audit did not index both files')
assert(files[1].relative_path == 'alpha.py', 'Diagnostic audit did not sort by relative path')
assert(files[1].errors == 1, 'Diagnostic audit counted the wrong number of errors')
assert(files[1].warnings == 1, 'Diagnostic audit counted the wrong number of warnings')
assert(
  files[1].first_diagnostic.lnum == 0 and files[1].first_diagnostic.col == 0,
  'Diagnostic audit did not pick the earliest, most severe diagnostic first'
)
assert(files[2].relative_path == 'beta.py', 'Diagnostic audit lost the second file')

vim.diagnostic.reset(audit_namespace, beta_buffer)
files = diagnostic_audit.get_files(diagnostic_root)
assert(#files == 1, 'Cleared diagnostics stayed in the audit index')
assert(files[1].relative_path == 'alpha.py', 'The wrong file survived the diagnostic reset')

vim.api.nvim_buf_delete(alpha_buffer, { force = true })
files = diagnostic_audit.get_files(diagnostic_root)
assert(#files == 0, 'Deleted buffers stayed in the audit index')

-- Project audit: dirty-path state machine behind Overseer task coordination.
local replaced_modules = {
  'config.audit.project',
  'config.project',
  'config.python.environment',
  'overseer',
}
local original_modules = {}
for _, module_name in ipairs(replaced_modules) do
  original_modules[module_name] = package.loaded[module_name]
end

local audit_root = vim.fn.tempname()
vim.fn.mkdir(audit_root, 'p')

package.loaded['config.project'] = {
  contains = function(root, path)
    return vim.fs.normalize(path):sub(1, #root + 1) == root .. '/'
  end,
  for_buffer = function()
    return audit_root
  end,
  is_python = function()
    return true
  end,
}
package.loaded['config.python.environment'] = {
  resolve = function()
    return nil
  end,
}

local fake_bin = vim.fn.tempname()
vim.fn.mkdir(fake_bin, 'p')
local analyzer_path = fake_bin .. '/basedpyright'
vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, analyzer_path)
vim.fn.setfperm(analyzer_path, 'rwxr-xr-x')
local original_path = vim.env.PATH
vim.env.PATH = fake_bin .. ':' .. original_path

local notifications = {}
local original_notify = vim.notify
rawset(vim, 'notify', function(message, _level)
  table.insert(notifications, message)
end)

local tasks = {}
local function complete_task(task, report_valid)
  task.running = false
  for _, subscriber in ipairs(task.subscribers) do
    subscriber(task, nil, report_valid and { project_audit_report_valid = true } or nil)
  end
end

package.loaded['overseer'] = {
  list_tasks = function()
    return tasks
  end,
  new_task = function(spec)
    local task = {
      name = spec.name,
      cmd = spec.cmd,
      cwd = spec.cwd,
      metadata = spec.metadata,
      subscribers = {},
      running = false,
      output_buffer = vim.api.nvim_create_buf(false, true),
    }
    function task:subscribe(_event, callback)
      table.insert(self.subscribers, callback)
    end
    function task:start()
      self.running = true
    end
    function task:restart()
      self.running = true
    end
    function task:is_running()
      return self.running
    end
    function task:get_bufnr()
      return self.output_buffer
    end
    table.insert(tasks, task)
    return task
  end,
}

local audit = require('config.audit.project')

audit.run_or_open()
assert(#tasks == 1, 'First audit did not create an Overseer task')
assert(tasks[1].metadata.project_audit_mode == 'full', 'First audit was not a full scan')
assert(tasks[1].running, 'First audit task was not started')

complete_task(tasks[1], true)

local function record_write(relative_path)
  local write_buffer = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(write_buffer, audit_root .. '/' .. relative_path)
  vim.api.nvim_exec_autocmds('BufWritePost', { buffer = write_buffer })
  vim.api.nvim_buf_delete(write_buffer, { force = true })
end

record_write('alpha.py')
audit.run_or_open()
assert(#tasks == 1, 'Incremental audit created a duplicate task')
assert(tasks[1].running, 'Incremental audit did not restart the task')
assert(
  tasks[1].metadata.project_audit_mode == 'incremental',
  'A written Python file did not trigger an incremental scan'
)
assert(
  #tasks[1].metadata.project_audit_targets == 1
    and tasks[1].metadata.project_audit_targets[1]:find('alpha.py', 1, true),
  'Incremental audit did not target the written file'
)

complete_task(tasks[1], true)

notifications = {}
audit.run_or_open()
assert(
  notifications[#notifications] == 'Project audit: <Space>gs already completed; no relevant files were written',
  'Clean re-run did not report the completed audit'
)

record_write('pyproject.toml')
audit.run_or_open()
assert(
  tasks[1].metadata.project_audit_mode == 'full',
  'A Python config write did not force a full scan'
)
assert(
  #tasks[1].metadata.project_audit_targets == 0,
  'A full scan carried incremental targets'
)

vim.env.PATH = original_path
rawset(vim, 'notify', original_notify)
pcall(vim.api.nvim_del_augroup_by_name, 'project_audit_writes')
for _, module_name in ipairs(replaced_modules) do
  package.loaded[module_name] = original_modules[module_name]
end
