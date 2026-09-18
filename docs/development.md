# Development

## Versions

`v0.1.0` is the initial release baseline. During `0.x` development, use patch releases (`v0.1.x`)
for compatible fixes and minor releases (`v0.x.0`) for features or incompatible changes. Describe
incompatible changes in the release notes. Each release uses an annotated Git tag and matching
GitHub release notes.

The README installation follows the repository's default branch. Release tags remain available
for users who want a specific release.

## Local plugin development

Add development settings alongside your existing proxy lines in `~/.nvim`, then restart Neovim:

```bash
http_proxy=http://172.25.160.1:7890
https_proxy=http://172.25.160.1:7890
# NO_PROXY=localhost,127.0.0.1

NVIM_DEV=true
NVIM_DEV_PATH=~/.config
NVIM_DEV_PLUGINS=BeckWlim/termaid
```

This loads Termaid from `~/.config/termaid`. `NVIM_DEV_PATH` is the parent directory of your local
plugin checkouts and defaults to `~/.config`. `NVIM_DEV_PLUGINS` contains comma-separated literal
substrings of plugin repository URLs, such as `BeckWlim/termaid,folke/`; it defaults to an empty list.
Checkouts must use lazy.nvim's plugin names as directory names (for example, `termaid`).
These settings use [lazy.nvim's native development options](https://lazy.folke.io/configuration).

Development mode is disabled by default. Set `NVIM_DEV=false` to use managed plugin installs
again. Plugins that do not match remain managed by lazy.nvim. A missing selected checkout produces
a lazy.nvim error instead of silently using a remote copy. The setting is read at startup.
Blank lines, `#` comments, quoted values, and an optional `export` prefix are supported.
Assignments are read as data; shell commands and variable substitutions are not executed.
Existing JSON settings remain supported.

For the `BeckWlim/render-markdown.nvim` fork, enable development mode in `~/.nvim` and include
its repository in the selection:

```bash
NVIM_DEV=true
NVIM_DEV_PATH=~/.config
NVIM_DEV_PLUGINS=BeckWlim/termaid,BeckWlim/render-markdown.nvim
```

This loads the renderer from `~/.config/render-markdown.nvim`. The plugin declaration leaves
development mode unset so personal settings control it; without opt-in it uses a managed install.
Restart Neovim after editing the renderer. Preview, table, and Mermaid implementation and unit tests
live in the fork; BeckNvim retains configuration and editor-integration tests. In the renderer checkout,
run `nvim --headless -u NONE -i NONE -l tests/preview/run.lua` or run `just test`.

Termaid's build keeps its Python package editable in the selected checkout, using `uv` when
available or `python3 -m venv` and the environment's `pip` otherwise. After switching
checkouts, run `:Lazy build termaid` if that checkout does not yet have its `.venv` dependencies.

## Validation

Keep behavior in its owning module and preserve native plugin renderers. Update focused tests and
documentation with user-visible behavior.

Focused tests mirror production ownership under `tests/<subsystem>/`; tests for a nested feature
use the same nesting. Markdown engine unit tests live in the renderer fork;
`tests/syntax/markdown/` covers BeckNvim integration.

```bash
bash -n setup.sh
bash -n tests/setup.sh
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
nvim --headless -u NONE -i NONE -l tests/ui/theme_installed.lua
nvim --headless -u NONE -i NONE -l tests/ui/theme_preview_installed.lua
nvim --headless -u NONE -i NONE -l tests/ui/tmux_installed.lua
nvim --headless -u NONE -i NONE -l tests/ui/dashboard_installed.lua
nvim --headless -u NONE -i NONE -l tests/search/telescope_installed.lua
nvim --headless -u NONE -i NONE -l tests/syntax/visuals_installed.lua
nvim --headless -u NONE -i NONE -l tests/syntax/treesitter_installed.lua
```

Verify startup, ordinary file editing, and Markdown's Mermaid fallback with optional runtimes
removed from `PATH` (uses installed plugins and temporary editor data; performs no downloads):

```bash
nvim --headless -u NONE -i NONE -l tests/startup/optional_installed.lua
```
