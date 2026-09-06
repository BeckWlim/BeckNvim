# BeckNvim

BeckNvim is a focused Neovim configuration for project navigation, semantic search, Git history,
and readable code review. It keeps editor, Telescope, Diffview, Markdown, and syntax-context UI in
one restrained visual system while preserving native plugin behavior wherever possible.

## Highlights

- Project dashboard with recent projects, files, and a shared directory picker.
- Fast file, text, symbol, definition, reference, and type-hierarchy workflows.
- Tree-sitter highlighting, folding, breadcrumbs, and pinned class/function context.
- Unified Git inspection for file, symbol, and repository history plus branch/commit/issue search.
- Diffview-owned commit expansion, collapse, file selection, and native footer presentation.
- Width-aware Markdown, diagnostics, completion, terminals, translation, and proxy tools.
- Asynchronous Git and network work with cancellation, bounded queues, and clean return paths.

## Installation

### Requirements

- Neovim 0.11 or newer
- Git, ripgrep, Python 3.10+, curl, wget, and unzip
- make and a C compiler
- Node.js, npm, and the tree-sitter CLI
- CMake and Ninja for C/C++ build workflows
- A Nerd Font

For local system clipboard integration, install the provider that matches your display server:

- X11: `xclip`
- Wayland: `wl-clipboard`, which provides the `wl-copy` and `wl-paste` commands

### Install

```bash
mv ~/.config/nvim ~/.config/nvim.bak
git clone https://github.com/BeckWlim/BeckNvim.git ~/.config/nvim
nvim
```

On first launch, lazy.nvim restores pinned plugins and Mason installs configured language servers.
Mason manages language servers for Bash, C/C++, Lua, Markdown, Python, and Vim script. Required
Python and C++ Tree-sitter parsers install when the CLI and compiler are available. Normal
installation honors `lazy-lock.json`; plugin updates are a separate maintenance action. Run
`:checkhealth`, `:Lazy check`, and `:Mason` if a capability is unavailable.

Open the project dashboard with `<Space>h`. The leader policy and complete defaults live in
[Default keybindings](docs/keybindings.md).

## Main Modules

```text
init.lua
lua/config/
├── startup/       bootstrap and startup policy
├── search/        Telescope lifecycle, previews, and project search
├── git/           repository boundary, search, Diffview, and panel lifecycle
├── syntax/        Tree-sitter context, highlights, and visual policy
├── lsp/           language navigation and type information
├── ui/            dashboard, statusline, floats, and shared presentation
├── network/       proxy discovery and session state
└── translation/   translation workflow
```

## Documentation

- [Default keybindings](docs/keybindings.md)
- [Git mode](docs/git-mode.md)
- [Architecture](docs/architecture.md)
- [Development and validation](docs/development.md)

## License

Licensed under the [MIT License](LICENSE).
