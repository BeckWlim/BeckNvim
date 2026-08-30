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
  it. Without it, parser installation fails silently and the sticky scope header, grep-preview
  breadcrumbs, Treesitter highlighting, and folding stop rendering. The config installs the Python
  and C++ parsers automatically on startup once the CLI is available.
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
├── config/                       Reusable, testable feature modules, grouped by area
│   ├── init.lua                  Configuration assembly order
│   ├── project.lua               Shared project-root and path boundary logic
│   ├── startup/                  Editor options, autocmds, plugin bootstrap, keymaps
│   ├── ui/                       Dashboard, statusline, file tree, and terminal behavior
│   ├── search/                   Telescope wiring, pickers, definitions, LSP locations
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
3. Without either, the nearest workspace marker is used: `.venv`, Pyright configuration,
   language manifests, or build-system files.
4. The current working directory is the final fallback.

The statusline renders a GitHub, GitLab, Bitbucket, generic Git, or workspace icon followed by the
root name and project-relative file path. In nvim-tree,
`<C-[>` moves the tree root out and `<C-]>` moves it into the selected node. Changes within the
same detected project proceed immediately; crossing a project boundary asks for confirmation.

`<Space>h` opens a compact project theme hosted by dashboard-nvim. A larger terminal Neovim mark and
fixed `PROJECT DECK` title use a stable upper-page anchor, while the horizontal drawer of up to five
recent projects extends the visual weight toward the center. The launch-directory project occupies the
leftmost position, and project positions then remain fixed; `h/l` only moves the selection. The active project's ten
most recent files appear below using project-relative paths, and `j/k` selects a file. The project
containing Neovim's launch directory starts selected at the left of the drawer. `<Enter>`
opens the selected file, or activates the selected project in the same homepage when the drawer is
focused; project activation does not open or focus the file tree. The active project and its stable
project-root path appear in a compact two-line footer with provider and folder icons, regardless of
which project file opened the homepage. The project rows and key prompt share a fixed bottom anchor
with two rows of breathing room. `q` closes the dashboard.
The colors, restrained separators, selection background, and
muted key hint reuse the same visual language as the diagnostic and type-information dialogs.

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

Telescope results support `<C-v>` for a vertical split, `<C-x>` for a horizontal split, and
`<C-q>` for immediately closing the picker from insert or normal mode.
Grep previews, including `<Space>fg` and `<Space>fw`, pin the enclosing class/function hierarchy in
their winbar, such as `Service › run`; conditional and loop blocks are intentionally omitted.
LSP location previews use the same structural winbar, including reference results opened with `gr`.
The winbar reuses the regular pinned-context background, bold foreground, muted hierarchy separator,
and green lower boundary so preview and source-window context remain visually consistent.

### Pinned Syntax Context

The context window uses a six-line soft budget. Class, function, method, and comparable structural
scopes always remain visible, as does the scope nearest the cursor. When those anchors and all
intermediate block scopes do not fit, inner block scopes consume the remaining budget first and
middle `if`, `with`, loop, or similar scopes may be omitted. Mandatory structural and nearest scopes
may exceed the soft budget rather than disappear.

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

`<Space>k` is a plain-text detail view rather than a search picker. It focuses one floating window
and fills it asynchronously with the current symbol's LSP hover inference plus type-definition
locations and source lines. Treesitter colors only fenced hover signatures and definition source
previews using the source buffer's language; styled headings, numbered paths, muted controls, a
cursor line, and word-aware hanging wraps keep the surrounding UI readable.
Press `<CR>` on a definition or its preview to jump there; with one definition, `<CR>` works anywhere
in the window. Press `<Space>k` or `q` to close it and `y` to copy its contents. Python uses
BasedPyright and C/C++ uses clangd through the same language-neutral requests; `<Space>D` remains the
separate Telescope workflow for searching type-definition results.

`<Space>e` uses the same focused detail-dialog layout, word wrapping, continuation marker, same-key
close, and copy behavior while preserving Neovim's diagnostic severity, source, code, and
related-information highlights. It omits the list-only cursor-line background and places its quick
buttons in a muted content line because a diagnostic detail normally contains one item.

