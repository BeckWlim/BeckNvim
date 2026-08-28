# Configuration Architecture

The repository separates startup assembly, reusable feature modules, and plugin declarations.

```text
init.lua
lua/
├── config/                       Reusable, testable feature modules
│   ├── init.lua                  Startup assembly
│   ├── options.lua               Editor options
│   ├── autocmds.lua              Global events
│   ├── lazy.lua                  Plugin manager bootstrap
│   ├── keybindings.lua           Global keymap assembly
│   ├── query_picker.lua          Immediate, incremental, cancellable query sessions
│   ├── lsp_locations.lua         Reference and location query orchestration
│   ├── detail_window.lua         Shared focused detail-window interactions
│   ├── type_information.lua      Combined inferred-type and type-definition float
│   ├── terminal.lua              ToggleTerm-local terminal-mode navigation
│   ├── filetree.lua              Nvim-tree-local mapping policy
│   ├── grep_preview.lua          Structural context for Telescope grep previews
│   ├── treesitter_context.lua    Priority-aware pinned syntax context
│   ├── type_hierarchy.lua        Recursive LSP class and implementation pickers
│   ├── workspace_symbols.lua     Project-definition finder
│   ├── python/                   Python environment and hierarchy indexing
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Plugin dependencies and loading conditions
```

## Module Ownership

| Module | Responsibility |
| --- | --- |
| `config/project.lua` | Project-root authority, path containment, markers, and cached Git-host detection |
| `config/statusline.lua` | Explicit project identity and project-relative current-file state |
| `config/dashboard.lua` | Bounded project drawer, project-relative MRU state, and dashboard actions |
| `config/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/query_picker.lua` | Empty-first Telescope lifecycle, incremental refresh, status, and cancellation |
| `config/lsp_locations.lua` | Cancellable LSP definition, declaration, reference, type, and implementation queries |
| `config/detail_window.lua` | Shared focus, same-key close, and copy behavior for detail windows |
| `config/type_information.lua` | Toggleable hover inference and type-definition preview for LSP languages |
| `config/terminal.lua` | ToggleTerm-local escape from terminal input to scrollable Normal mode |
| `config/filetree.lua` | Nvim-tree mappings, window-switching Tab preservation, and project-boundary confirmation |
| `config/grep_preview.lua` | Telescope grep/LSP location preview loading, highlighting, and structural winbar context |
| `config/treesitter_context.lua` | Structural and nearest-scope retention within the pinned-context budget |
| `config/type_hierarchy.lua` | Recursive LSP type hierarchy and class-qualified method implementations |
| `config/telescope.lua` | Telescope defaults and keymap assembly |
| `config/lsp.lua` | Language-server configuration and BasedPyright diagnostic policy |
| `config/python/environment.lua` | Python interpreter and environment resolution |
| `config/python/hierarchy_index.lua` | Background Python AST index lifecycle and graph queries |
| `config/audit/project.lua` | Batch project analysis and Overseer task coordination |
| `config/audit/diagnostic.lua` | Diagnostic-cache inspection and project reporting |
| `plugins/*.lua` | Plugin specifications, dependencies, conditions, and lightweight setup calls |

## Project Definition Search

`config.workspace_symbols` owns the `<Space>fw` workflow:

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

LSP navigation has a separate ownership path through `config.lsp_locations`. Every location query
opens its Telescope session before dispatching requests, streams available results, and cancels
outstanding requests when the picker closes. Cancelled primary requests are retried once; auxiliary
document-highlight failures do not turn a successful project reference request into a failed query.
For Python function-local identifiers, `gr` seeds the picker from the enclosing Treesitter scope,
then replaces those provisional candidates with the first successful document-highlight or complete
project reference response.

`config.type_information` is deliberately outside that search path. `<Space>k` opens one focused
plain-text detail float, requests hover inference and type-definition locations in parallel, and
renders the responses in place. It never creates a Telescope candidate list. Definition rows and
their source previews support direct `<CR>` jumps. `config.detail_window` gives both this float and
the diagnostic detail float the same focus, wrapping, continuation marker, same-key close, `q`
close, and `y` copy behavior. Cursor-line selection is enabled for the navigable type-definition
list but omitted for diagnostic details, whose quick buttons render in a muted content line.

## Type Hierarchy and Implementations

`config.type_hierarchy` owns three semantic navigation workflows:

```text
C++ <Space>cd/cb → empty picker → clangd Type Hierarchy → incremental recursive graph
C++ <Space>ci    → empty picker → clangd implementations → class-qualified entries
Python FileType  → background AST scan → in-memory inheritance/method index
Python cd/cb/ci  → empty picker → in-memory graph query
```

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
focused fixture to `config.workspace_symbols` and `tests/workspace_symbols.lua`.

Project-root authority belongs to `config/project.lua`. Git repository roots outrank attached LSP
roots; LSP roots outrank `.venv`, language manifest, and build-file fallbacks. Consumers must use
this shared policy instead of maintaining their own marker order. Language-server startup markers
remain with `config/lsp.lua`. Mason installation coverage is maintained in the same LSP module.

`dashboard-nvim` remains responsible for the homepage buffer lifecycle. The local
`dashboard.theme.project` module delegates its compact rendering and navigation to
`config.dashboard`; recent files come from `vim.v.oldfiles`, are grouped through the shared project
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
