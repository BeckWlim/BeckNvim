-- Run the actual build commands with isolated runtime fixtures and no downloads.
local fixture_directory = vim.fn.tempname() .. ' termaid build'
local fixture_bin = fixture_directory .. '/bin'
local trace_path = fixture_directory .. '/trace'
vim.fn.mkdir(fixture_bin, 'p')
vim.fn.mkdir(fixture_directory .. '/.venv/bin', 'p')

for _, executable_path in ipairs({
  fixture_bin .. '/uv',
  fixture_bin .. '/python3',
  fixture_directory .. '/.venv/bin/python',
}) do
  vim.fn.writefile({
    '#!/bin/sh',
    'printf "%s %s\\n" "${0##*/}" "$*" >> "$TERMAID_TEST_TRACE"',
    'case "$*" in',
    '  "-c "*) exit "${TERMAID_TEST_PROBE_STATUS:-0}" ;;',
    '  "venv "*|"-m venv "*) exit "${TERMAID_TEST_VENV_STATUS:-0}" ;;',
    '  *) exit "${TERMAID_TEST_PIP_STATUS:-0}" ;;',
    'esac',
  }, executable_path)
  vim.fn.setfperm(executable_path, 'rwx------')
end

local function check_build(uv_available, venv_status, pip_status, probe_status)
  local spec_chunk = assert(loadfile('lua/plugins/termaid.lua'))
  setfenv(spec_chunk, {
    vim = {
      fn = {
        shellescape = vim.fn.shellescape,
        executable = function(command)
          assert(command == 'uv', 'Unexpected build runtime probe')
          return uv_available and 1 or 0
        end,
      },
    },
  })
  local spec = spec_chunk()[1]
  vim.fn.writefile({}, trace_path)
  local result = vim.system({ '/bin/sh', '-c', spec.build }, {
    cwd = fixture_directory,
    env = {
      PATH = fixture_bin,
      TERMAID_TEST_TRACE = trace_path,
      TERMAID_TEST_VENV_STATUS = tostring(venv_status),
      TERMAID_TEST_PIP_STATUS = tostring(pip_status),
      TERMAID_TEST_PROBE_STATUS = tostring(probe_status or 0),
    },
    text = true,
  }):wait()
  local expected_commands = uv_available and {
    'uv venv --allow-existing .venv',
    'uv pip install --python .venv/bin/python --reinstall -e .',
  } or {
    'python3 -m venv .venv',
    'python -m pip install --force-reinstall -e .',
  }
  if venv_status ~= 0 then
    table.remove(expected_commands, 2)
  end
  if probe_status then
    expected_commands = {}
  end
  local traced_commands = vim.fn.readfile(trace_path)
  if not uv_available then
    assert(traced_commands[1]:find('python3 -c import sys', 1, true) == 1,
      'Termaid did not check Python before attempting its build')
    table.remove(traced_commands, 1)
  end
  assert(vim.deep_equal(traced_commands, expected_commands),
    'Termaid must build an editable package using only the selected runtime')
  local expected_status = probe_status and 0 or (venv_status ~= 0 and venv_status or pip_status)
  assert(result.code == expected_status, 'Termaid build lost the failing command status: ' .. result.stderr)
end

for _, uv_available in ipairs({ false, true }) do
  check_build(uv_available, 0, 0)
  check_build(uv_available, 7, 0)
  check_build(uv_available, 0, 9)
  if not uv_available then
    check_build(uv_available, 0, 0, 1)
    check_build(uv_available, 0, 0, 127)
  end
end
vim.fn.delete(fixture_bin .. '/python3')
local missing_python_chunk = assert(loadfile('lua/plugins/termaid.lua'))
setfenv(missing_python_chunk, {
  vim = {
    fn = {
      executable = function() return 0 end,
      shellescape = vim.fn.shellescape,
    },
  },
})
local missing_python_spec = missing_python_chunk()[1]
local missing_python_result = vim.system({ '/bin/sh', '-c', missing_python_spec.build }, {
  cwd = fixture_directory,
  env = { PATH = fixture_bin },
  text = true,
}):wait()
assert(missing_python_result.code == 0 and missing_python_result.stdout:find('Termaid build skipped', 1, true),
  'An absent Python executable must skip the optional build successfully')
local uv_only_spec_chunk = assert(loadfile('lua/plugins/termaid.lua'))
setfenv(uv_only_spec_chunk, {
  vim = { fn = { executable = function(command) return command == 'uv' and 1 or 0 end } },
})
local uv_only_result = vim.system({ '/bin/sh', '-c', uv_only_spec_chunk()[1].build }, {
  cwd = fixture_directory,
  env = { PATH = fixture_bin, TERMAID_TEST_VENV_STATUS = '0', TERMAID_TEST_PIP_STATUS = '0' },
  text = true,
}):wait()
assert(uv_only_result.code == 0, 'uv should activate Termaid without a system Python probe')
vim.fn.delete(fixture_directory, 'rf')
