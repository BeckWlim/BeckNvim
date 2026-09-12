# BeckNvim

BeckNvim is a project-oriented Neovim configuration focused on navigation, semantic search, Git
inspection, language tooling, and readable code review. Its features share a consistent visual
system while keeping native Neovim and plugin behavior wherever practical.

## Highlights

- Project dashboard, recent-project state, file browsing, and project-root synchronization.
- Fast file, text, symbol, definition, reference, and type-hierarchy search.
- Unified file, symbol, repository, branch, commit, issue, and pull-request inspection.
- Diffview-based history review with bounded asynchronous loading and safe state transitions.
- LSP completion, diagnostics, type information, and language-aware navigation.
- Tree-sitter highlighting, folding, syntax context, scope visualization, and structural selection.
- Readable Markdown rendering with responsive tables and stable native editing behavior.
- Integrated terminal, translation, proxy management, and project diagnostics.

## Main Modules

| Module | Main responsibility |
| --- | --- |
| `config/startup/` | Editor options, autocmds, keymap assembly, and plugin bootstrap |
| `config/project.lua` | Project-root discovery, activation, containment, and cached project state |
| `config/ui/` | Dashboard, file tree, statusline, terminal, shared floats, and window state |
| `config/search/` | Telescope configuration, project search, previews, and LSP location results |
| `config/git/` | Git history workflows, Diffview lifecycle, repository data, and GitHub details |
| `config/lsp/` | Language-server setup, completion, diagnostics, and type-information views |
| `config/syntax/` | Tree-sitter setup, Markdown rendering, folds, highlights, and syntax context |
| `config/type_hierarchy/` | Recursive class hierarchy and implementation discovery |
| `config/python/` | Python environment resolution and hierarchy indexing |
| `config/network/` | Proxy discovery, persistent session state, and proxy selection UI |
| `config/translation/` | Translation interface, provider construction, and response parsing |
| `config/audit/` | Project-wide diagnostic collection and audit coordination |
| `plugins/` | Plugin declarations, dependencies, loading conditions, and setup |

The complete ownership and lifecycle model is documented in
[Architecture](docs/architecture.md).

## Installation

Requirements:

- Neovim 0.11 or newer
- Git, ripgrep, Python 3.10+, curl, wget, and unzip
- Node.js, npm, and the tree-sitter CLI
- make, a C compiler, CMake, and Ninja
- A Nerd Font
- `xclip` on X11 or `wl-clipboard` on Wayland for system clipboard integration

```bash
mv ~/.config/nvim ~/.config/nvim.bak
git clone https://github.com/BeckWlim/BeckNvim.git ~/.config/nvim
nvim
```

On first launch, lazy.nvim restores pinned plugins and Mason installs the configured language
servers. Plugin versions remain pinned by `lazy-lock.json` until explicitly updated.

## Documentation

- [Default keybindings](docs/keybindings.md)
- [Git mode](docs/git-mode.md)
- [Architecture](docs/architecture.md)
- [Development and validation](docs/development.md)

## License

Licensed under the [MIT License](LICENSE).
