# Neovim Configuration

A personal Neovim configuration for daily development. Plugin management uses
[lazy.nvim](https://github.com/folke/lazy.nvim), with completion, LSP, fuzzy search, Git tools,
terminals, a file tree, and Markdown rendering included.

## Requirements

- Neovim 0.11 or newer
- Git
- `curl` for the translation component
- [ripgrep](https://github.com/BurntSushi/ripgrep) for full-text and project-definition search
- `make` and a C compiler for `telescope-fzf-native.nvim`
- A Nerd Font for the complete icon set; the GUI defaults to Hack Nerd Font

Mason installs the configured language servers on demand. The current setup covers Bash,
C/C++, Lua, Markdown, Python, and Vim script.

## Installation

Back up the existing configuration, clone this repository, and start Neovim:

```bash
mv ~/.config/nvim ~/.config/nvim.bak
git clone <repository-url> ~/.config/nvim
nvim
```

Useful checks after the first startup:

```vim
:Lazy check
:Mason
:checkhealth
```

Plugin versions are pinned in `lazy-lock.json`. Include the updated lockfile when applying
`:Lazy update`.

## Repository Layout

```text
init.lua                         Startup entry point; calls config.setup()
lua/
├── config/                       Reusable, testable feature modules
│   ├── init.lua                  Configuration assembly order
│   ├── project.lua               Shared project-root and path boundary logic
│   ├── keybindings.lua           Global keymap assembly
│   ├── workspace_symbols.lua     Project-definition finder
│   ├── python/                   Python environment resolution
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Lightweight lazy.nvim plugin specifications
tests/                            Focused regression tests
lazy-lock.json                    Pinned plugin versions
```

See [Architecture](docs/architecture.md) for module ownership and extension rules.

## Keymaps

The default leader remains `\`. Every `<Space>` entry below uses the literal space key as its
prefix.

### Windows and Navigation

| Key | Action |
| --- | --- |
| `<Space>wi/wj/wk/wl` | Move to the upper/left/lower/right window |
| `<Space>wv/ws` | Create a vertical/horizontal split |
| `<Space>wq/wo` | Close the current window/keep only the current window |
| `<Tab>` / `<S-Tab>` | Move to the next/previous window |
| `<Space>ri/rk/rj/rl` | Increase/decrease height or width |
| `<Space>r=` | Equalize window sizes |
| `<Space>o` / `<Space>p` | Move backward/forward through the jump list |
| `<Space>zz/zc/zo` | Toggle, close all, or open all folds |

### Search

| Key | Action |
| --- | --- |
| `<Space>ff` | Find project files |
| `<Space>fv` | Find a file and open it in a vertical split |
| `<Space>fg` | Search project text |
| `<Space>fb` | Find an open buffer |
| `<Space>bv` | Find a buffer and open it in a vertical split |
| `<Space>fr` | Find recent files |
| `<Space>fh` | Search help tags |
| `<Space>fk` | Search keymaps |
| `<Space>fs` | Search symbols in the current file |
| `<Space>fw` | Search definitions across the project |

#### Project Definition Search

`<Space>fw` opens a dedicated Telescope definition picker with the following policy:

- Scope: Python, C/C++/CUDA, Lua, Shell, Vim script, and Markdown files under the project root.
- Backend: language-specific ripgrep jobs run in parallel and feed one Telescope finder.
- Query: two characters start a name-prefix search; longer input uses name containment.
- Capacity: each query supplies up to 1,000 candidates, and further input narrows the result set.
- Result row: definition name, symbol kind, and project-relative path.
- Preview: the source location appears in the Telescope preview window.
- State: each new query retires the previous finder generation and releases its search jobs.
- Readiness: initialization completes on Neovim's main loop; an early invocation reports the loading
  state and accepts a retry after startup settles.

This picker owns project-definition search. LSP navigation remains assigned to `gd`, `gD`, `gr`,
and `gI`.

Telescope results support `<C-v>` for a vertical split and `<C-x>` for a horizontal split.

### LSP and Diagnostics

| Key | Action |
| --- | --- |
| `gd` / `gD` | Go to a definition/declaration |
| `gr` / `gI` | Find references/go to an implementation |
| `K` | Show hover documentation |
| `<Space>i` | Go to an implementation |
| `<Space>D` | Go to a type definition |
| `<Space>rn` | Rename a symbol |
| `<Space>e` | Show diagnostic details |
| `[d` / `]d` | Move to the previous/next diagnostic |
| `<Space>q` | Open the diagnostic list |
| `<Space>lp` | Toggle BasedPyright third-party dependency diagnostics |

`<Space>gf`, `<Space>gv`, and `<Space>gx` open referenced C/C++ includes, Python imports, and Lua
modules in the current window, a vertical split, or a horizontal split.

### Tools

| Key | Action |
| --- | --- |
| `<F3>` | Toggle the file tree |
| `<C-t>` | Toggle the horizontal terminal |
| `<M-e>` | Apply a quick surround operation |
| `<Space>t` | Open the centered live Chinese/English translation query (700 ms debounce) |
| `<Space>mp` | Toggle Markdown rendering |
| `<Space>dv` | Open Diffview for the current branch |
| `<Space>dvm` | Compare the current branch with `main` |
| `<Space>dvh` | Show history for the current file |
| `<Space>dvc` | Close Diffview |
| `gcc` / `gc` | Comment the current line or selection |

## Customization

- Theme and completion colors: `lua/plugins/theme.lua`
- Indentation, clipboard, and display options: `lua/config/options.lua`
- LSP behavior: `lua/config/lsp.lua`
- Completion behavior: `lua/config/completion.lua`
- Telescope and project definitions: `lua/config/telescope.lua`,
  `lua/config/workspace_symbols.lua`
- Plugin dependencies and loading conditions: `lua/plugins/`

Local sessions use the system clipboard. SSH sessions use OSC 52 to communicate with the local
terminal clipboard.

## Validation

Run the focused regression suite with a minimal Neovim runtime:

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

The repository `.luarc.json` supplies the Lua Language Server configuration. Changes to plugin
declarations or startup wiring also receive a full headless startup check and keymap verification.
