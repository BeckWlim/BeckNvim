local use_uv = vim.fn.executable('uv') == 1
local build_command = use_uv
    and ('uv venv --allow-existing .venv'
      .. ' && uv pip install --python .venv/bin/python --reinstall -e .')
  or ('"$termaid_python" -m venv .venv'
    .. ' && .venv/bin/python -m pip install --force-reinstall -e .')

return {
  {
    'BeckWlim/termaid',
    branch = 'main',
    version = false,
    lazy = true,
    -- Keep the Python package linked to the checkout selected by lazy.nvim.
    -- Probe inside lazy.nvim's build job, never block editor startup on Python.
    build = use_uv and build_command
      or ('for termaid_python in python python3; do if "$termaid_python" -c ' .. vim.fn.shellescape(
        'import sys, venv, ensurepip; sys.exit(sys.version_info < (3, 10))'
      ) .. ' >/dev/null 2>&1; then ' .. build_command
        .. "; exit $?; fi; done; printf '%s\\n' 'Termaid build skipped: Python 3.10+ with venv and ensurepip"
        .. " is unavailable. Install it, then run :Lazy build termaid.'"),
  },
}
