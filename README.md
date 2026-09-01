# Neovim Configuration

A personal Neovim configuration for daily development. Plugin management uses
[lazy.nvim](https://github.com/folke/lazy.nvim), with completion, LSP, fuzzy search, Git tools,
terminals, a file tree, Markdown rendering, rainbow delimiters, and a subtle current-scope background
included. Within that grey code domain, the cursor line uses a stronger grey highlight for clear focus;
scopes larger than 120 lines are left unshaded to avoid overwhelming the file.

## Requirements

- Neovim 0.11 or newer
- Git
- Python 3.10 or newer for the low-latency Python hierarchy index
- `curl` for the translation component
- [ripgrep](https://github.com/BurntSushi/ripgrep) for full-text and project-definition search
- `make` and a C compiler for `telescope-fzf-native.nvim`
- The [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md)
  (`npm install -g tree-sitter-cli`): the `main` branch of nvim-treesitter builds parsers through
  it. The CLI enables parser installation, sticky scope headers, grep-preview breadcrumbs,
  Treesitter highlighting, and folding. The config installs the Python and C++ parsers automatically
  on startup once the CLI is available.
- A Nerd Font for the complete icon set; the GUI defaults to Hack Nerd Font

Mason installs the configured language servers on demand. The current setup covers Bash,
C/C++, Lua, Markdown, Python, and Vim script.

### Linux packages

Ubuntu 24.04 ships an older Neovim in its default repositories, so install Neovim 0.11 or
newer from the [official PPA](https://github.com/neovim/neovim/blob/master/INSTALL.md#ubuntu) or a
standalone tarball. The remaining runtime dependencies install with:

```bash
sudo apt install git curl wget unzip ripgrep make gcc python3 nodejs npm cmake ninja-build
```

- `make` and `gcc` compile `telescope-fzf-native.nvim` and the Treesitter parsers.
- `unzip`, `wget`, and `curl` let Mason download and extract the language servers.
- `nodejs` and `npm` are needed by Mason to install the BasedPyright Python language server, and
  by `npm install -g tree-sitter-cli`, which nvim-treesitter needs to build its parsers.
- `cmake` and `ninja-build` power `cmake-tools.nvim` for C/C++ builds.
- `xclip` (X11) or `wl-clipboard` (Wayland) provides the system clipboard used by `unnamedplus`;
  install the one matching your display server.
- A [Nerd Font](https://www.nerdfonts.com/) such as Hack Nerd Font supplies the complete icon set.

## Quick Start

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
├── config/                       Reusable, testable feature modules, grouped by area
│   ├── init.lua                  Configuration assembly order
│   ├── project.lua               Shared project-root and path boundary logic
│   ├── startup/                  Editor options, autocmds, plugin bootstrap, keymaps
│   ├── ui/                       Float/folder-picker policy, dashboard, statusline, file tree, terminal
│   ├── search/                   Telescope wiring, pickers, definitions, LSP locations
│   ├── git/                      History/detach workflow, Diffview UI, GitHub issue details
│   ├── lsp/                      Servers, completion, type information, diagnostics
│   ├── syntax/                   Treesitter context, scope visuals, highlights, folds
│   ├── type_hierarchy/           Recursive class hierarchy and implementation pickers
│   ├── translation/              Translation query UI and backend providers
│   ├── python/                   Python environment and hierarchy indexing
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Lightweight lazy.nvim plugin specifications
tests/                            Focused regression tests
lazy-lock.json                    Pinned plugin versions
```

See [Architecture](docs/architecture.md) for module ownership and extension rules. The project-local
[`nvim-design`](.agents/skills/nvim-design/SKILL.md) skill guides implementation work, while
[`nvim-guide`](.agents/skills/nvim-guide/SKILL.md) covers installation and advanced usage.

## Main Functions and Keymaps

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
| `<Space>h` | Return to the dashboard for recent projects or files |
| `<Space>zz/zc/zo` | Toggle, close all, or open all folds |
| `<Space>cc` | Jump to the nearest enclosing syntax context; repeat to move outward |

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

### Project Root Policy

Project roots use one shared authority order across the statusline, searches, audits, and file
tree:

1. The nearest ancestor containing `.git` is authoritative.
2. Outside Git repositories, the most specific attached LSP root is used for an open buffer.
3. Next, the nearest workspace marker is used: `.venv`, Pyright configuration,
   language manifests, or build-system files.
4. The current working directory is the final fallback.

The statusline shows the provider, root name, and project-relative file path. `<Space>h` opens the
dashboard for recent projects and files; `h/l` changes project, `j/k` changes file, and `<Enter>`
opens the selection. Press `f` for the shared folder picker, then use `<C-h>`/`<C-l>` to browse,
`<Tab>` to complete a path, and `<Enter>` to open the workspace.

In nvim-tree, `<C-[>` moves the root outward and `<C-]>` moves it into the selected node. Crossing a
project boundary asks for confirmation. These features are owned by `config.project` and `config.ui`.

#### Project Definition Search

`<Space>fw` searches project definitions for Python, C/C++/CUDA, Lua, Shell, Vim script, and Markdown.
Results show the symbol, kind, path, and syntax-aware source preview. `gd`, `gD`, `gr`, and `gI`
remain the LSP navigation keys.

Across Telescope pickers, `<Tab>` moves between results and preview, while `<C-v>` and `<C-x>` open
the selection in a vertical or horizontal split. `config.search` owns picker behavior and reuses the
pinned class/function context from `config.syntax`.

#### Git Repository Inspection

`<Space>df`, `<Space>ds`, and `<Space>dr` open file, symbol, and repository history in one Diffview
workspace. Every scope uses the same commit → file footer and `BEFORE`/`AFTER` code panes; FILE keeps
rename tracking and SYMBOL keeps its Git line trace. `<Space>fw` searches definitions in the displayed
historical buffer.

`<Space>de` enters repository history and opens the Telescope dispatcher for branches, commits,
changed files, and GitHub issues. A `#<digits>` query combines exact Git subject matches with the
origin issue or pull request. Search selection reviews and highlights a commit while preserving HEAD;
`<Space>dm` performs guarded checkout from the footer. Current branch HEAD stays attached, and an
older commit uses detached HEAD.

Use `<Tab>`/`<S-Tab>` between the footer and code panes, `<Space>dp` to collapse or restore the
footer, and `<C-q>` to return from search or issue detail to history and then to the editor. Git uses
the repository's configured transport; GitHub metadata uses the shared proxy environment. The
workflow is owned by `config.git`; detailed behavior lives in
[`nvim-guide`](.agents/skills/nvim-guide/references/advanced-usage.md).

### Pinned Syntax Context

The pinned context keeps class/function structure and the scope nearest the cursor visible within a
six-line soft budget. `<Space>cc` moves outward through enclosing scopes. `config.syntax` provides the
same context and highlight policy to editor, Telescope, and Diffview panes.

### LSP and Diagnostics

| Key | Action |
| --- | --- |
| `gd` / `gD` | Find definitions/declarations |
| `gr` / `gI` | Find references/implementations |
| `K` | Show hover documentation |
| `<Space>k` | Toggle inferred type and type-definition window |
| `<Space>i` | Find implementations |
| `<Space>D` | Find type definitions |
| `<Space>rn` | Rename a symbol |
| `<Space>e` | Show diagnostic details |
| `[d` / `]d` | Move to the previous/next diagnostic |
| `<Space>q` | Search diagnostics in the current file with Telescope |
| `<Space>lp` | Toggle BasedPyright third-party dependency diagnostics |
| `<Space>cd` | Find all direct and indirect derived classes under the cursor |
| `<Space>cb` | Find all direct and indirect base classes under the cursor |
| `<Space>ci` | Find concrete implementations of the class or method under the cursor |

`<Space>k` opens inferred type information and type-definition previews; `<CR>` jumps, `y` copies,
and `q` closes. `<Space>e` uses the same detail-window style for diagnostics. `config.lsp` owns both
workflows and their language-server requests.

#### Cancellable LSP Queries

Definition, reference, type-definition, implementation, and hierarchy queries open Telescope
immediately and stream partial LSP results into the list. Closing the picker cancels the active
requests. Python references can seed fast local candidates before semantic results arrive.

#### Type Hierarchy and Implementations

`<Space>cd`, `<Space>cb`, and `<Space>ci` find derived classes, base classes, and concrete
implementations. C/C++ uses clangd hierarchy data; Python uses the background project index. Results
include their owning class and support Telescope preview and split actions. `config.type_hierarchy`
owns this feature.

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
| `<Space>df` | Open bounded history for the current file |
| `<Space>de` | Enter repository Git mode and search branches, commits, and GitHub issues |
| `<Space>ds` | Open bounded history for the function or class under the cursor |
| `<Space>dr` | Open bounded history for the complete repository |
| `<Space>dp` | Temporarily collapse or restore the Git history panel |
| `<Space>dm` | In the Git history list, checkout the selected commit version |
| `<Space>fw` | Search project definitions; inside Git history, search the selected revision buffer |
| `gcc` / `gc` | Comment the current line or selection |

Inside the file tree, `<Tab>` keeps the global next-window behavior instead of opening a folder or
preview. `<CR>` opens regular files and directories but ignores the `..` parent entry; use `<C-[>`
to move the tree root out to its parent and `<C-]>` to move the root into the selected directory.
`<S-Tab>` continues to select the previous window.

The `<C-t>` terminal starts in terminal-input mode. Press `<Esc>` to return to Normal mode, where
regular scrolling and motions can inspect earlier output; press `v` to select terminal text, or
`i`/`a` to resume terminal input. This mapping is local to ToggleTerm buffers.

#### Translation Configuration

`config.network` resolves process and shell proxy settings before plugin bootstrap. `:Proxy` shows
the effective HTTP, HTTPS, fallback, and NO_PROXY routes; `<Enter>` selects or edits a session route,
and direct mode bypasses the proxy. Shell configuration supplies persistence.

`<Space>t` opens live Chinese/English translation through MyMemory. Its title shows the provider and
proxy state, and network errors render in the same window. `config.translation` owns the query UI and
provider parsing; GitHub metadata shares the network module.

## Customization

- Theme and completion colors: `lua/plugins/theme.lua`
- Indentation, clipboard, and display options: `lua/config/startup/options.lua`
- LSP behavior: `lua/config/lsp/init.lua`
- Completion behavior: `lua/config/lsp/completion.lua`
- Shared GitHub/translation proxy discovery: `lua/config/network/proxy.lua`
- Translation providers: `lua/config/translation/providers.lua`
- Class hierarchy and method implementations: `lua/config/type_hierarchy/`
- Telescope and project definitions: `lua/config/search/telescope.lua`,
  `lua/config/search/workspace_symbols.lua`
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
