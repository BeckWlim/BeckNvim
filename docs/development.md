# Development

Keep behavior in its owning module and preserve native plugin renderers. Update focused tests and
documentation with user-visible behavior.

```bash
XDG_CACHE_HOME=/tmp/nvim-test-cache XDG_STATE_HOME=/tmp/nvim-test-state \
  nvim --headless -u NONE -i NONE -l tests/run.lua
git diff --check
XDG_CACHE_HOME=/tmp/nvim-test-cache XDG_STATE_HOME=/tmp/nvim-test-state \
  nvim --headless -u init.lua -i NONE '+qa'
```

The test runner includes the binding audit. Exercise Diffview lifecycle changes against a disposable
or read-only Git repository.
