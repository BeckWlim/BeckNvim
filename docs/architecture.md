# Configuration Architecture

The repository separates startup assembly, reusable feature modules, and plugin declarations.

```text
init.lua
lua/
├── config/                       Reusable, testable feature modules, grouped by area
│   ├── init.lua                  Startup assembly
│   ├── project.lua               Project-root authority and path containment
│   ├── startup/                  options.lua, autocmds.lua, lazy.lua, keybindings.lua
│   ├── ui/                       dashboard.lua, statusline.lua, filetree.lua, terminal.lua
│   ├── search/                   telescope.lua, query_picker.lua, workspace_symbols.lua,
│   │                             lsp_locations.lua, grep_preview.lua, navigation.lua
│   ├── lsp/                      init.lua (servers), completion.lua, type_information.lua,
│   │                             diagnostics.lua, detail_window.lua
│   ├── syntax/                   treesitter_context.lua, visuals.lua, highlights.lua, folds.lua
│   ├── type_hierarchy/           Recursive class and implementation pickers
│   ├── translation/              Translation query UI and backend providers
│   ├── python/                   Python environment and hierarchy indexing
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Plugin dependencies and loading conditions
```

## Module Ownership

| Module | Responsibility |
| --- | --- |
| `config/project.lua` | Project-root authority, path containment, markers, and cached Git-host detection |
| `config/startup/` | Editor options, global autocmds, lazy.nvim bootstrap, and the single keymap assembly |
| `config/ui/statusline.lua` | Explicit project identity and project-relative current-file state |
| `config/ui/dashboard.lua` | Bounded project drawer, project-relative MRU state, and dashboard actions |
| `config/ui/filetree.lua` | Nvim-tree mappings, window-switching Tab preservation, and project-boundary confirmation |
| `config/ui/terminal.lua` | ToggleTerm-local escape from terminal input to scrollable Normal mode |
| `config/search/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/search/query_picker.lua` | Empty-first Telescope lifecycle, incremental refresh, status, and cancellation |
| `config/search/lsp_locations.lua` | Cancellable LSP definition, declaration, reference, type, and implementation queries |
| `config/search/grep_preview.lua` | Telescope grep/LSP location preview loading, highlighting, and structural winbar context |
| `config/search/telescope.lua` | Telescope defaults, extensions, and previewer wiring |
| `config/search/navigation.lua` | Go-to-referenced-file jumps from prose and code |
| `config/lsp/init.lua` | Language-server configuration and BasedPyright diagnostic policy |
| `config/lsp/completion.lua` | nvim-cmp completion behavior |
| `config/lsp/type_information.lua` | Toggleable hover inference and type-definition preview for LSP languages |
| `config/lsp/diagnostics.lua` | Diagnostic float and document diagnostic picker wiring |
| `config/lsp/detail_window.lua` | Shared focus, same-key close, and copy behavior for detail windows |
| `config/syntax/` | Treesitter pinned context, scope and rainbow visuals, highlight policy, and folds |
| `config/type_hierarchy/` | Recursive class and implementation pickers: `init.lua` dispatches by filetype, `python.lua` owns the indexed AST paths and Python source parsing, `lsp.lua` owns the live-request paths, `core.lua` owns shared picker plumbing and walk bookkeeping |
| `config/translation/` | Translation query window (`init.lua`); backend providers, proxy resolution, and response parsing (`providers.lua`) |
| `config/python/environment.lua` | Python interpreter and environment resolution |
| `config/python/hierarchy_index.lua` | Background Python AST index lifecycle and graph queries |
| `config/audit/project.lua` | Batch project analysis and Overseer task coordination |
| `config/audit/diagnostic.lua` | Diagnostic-cache inspection and project reporting |
| `plugins/*.lua` | Plugin specifications, dependencies, conditions, and lightweight setup calls |

## Project Definition Search

`config.search.workspace_symbols` owns the `<Space>fw` workflow:

```text
<Space>fw
  → Telescope definition prompt
  → parallel language-specific ripgrep jobs
  → extension-aware definition parser
  → name / kind / relative-path result row
  → source preview
```

The query policy is shared across every supported language:

- Python, C/C++/CUDA, Lua, Shell, Vim script, and Markdown participate in each query.
- Two-character input uses a definition-name prefix.
- Longer input uses definition-name containment.
- A query emits up to 1,000 Telescope candidates.
- A new prompt cycle retires the previous generation and releases its active jobs.
- Search results enter Telescope through Neovim's scheduled main-loop callbacks.
- Picker readiness activates after Telescope setup; an earlier invocation reports its loading state.

