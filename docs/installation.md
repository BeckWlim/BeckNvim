# Installation

For clone and setup commands, see the [quick start](../README.md#installation).

## Dependencies and setup options

Setup installs missing core external tools and checks whether Node.js/npm and Python are available.
Setup installs SQLite 3 for persistent preferences. If its shared library is unavailable, Neovim
continues with memory-only preferences and warns once; those changes disappear on exit. Existing
saved files remain untouched. Temporary UI settings always stay in the current process's memory.
It does not install runtime managers or language runtimes. Setup installs Tree-sitter CLI through
npm into `~/.local/bin` when npm is available. If npm is missing or unusable, setup skips CLI
installation; if npm installation fails, setup warns and continues. Follow any PATH instructions
it prints and reopen your terminal before starting Neovim.

`--skip-system` disables core operating-system package installation. `--skip-clipboard` skips
installation and checks for X11 and Wayland clipboard providers. On Linux, setup checks `wl-copy`
for Wayland or `xclip` for X11; SSH sessions without a local display use OSC 52 clipboard integration.
Run `./setup.sh --help` for setup options.

## Dependency checks

Run `./setup.sh --check` to validate dependencies without changing the system. It checks core tools,
compiler availability, Neovim, Tree-sitter CLI, and the applicable clipboard provider. Once core
checks pass, it checks optional runtimes: Node.js 22 or newer with npm, and Python 3.10 or newer with
`venv` and `ensurepip`.

Missing or incompatible dependencies produce a nonzero exit status, including missing Node.js/npm
or Python. Normal setup continues after warning about missing optional runtimes so core Neovim can
be installed. Install suitable runtimes yourself when the corresponding feature is needed, follow
any reported PATH instructions, and rerun the check.

## First launch and language tooling

On first launch, lazy.nvim installs missing plugins and builds Termaid for Mermaid diagrams when
uv or a compatible Python is available. Tree-sitter parser installation is opt-in; use
`:TSInstall python` or another language after installing a compatible Tree-sitter CLI.

Startup requests no LSP installation. Choose every language server explicitly in `:Mason`:
press `i` to install, `X` to uninstall, and `?` for help. Restart Neovim after removing a server to
stop any existing client. Startup enables installed servers and does not download or restore removed
servers.

Neovim still opens and edits files without the optional runtimes. Install the Shell and Vim servers
through `:Mason` after installing Node.js/npm; running them only requires Node.js. Python hierarchy
indexing needs system Python or a project virtual environment. Mason's basedpyright installation
requires Python, while native C/C++, Lua, and Markdown servers do not require Node.js/npm.
After installing missing runtimes, restart Neovim.

## Markdown and Mermaid

Markdown preview features are provided by the
[BeckWlim renderer fork](https://github.com/BeckWlim/render-markdown.nvim).
Termaid is optional and activates automatically when available. Its build uses uv when available,
or Python's `venv` and `pip` otherwise. Without a usable Termaid build, Markdown shows the original
Mermaid source. After installing missing runtimes, use `:Lazy build termaid` to retry its build.

## Local plugin checkouts

To load plugins from local checkouts, configure
[development mode](development.md#local-plugin-development) in `~/.nvim`.
