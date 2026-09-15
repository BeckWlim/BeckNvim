return {
  {
    'BeckWlim/termaid',
    branch = 'main',
    version = false,
    lazy = true,
    -- lazy.nvim runs shell builds asynchronously in the checked-out directory.
    build = 'uv venv --allow-existing --python python3 --no-python-downloads .venv'
      .. ' && uv pip install --python .venv/bin/python --reinstall .',
  },
}