This finder is deliberately separate from `config.search.query_picker`. A query-picker session is
empty-first and async-filled, so `q` can cancel even in insert mode; the definition finder is
prompt-driven — the prompt is the query — so cancellation rides on Telescope's normal-mode `q`
and picker teardown, which invokes the finder's `close` and retires the active job generation.

LSP navigation has a separate ownership path through `config.search.lsp_locations`. Every location query
opens its Telescope session before dispatching requests, streams available results, and cancels
outstanding requests when the picker closes. Cancelled primary requests are retried once; auxiliary
document-highlight failures do not turn a successful project reference request into a failed query.
For Python function-local identifiers, `gr` seeds the picker from the enclosing Treesitter scope,
then replaces those provisional candidates with the first successful document-highlight or complete
project reference response.

`config.lsp.type_information` is deliberately outside that search path. `<Space>k` opens one focused
plain-text detail float, requests hover inference and type-definition locations in parallel, and
renders the responses in place. It never creates a Telescope candidate list. Definition rows and
their source previews support direct `<CR>` jumps. `config.lsp.detail_window` gives both this float and
the diagnostic detail float the same focus, wrapping, continuation marker, same-key close, `q`
close, and `y` copy behavior. Cursor-line selection is enabled for the navigable type-definition
list but omitted for diagnostic details, whose quick buttons render in a muted content line.

## Type Hierarchy and Implementations

`config.type_hierarchy` owns three semantic navigation workflows. `init.lua` is only a
dispatcher: Python buffers query the background AST index first and fall back to live requests;
other languages go straight to the LSP paths.

```text
C++ <Space>cd/cb → empty picker → clangd Type Hierarchy → incremental recursive graph
C++ <Space>ci    → empty picker → clangd implementations → class-qualified entries
Python FileType  → background AST scan → in-memory inheritance/method index
Python cd/cb/ci  → empty picker → in-memory graph query
```

`core.lua` supplies the shared picker plumbing and the recursive-walk bookkeeping
(deduplication, pending-request tracking, depth-sorted publication) used by both the clangd
hierarchy walk and the Python definition-request fallback.

Each path creates the empty picker first. Recursive C++ responses refresh it incrementally, and the
picker session owns cancellation for both initial and descendant requests.

For C++, clangd supplies standard Type Hierarchy nodes, which are deduplicated by URI, name, and
source range before recursive expansion. BasedPyright does not expose that protocol, so
`config.python.hierarchy_index` starts a background standard-library AST scan when a Python buffer
opens. It resolves local imports and aliases, records positioned base-class references, builds
parent/child and method maps, excludes virtual
environments and build outputs during directory traversal, and serves queries from memory. A save
starts a background refresh while the previous complete snapshot remains queryable. LSP requests
remain a fallback when the current symbol is absent from the index. Method implementations omit the
declaration under the cursor and display class-qualified Python and C++ names.

## Extension Rules

Place plugin declarations in `plugins/` and feature behavior in a responsibility-focused `config`
module. Extend project-definition support by adding the file globs, definition pattern, parser, and
focused fixture to `config.search.workspace_symbols` and `tests/workspace_symbols.lua`.

Project-root authority belongs to `config/project.lua`. Git repository roots outrank attached LSP
roots; LSP roots outrank `.venv`, language manifest, and build-file fallbacks. Consumers must use
this shared policy instead of maintaining their own marker order. Language-server startup markers
remain with `config/lsp/init.lua`. Mason installation coverage is maintained in the same LSP module.

`dashboard-nvim` remains responsible for the homepage buffer lifecycle. The local
`dashboard.theme.project` module delegates its compact rendering and navigation to
`config.ui.dashboard`; recent files come from `vim.v.oldfiles`, are grouped through the shared project
authority policy, and are capped before rendering. Activating a project updates the dashboard
window's local working directory and context in place; it does not create an empty file buffer or
open the file tree.

Project audits share project context through `config.project`; each audit module owns its own task
or diagnostic state.

## Validation

Run the focused suite with a minimal Neovim runtime:

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

Use the repository `.luarc.json` for Lua Language Server checks. Startup-related changes also
receive a full headless startup check, keymap assertions, and an end-to-end query in a representative
project.
