# Development

## Versions

`v0.1.0` is the initial release baseline. During `0.x` development, use patch releases (`v0.1.x`)
for compatible fixes and minor releases (`v0.x.0`) for features or incompatible changes. Describe
incompatible changes in the release notes. Each release uses an annotated Git tag and matching
GitHub release notes.

The README installation selects the tagged release. For development, use `git switch master`
from a clean checkout.

## Validation

Keep behavior in its owning module and preserve native plugin renderers. Update focused tests and
documentation with user-visible behavior.

Focused tests mirror production ownership under `tests/<subsystem>/`; tests for a nested feature
use the same nesting, such as `config.syntax.markdown` under `tests/syntax/markdown/`.

```bash
bash -n setup.sh
bash -n tests/setup.sh
bash -n tests/setup_runtime.sh
bash tests/setup.sh
XDG_CACHE_HOME=/tmp/nvim-test-cache XDG_STATE_HOME=/tmp/nvim-test-state \
  nvim --headless -u NONE -i NONE -l tests/run.lua
git diff --check
XDG_CACHE_HOME=/tmp/nvim-test-cache XDG_STATE_HOME=/tmp/nvim-test-state \
  nvim --headless -u init.lua -i NONE '+qa'
```

The test runner includes the binding audit. Exercise Diffview lifecycle changes against a disposable
or read-only Git repository.

With plugins, Markdown parsers, and Termaid installed, verify Markdown modes, screen colors, source
navigation, and input responsiveness during multiple diagram completions and resizing in an embedded
Neovim UI. The check retains normal prompt behavior so blocking errors remain visible:

```bash
nvim --headless -u NONE -i NONE -l tests/syntax/markdown/installed.lua
```
