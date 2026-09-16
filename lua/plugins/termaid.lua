return {
  {
    'BeckWlim/termaid',
    branch = 'main',
    version = false,
    lazy = true,
    -- Keep the Python package linked to the checkout selected by lazy.nvim.
    build = 'uv venv --allow-existing --python python3 --no-python-downloads .venv'
      .. ' && uv pip install --python .venv/bin/python --reinstall -e .',
  },
}
