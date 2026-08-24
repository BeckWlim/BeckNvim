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
│   ├── type_hierarchy.lua        Recursive LSP class and implementation pickers
│   ├── workspace_symbols.lua     Project-definition finder
│   ├── python/                   Python environment and hierarchy indexing
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Plugin dependencies and loading conditions
```

## Module Ownership

| Module | Responsibility |
| --- | --- |
| `config/project.lua` | Project roots, path containment, and project markers |
| `config/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/query_picker.lua` | Empty-first Telescope lifecycle, incremental refresh, status, and cancellation |
| `config/lsp_locations.lua` | Cancellable LSP definition, declaration, reference, type, and implementation queries |
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
outstanding requests when the picker closes. For Python function-local identifiers, `gr` seeds the
picker from the enclosing Treesitter scope, then replaces those provisional candidates with the
first result from a document-highlight or complete project reference request.

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

Project-root markers belong to `config/project.lua`. Language-specific server markers remain with
their server configuration in `config/lsp.lua`. Mason installation coverage is maintained in the
same LSP module.

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
