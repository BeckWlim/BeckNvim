# Configuration Architecture

The repository separates startup assembly, reusable feature modules, and plugin declarations.

```text
init.lua
lua/
├── config/                       Reusable, testable feature modules, grouped by area
│   ├── init.lua                  Startup assembly
│   ├── project.lua               Project-root authority and path containment
│   ├── startup/                  options.lua, autocmds.lua, lazy.lua, keybindings.lua
│   ├── ui/                       float.lua, folder_picker.lua, dashboard.lua, statusline.lua, filetree.lua, terminal.lua
│   ├── search/                   telescope.lua, query_picker.lua, workspace_symbols.lua,
│   │                             lsp_locations.lua, grep_preview.lua, navigation.lua
│   ├── git/                      init.lua (workflow), diffview.lua (history UI), github.lua and
│   │                             issue.lua (remote details), repository.lua and ui.lua
│   ├── network/                  reusable proxy discovery, session state, and manager UI
│   ├── lsp/                      init.lua (servers), completion.lua, type_information.lua,
│   │                             diagnostics.lua, detail_window.lua
│   ├── syntax/                   treesitter.lua (parser bootstrap), treesitter_context.lua,
│   │                             visuals.lua, highlights.lua, folds.lua
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
| `config/ui/folder_picker.lua` | Reusable Telescope directory browsing, path input, completion, and adaptive sizing |
| `config/ui/filetree.lua` | Nvim-tree mappings, window-switching Tab preservation, and project-boundary confirmation |
| `config/ui/terminal.lua` | ToggleTerm-local escape from terminal input to scrollable Normal mode |
| `config/ui/float.lua` | Shared close-key policy for ordinary editable and read-only floating windows |
| `config/search/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/search/query_picker.lua` | Empty-first Telescope lifecycle, incremental refresh, status, and cancellation |
| `config/search/lsp_locations.lua` | Cancellable LSP definition, declaration, reference, type, and implementation queries |
| `config/search/grep_preview.lua` | Telescope grep/LSP location preview loading, highlighting, and structural winbar context |
| `config/search/telescope.lua` | Telescope defaults, extensions, and previewer wiring |
| `config/search/navigation.lua` | Go-to-referenced-file jumps from prose and code |
| `config/git/init.lua` | File, symbol, and repository history entry points plus safe branch switching |
| `config/git/diffview.lua` | Shared bounded history workspace, lifecycle, layout, and pane keymaps |
| `config/git/github.lua` | GitHub origin parsing and cancellable read-only issue/PR REST boundary |
| `config/git/issue.lua` | Exact-number result integration, single-buffer issue rendering, and related navigation |
| `config/git/panel.lua` | Two-level Git panel stack and unified one-layer `<C-q>` transition |
| `config/git/repository.lua` | Branch limits, parsing, commands, and cancellable process boundary |
| `config/git/ui.lua` | Branch-picker rows and focus proportions |
| `config/network/proxy.lua` | Static environment/`~/.bashrc` proxy discovery shared by GitHub and translation |
| `config/network/ui.lua` | Unified proxy status, candidate selection, direct mode, and custom session input |
| `config/lsp/init.lua` | Language-server configuration and BasedPyright diagnostic policy |
| `config/lsp/completion.lua` | nvim-cmp completion behavior |
| `config/lsp/type_information.lua` | Toggleable hover inference and type-definition preview for LSP languages |
| `config/lsp/diagnostics.lua` | Diagnostic float and document diagnostic picker wiring |
| `config/lsp/detail_window.lua` | Shared focus, same-key close, and copy behavior for detail windows |
| `config/syntax/` | Parser installation and highlighting bootstrap (`treesitter.lua`), Treesitter pinned context, scope and rainbow visuals, highlight policy, and folds |
| `config/type_hierarchy/` | Recursive class and implementation pickers: `init.lua` dispatches by filetype, `python.lua` owns the indexed AST paths and Python source parsing, `lsp.lua` owns the live-request paths, `core.lua` owns shared picker plumbing and walk bookkeeping |
| `config/translation/` | Translation query window (`init.lua`) plus backend construction and response parsing (`providers.lua`) |
| `config/python/environment.lua` | Python interpreter and environment resolution |
| `config/python/hierarchy_index.lua` | Background Python AST index lifecycle and graph queries |
| `config/audit/project.lua` | Batch project analysis and Overseer task coordination |
| `config/audit/diagnostic.lua` | Diagnostic-cache inspection and project reporting |
| `plugins/*.lua` | Plugin specifications, dependencies, conditions, and lightweight setup calls |

## Uniform Floating-Window Behavior

`config.ui.float` is the single definition of ordinary float close behavior. Callers provide a
buffer and close callback, or a Telescope-compatible mapping callback. Editable floats opt into
`accepts_input`: insert-mode `q` remains content and `<C-q>` closes; after returning to normal mode,
`q` closes and `<C-q>` remains unbound for Visual Block. Read-only floats receive only normal-mode
`q`. Window layout, rendering, and feature-specific actions remain in their owning modules.

The translator, Telescope prompts and focused previews, LSP detail windows, and the project-audit
float all consume this definition directly. Telescope explicitly disables its built-in normal-mode
`<C-q>` quickfix action so it cannot violate the shared policy.

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
empty-first and async-filled, while the definition finder is prompt-driven — the prompt is the
query. Both keep insert-mode `q` as query text, use insert-mode `<C-q>` to cancel, and use
normal-mode `q` to close. Picker teardown invokes the finder's `close` and retires the active job
generation.

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

## Git Repository Inspection

`config.git` exposes exactly three history scopes and resolves their repository/file/Tree-sitter
context before delegating to one `config.git.diffview` renderer:

```text
<Space>df → file path + --follow ─────────┐
<Space>ds → cursor structure + line range ├→ bounded FileHistory → bottom list + two code panes
<Space>dr → repository root ──────────────┘
<Space>de → repository history ────────────→ branch/commit/issue dispatcher
```

Diffview supplies the commit metadata, expandable changed-file rows, syntax-aware historical buffers,
line jumps, and horizontal two-way layout. Its history panel starts at ten lines at the bottom;
normal Diffview selection changes the code shown above. `<Tab>` and `<S-Tab>` are replaced in every
main pane with window-focus traversal, preventing the list binding from advancing commits. Ordinary
initial scopes pass `--max-count=50`, so traversal is bounded at the Git boundary. A search-selected
commit that is absent from the mounted list reopens its complete owning-branch history without that
cap, ensuring the target cannot be hidden beyond the first page. A selected commit always compares its
parent on the left (`BEFORE`) with the commit on the right (`AFTER`); explicit winbars show both roles
and revisions before the lower-priority file path, without redundant physical-side labels. The
workflow only reads local Git state and performs no implicit fetch.
File and symbol histories preserve Diffview's single-file and line-trace log options while adapting
only each entry's presentation data. The existing FileHistory renderer therefore shows the same
expandable commit → file footer hierarchy as repository history without replacing renderer methods
or changing filter/navigation semantics. The footer winbar adds the FILE path or the SYMBOL label,
path, and traced line range.
`<Space>dp` calls the history panel's reversible toggle from either code pane or the list, preserving
the panel contents, selected commit, and configured restored height.
Diffview revision buffers opt out of the editor-wide current-scope extmarks but retain the editor's
real pinned Tree-sitter context inside the focused code pane. The pinned source lines use a shared
light-green background and no lower underline. The remaining code render is reduced to syntax
foregrounds, one ordinary cursor-line background, and Diffview's add/change/delete backgrounds.
File and repository history resolve the enclosing definition of the selected hunk, open its fold,
then restore focus to the changed line. Symbol history uses the same boundary but intentionally
leaves focus on the definition.

For symbol history, the selected line-trace patch provides the changed row in each revision buffer.
The renderer asks the shared Tree-sitter context resolver for the nearest enclosing declaration in
each of those two buffers, reveals that declaration within Diffview's patch folds, and falls back to
the changed row when no parser is available. Parsing is limited to the displayed target buffers.
`<Space>fw` is overridden only inside Diffview and opens the shared definition picker over one
in-memory revision buffer. The list defaults to the right-side `AFTER` buffer; either code pane
targets itself. Selection returns to that Diffview pane and reveals the historical declaration, so
the picker never substitutes the working-tree file for commit content. The buffer-local index is
capped at 1,000 definitions, and its preview copy is cached by source buffer and changed tick.

The complete tab is one lifecycle unit: buffer-local `<C-q>` and `<Space>o` mappings are installed
after every layout pass, and command submission rejects interactive `:q`/`:quit` while the view is
active without interfering with Diffview's internal window replacement. A whole-view close focuses
the editing tab first and disposes an in-flight history render asynchronously. `<Space>o` falls back
to the ordinary jumplist outside Git history. Shared Telescope/Diffview highlights keep the list and
code planes visually consistent; diff highlights assign background tints only, preserving syntax
foregrounds on both added and deleted lines.

Git search is a temporary layer above ordinary Git history. Global `<Space>de` first mounts repository
history, then opens the dispatcher; the same buffer-local key reopens it from Git mode. The history view retains its commit/file
panel, selected entry, checkout, and split layout while the picker is active. Buffer-local
`<Space>de` opens `config.git.search` directly as a Telescope prompt, result list, and preview; there
is no preceding footer input and `<C-b>` is not mapped in Git mode. Git search
inherits the branch view's repository/file/symbol scope and caps candidates at 50.

An exact `#<digits>` query sends a digit-boundary regexp to Git, then applies a subject-only check so
body matches and longer references cannot leak into the picker. Git is queried first across locally
available `--branches` and `--remotes`; `%S` source metadata groups each commit beneath its owning
local or remote-tracking branch. Known branches and the GitHub issue are root records.
The preview renderer dispatches by level: branch to aligned commit rows with nested files, commit to
a structured changed-file list, and issue to Markdown. Repository parsing consumes machine-delimited
Git metadata before the UI boundary, so raw `git log` and `git show` output never becomes the preview.
Source, kind, branch/hash, date, and title columns have stable widths and semantic highlights.
`<Tab>` focuses the preview and `<CR>` performs the selected branch or commit action at the cursor.
Focused previews enable the normal editor `CursorLine` background so cursor position remains visible.
An unmapped branch-preview header never falls through to `git switch`; branch checkout is dispatched
only from the branch result row, while preview commit/file rows open read-only review for their mapped
commit hash.

Selecting a commit is a read-only review operation: it leaves HEAD and the working tree untouched.
If the target exists in the mounted FileHistoryView, the renderer preserves that complete ordered
history and selects its row in place. Otherwise it mounts the complete owning-branch history, or the
raw commit hash's ancestry when no branch is known, and selects the requested row after Diffview has
populated the panel. Its panel winbar renders source and branch directly above the list; the selected
row uses the shared selection background. An empty commit retains the complete list and uses
Diffview's blank placeholder in the code area. A replacement view is mounted before the prior history
view is disposed and remains the ordinary Git layer rather than a disposable search layer. Render
options and dispatcher options are stored separately, so reopening `<Space>de` searches repository
history rather than restricting grep to the displayed branch range.
Selecting an issue creates a centered read-only Markdown
float over the untouched parent Diffview instead of entering either split. Normal and Visual editor
operations remain available, including selection and yank. `q` and `<Space>de` close that float and
reconstruct the cached result picker. Related issue navigation stays
inside the Markdown buffer, and `o`/`gx` delegates to `vim.ui.open`. This boundary requires no
instance method replacement, renderer suspension, or split recovery.

Remote scope is selected from the project `origin`, not a global repository setting. Git refs retain
Git's configured transport and therefore reuse SSH configuration naturally. GitHub issue and
pull-request metadata receives the shared proxy environment explicitly. REST is the primary
structured source; public github.com projects fall back to Open Graph metadata from the origin's
issue page when REST is rate-limited. A failed provider becomes a visible `REMOTE ERROR` root record
and is not cached, so changing `:Proxy` or adding `GH_TOKEN` can be retried immediately. Tokens travel
to curl through stdin headers.

`config.git.panel` models the UI as `editor ← ordinary Git history ← temporary search`. Search
results/preview and issue detail are alternate renderers of the same top search layer, not separately
nested modes. Commit and branch choices replace ordinary history in place at the lower layer. Every
Git surface routes `<C-q>` through one pop operation: the top search renderer returns to the preserved
history Diffview, while ordinary history returns to the normal editing tab.
The history list maps `<Space>dm` to the commit under its commit/file row and sends it through that
same guarded detach path. `<CR>` remains Diffview's non-mutating fold/file render action.
Each Git view retains its repository root, selected revision, and historical absolute file path as
separate metadata. This is the boundary for future Git-mode `gd`/`gr` support: definition/reference
requests can be redirected to the displayed revision without treating a virtual Diffview buffer as
the live working-tree document.

A hexadecimal query of 7–64 characters takes the same read-only full-history selection path instead
of message grep. The reopened Diffview receives the owning branch (or raw hash ancestry) and selects
the target even when the object is reachable only from a fetched remote ref; no fetch or checkout
occurs implicitly. `<Space>dm` is the sole commit-list action that enters the guarded mutation
boundary: it resolves the commit object and reads porcelain-v2 HEAD/worktree state, rejecting staged,
unstaged, untracked, or unsaved-buffer changes. If the target is already the checked-out branch's
HEAD, the branch remains attached. An older target uses `git switch --detach`, while an already-
detached HEAD at the same object skips that duplicate operation. Reachability through `refs/heads`
produces a `LOCAL` tag, while remote-only reachability produces `REMOTE`.

The branch drill-down remains a bounded Telescope picker. It prioritizes the current branch and uses
`git switch` without force. Remote-only refs become tracking branches, while an existing local
counterpart is selected directly. Switching is rejected before Git runs if any loaded repository
buffer is modified; disk-level working-tree conflicts remain under Git's own refusal rules. After a
successful switch, a repository history for the selected branch is mounted before the old history is
retired, so Git mode and its bottom commit list remain continuously available.

## Shared Network Proxy

`config.network.proxy` recognizes lowercase and uppercase proxy variables, direct `IP:port` values,
and `no_proxy` bypass lists. Process environment values take precedence; missing values are filled by
statically parsing simple assignments and variable references in `~/.bashrc`. No shell code is
executed. Startup activates the result before lazy.nvim can contact GitHub, while translation uses
the same resolver for each curl subprocess.

`config.network.ui` exposes the same state through `:Proxy`, with exact lowercase `:proxy` expanded
at the command-line boundary. Its Telescope list groups effective routes by compact `host:port`
parents and renders the contributing HTTP, HTTPS, or ALL_PROXY fallback routes as child details. Its
centered layout is capped at 72 columns by 16 lines rather than inheriting the project-search scale.
The leading rows reduce state to `PROXY ON/OFF` and `NO_PROXY ON/OFF`; grouping uses the sanitized
endpoint rather than the URL scheme, so one endpoint cannot appear as several active proxies.
The prompt also accepts `proxy | no_proxy`, allowing one input path to update both fields. A session override is
held separately from discovery so direct mode remains direct even when `~/.bashrc` defines a proxy;
the selected environment is also applied to `vim.env` for future child processes. NO_PROXY has edit,
clear, and loopback-default actions; changing it preserves all protocol-specific routes. Applying an
action refreshes the picker without closing it.
If the translation dialog is active, its cached request environment and proxy label are refreshed
immediately.

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
