local highlight_namespace = vim.api.nvim_create_namespace('project_audit_output')

local function set_buffer_lines(task, lines, status_highlight)
  local bufnr = task:get_bufnr()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false

  vim.api.nvim_buf_clear_namespace(bufnr, highlight_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, highlight_namespace, 'Title', 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, highlight_namespace, status_highlight, 3, 11, -1)
end

local function elapsed_seconds(started_at)
  if not started_at then
    return 0
  end
  return (vim.uv.hrtime() - started_at) / 1e9
end

local function render_running(self, task)
  local command = type(task.cmd) == 'table' and task.cmd[1] or task.cmd
  local scan_mode = task.metadata.project_audit_mode == 'incremental' and 'Incremental' or 'Full project'
  set_buffer_lines(task, {
    'Project Diagnostic Audit',
    string.rep('─', 32),
    '',
    'Status     RUNNING',
    'Analyzer   ' .. vim.fs.basename(command or 'basedpyright'),
    'Python     ' .. tostring(task.metadata.project_audit_python or 'analyzer default'),
    'Project    ' .. task.cwd,
    'Scope      ' .. scan_mode,
    ('Elapsed    %.0fs'):format(elapsed_seconds(self.started_at)),
    '',
    'basedpyright reports results when analysis completes.',
    'Press q or <Esc> to close; the task continues in background.',
  }, 'DiagnosticInfo')
end

local function stop_timer(self)
  if self.timer and not self.timer:is_closing() then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = nil
end

local function diagnostic_counts(report, diagnostics)
  local summary = type(report.summary) == 'table' and report.summary or {}
  local errors = type(summary.errorCount) == 'number' and summary.errorCount or 0
  local warnings = type(summary.warningCount) == 'number' and summary.warningCount or 0
  if errors == 0 and warnings == 0 then
    for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.type == 'E' then
        errors = errors + 1
      elseif diagnostic.type == 'W' then
        warnings = warnings + 1
      end
    end
  end
  return errors, warnings, summary
end

local function render_completed(task, report, diagnostics)
  local errors, warnings, summary = diagnostic_counts(report, diagnostics)
  local status = errors > 0 and 'COMPLETED WITH ERRORS'
    or warnings > 0 and 'COMPLETED WITH WARNINGS'
    or 'CLEAN'
  local status_highlight = errors > 0 and 'DiagnosticError'
    or warnings > 0 and 'DiagnosticWarn'
    or 'DiagnosticOk'
  local analysis_time = type(summary.timeInSec) == 'number'
      and ('%.2fs'):format(summary.timeInSec)
    or 'completed'
  local target_count = #(task.metadata.project_audit_targets or {})
  local scope = task.metadata.project_audit_mode == 'incremental'
      and ('Incremental (%d saved file(s))'):format(target_count)
    or 'Full project'

  set_buffer_lines(task, {
    'Project Diagnostic Audit',
    string.rep('─', 32),
    '',
    'Status     ' .. status,
    'Analyzer   basedpyright ' .. tostring(report.version or ''),
    'Python     ' .. tostring(task.metadata.project_audit_python or 'analyzer default'),
    'Project    ' .. task.cwd,
    'Scope      ' .. scope,
    'Duration   ' .. analysis_time,
    'Files      ' .. tostring(summary.filesAnalyzed or '—'),
    ('Findings   %d error(s), %d warning(s)'):format(errors, warnings),
    '',
    'Diagnostics are cached for this Neovim session.',
    '<Space>gq  Open affected files',
    '<Space>gs  Scan saved changes, or show this result',
    'q / <Esc>  Close this window',
  }, status_highlight)
end

local function reset_diagnostic_buffer(self, bufnr)
  vim.diagnostic.reset(self.diagnostic_namespace, bufnr)
  self.diagnostic_bufnrs[bufnr] = nil
end