#### Cancellable LSP Queries

Definition, declaration, reference, type-definition, implementation, and class-hierarchy commands
open an empty Telescope window immediately instead of waiting for the language server. The title
shows whether the request is still running and how many partial results are available. While a
request is active, `q` in either insert or normal mode cancels every outstanding LSP request and
closes the picker; closing the picker through another action also cancels its work.

For a Python identifier inside a function, `gr` first scans identifier nodes in the enclosing syntax
scope and normally displays local candidates within a few milliseconds. It then starts the current
document's semantic-highlight request in parallel with the full project reference request. The first
semantic response replaces the provisional syntax candidates; subsequent results are deduplicated
and merged into the already visible picker.

#### Type Hierarchy and Implementations

The class tools use language-server semantics instead of textual class-name matching, so aliases,
imports, multiple inheritance, and cross-file relationships remain resolvable. With C++, clangd's
native Type Hierarchy recursively supplies the complete base/derived tree and its depth. Because
BasedPyright does not implement that protocol, Python files are indexed in the background with the
standard-library AST parser. Queries then traverse the in-memory class graph without waiting for an
LSP round trip; a warm query is expected to open within 100 ms. The index is prepared when a Python
buffer opens, excludes virtual environments and build outputs, and refreshes after saving a Python
file while continuing to serve the previous ready snapshot. LSP remains the fallback for symbols
that are not present in the project index.

On a Python method decorated with `@abstractmethod`, `<Space>ci` reads concrete overrides from the
in-memory class graph and labels each result with its owning class, such as `SqlRepository.save`.
On a class name—including a base-class reference inside a multiline inheritance list—it resolves
that exact indexed class and lists its direct and indirect derived classes without an LSP fallback.
For a C++ pure virtual method, clangd results are labeled similarly as `SqlRepository::save`. The
abstract declaration itself is excluded. Class results appear incrementally during recursive LSP
queries. All three pickers support preview, `<CR>` to open, `<C-v>` for a vertical split, and `<C-x>`
for a horizontal split.

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

Inside the file tree, `<Tab>` keeps the global next-window behavior instead of opening a folder or
preview. `<CR>` opens regular files and directories but ignores the `..` parent entry; use `<C-[>`
to move the tree root out to its parent and `<C-]>` to move the root into the selected directory.
`<S-Tab>` continues to select the previous window.

The `<C-t>` terminal starts in terminal-input mode. Press `<Esc>` to return to Normal mode, where
regular scrolling and motions can inspect earlier output; press `v` to select terminal text, or
`i`/`a` to resume terminal input. This mapping is local to ToggleTerm buffers.

#### Translation Configuration

The translation defaults are configured in `lua/config/translation/`. The proxy is resolved at
query time by `resolve_proxy()` instead of a fixed address: proxy variables already exported into
Neovim's environment (`http_proxy` / `https_proxy` / `ALL_PROXY`, upper or lower case) are used
as-is, and when none are present requests go direct with no proxy.

The active provider and proxy are shown in a status line at the top of the query window (for
example `MyMemory · proxy 127.0.0.1:7890`, or `MyMemory · no proxy`). Two providers are supported:
[MyMemory](https://mymemory.translated.net/doc/spec.php) (the default) and Google. Press `<C-p>` in
either insert or normal mode to switch between them; the current input is re-translated immediately.
Each translation and dictionary subprocess receives the resolved variables explicitly, so running a
separate `proxy_on` shell function is unnecessary. Network errors and timeouts are captured and
rendered inside the query window, never echoed into Neovim's command line. Backend selection,
proxy resolution, and response parsing live in `providers.lua`; the query window, debounce delay,
and 500-byte backend limit live in `init.lua`.

## Customization

- Theme and completion colors: `lua/plugins/theme.lua`
- Indentation, clipboard, and display options: `lua/config/startup/options.lua`
- LSP behavior: `lua/config/lsp/init.lua`
- Completion behavior: `lua/config/lsp/completion.lua`
- Translation defaults and proxy: `lua/config/translation/providers.lua`
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