local function apply_diagnostics(self, task, report)
  if task.metadata.project_audit_mode ~= 'incremental' then
    for bufnr in pairs(self.diagnostic_bufnrs) do
      reset_diagnostic_buffer(self, bufnr)
    end
  else
    for _, path in ipairs(task.metadata.project_audit_targets or {}) do
      reset_diagnostic_buffer(self, vim.fn.bufadd(path))
    end
  end

  local diagnostics_by_path = {}
  local quickfix_diagnostics = {}
  for _, item in ipairs(report.generalDiagnostics) do
    if item.severity == 'error' or item.severity == 'warning' then
      local range = item.range or {}
      local range_start = range.start or {}
      local range_end = range['end'] or range_start
      local base_message = item.message or ''
      local diagnostic_message = item.rule
          and ('%s [%s]'):format(base_message, item.rule)
        or base_message

      local path = vim.fs.normalize(item.file)
      diagnostics_by_path[path] = diagnostics_by_path[path] or {}
      diagnostics_by_path[path][#diagnostics_by_path[path] + 1] = {
        lnum = range_start.line or 0,
        col = range_start.character or 0,
        end_lnum = range_end.line or range_start.line or 0,
        end_col = range_end.character or range_start.character or 0,
        severity = item.severity == 'error'
            and vim.diagnostic.severity.ERROR
          or vim.diagnostic.severity.WARN,
        message = diagnostic_message,
        source = 'basedpyright',
        code = item.rule,
      }
      quickfix_diagnostics[#quickfix_diagnostics + 1] = {
        filename = path,
        lnum = (range_start.line or 0) + 1,
        col = range_start.character or 0,
        text = diagnostic_message,
        type = item.severity == 'error' and 'E' or 'W',
      }
    end
  end

  for path, diagnostics in pairs(diagnostics_by_path) do
    local bufnr = vim.fn.bufadd(path)
    -- Dependencies can appear in an incremental report even when they were not
    -- explicit targets. Replace their cached result atomically as well.
    reset_diagnostic_buffer(self, bufnr)
    vim.diagnostic.set(self.diagnostic_namespace, bufnr, diagnostics)
    self.diagnostic_bufnrs[bufnr] = true
  end
  return quickfix_diagnostics
end

local function render_parse_failure(task)
  set_buffer_lines(task, {
    'Project Diagnostic Audit',
    string.rep('─', 32),
    '',
    'Status     OUTPUT PARSE FAILED',
    'Project    ' .. task.cwd,
    '',
    'basedpyright did not return a valid JSON report.',
    'Use :OverseerToggle to inspect the task status.',
    'q / <Esc>  Close this window',
  }, 'DiagnosticError')
end

return {
  desc = 'Parse basedpyright JSON output into task diagnostics',
  constructor = function()
    return {
      output = {},
      timer = nil,
      started_at = nil,
      diagnostic_namespace = nil,
      diagnostic_bufnrs = {},
      on_init = function(self, task)
        self.diagnostic_namespace = vim.api.nvim_create_namespace(
          'project-audit-basedpyright:' .. vim.fn.sha256(task.cwd):sub(1, 16)
        )
      end,
      on_start = function(self, task)
        self.started_at = vim.uv.hrtime()
        render_running(self, task)
        self.timer = vim.uv.new_timer()
        if self.timer then
          self.timer:start(1000, 1000, vim.schedule_wrap(function()
            if task:is_running() then
              render_running(self, task)
            else
              stop_timer(self)
            end
          end))
        end
      end,
      on_reset = function(self)
        stop_timer(self)
        self.output = {}
        self.started_at = nil
      end,
      on_output = function(self, task)
        -- The process buffer receives stdout before components do. Replace it
        -- in the same event-loop callback so raw JSON is never presented as UI.
        render_running(self, task)
      end,
      on_output_lines = function(self, _, lines)
        vim.list_extend(self.output, lines)
      end,
      on_pre_result = function(self, task)
        stop_timer(self)
        local output = table.concat(self.output, '\n')
        local json_start = output:find('{', 1, true)
        local json_end = output:match('.*()}')
        if not json_start or not json_end then
          render_parse_failure(task)
          return { diagnostics = {} }
        end

        local ok, report = pcall(vim.json.decode, output:sub(json_start, json_end))
        if not ok or type(report) ~= 'table' or type(report.generalDiagnostics) ~= 'table' then
          render_parse_failure(task)
          return { diagnostics = {} }
        end

        local diagnostics = apply_diagnostics(self, task, report)

        render_completed(task, report, diagnostics)
        return {
          diagnostics = diagnostics,
          project_audit_report_valid = true,
        }
      end,
      on_dispose = function(self)
        stop_timer(self)
        for bufnr in pairs(self.diagnostic_bufnrs) do
          reset_diagnostic_buffer(self, bufnr)
        end
      end,
    }
  end,
}
