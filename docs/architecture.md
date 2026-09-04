# BeckNvim Architecture

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
| `config/ui/open_target.lua` | Shared URL routing/handoff and confirmed local-file navigation for global and feature-owned actions |
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
| `config/git/lifecycle.lua` | Generation-checked Git render/return/anchor state machine and structured diagnostics |
| `config/git/events.lua` | Asynchronous public event port between the Git subsystem and editor-owned consumers |
| `config/git/github.lua` | Cancellable read-only GitHub issue/PR acquisition and discussion-enrichment boundary |
| `config/git/issue.lua` | Exact-number and direct-URL integration, shared issue/PR rendering, and related navigation |
| `config/git/reference.lua` | Unified local-path, direct-URL, Git-remote, and Git-command-output parser for structured GitHub record references |
| `config/git/panel.lua` | Two-level Git panel stack and unified one-layer `<C-q>` transition |
| `config/git/repository.lua` | Branch limits, parsing, commands, and cancellable process boundary |
| `config/git/ui.lua` | Branch-picker rows and focus proportions |
| `config/network/proxy.lua` | Validated persistent proxy state and static environment/`~/.bashrc` discovery shared by network consumers |
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
| `config/python/hierarchy_index.lua` | Demand-driven Python AST index lifecycle and graph queries |
| `config/audit/project.lua` | Batch project analysis and Overseer task coordination |
| `config/audit/diagnostic.lua` | Diagnostic-cache inspection and project reporting |
| `plugins/*.lua` | Plugin specifications, dependencies, conditions, and lightweight setup calls |

## Asynchronous I/O Policy

Interactive workflows must keep child-process, filesystem, LSP, and network waits off Neovim's
main loop. The shared design is bounded concurrency with incremental rendering, not unbounded fanout:

- split work into a small fixed number of independent jobs only when the input has natural
  partitions, as `<Space>fw` does for language families;
- publish partial results through scheduled main-loop callbacks and make the smallest useful result
  set interactive without waiting for optional enrichment;
- give every picker, panel, or view a generation and cancellable request ownership, then discard
  callbacks whose generation, target, or selection is no longer current;
- apply backpressure with result limits, bounded workers, and demand-driven enrichment. Never launch
  one Git or network process for every row in a result list;
- separate acquisition and parsing from rendering. Async callbacks deliver structured data to the
  renderer that already owns the surface;
- represent timeout and failure as lifecycle states that remain safely closable, and release child
  jobs or loaded resources during replacement and teardown.

Git mode is the reference stateful implementation: its view generation guards streamed history,
render sequences reject superseded file callbacks, scoped commit files load only when expanded, and
closing a view cancels enrichment before retiring Diffview. Telescope and LSP workflows use the same
generation/cancellation principle while retaining their own native renderers.

## Uniform Floating-Window Behavior

`config.ui.float` is the single definition of ordinary float close behavior. Callers provide a
buffer and close callback, or a Telescope-compatible mapping callback. Editable floats opt into
`accepts_input`: insert-mode `q` remains content and `<C-q>` closes; after returning to normal mode,
`q` closes and `<C-q>` remains unbound for Visual Block. Read-only floats receive only normal-mode
`q`. Window layout, rendering, and feature-specific actions remain in their owning modules.

The translator, Telescope prompts and focused previews, LSP detail windows, and the project-audit
float all consume this definition directly. Telescope explicitly disables its built-in normal-mode
`<C-q>` quickfix action so it cannot violate the shared policy.

## Markdown Rendering

`render-markdown.nvim` owns ordinary Markdown presentation. Its public `win_options` adapter enables
word-aware soft rows in the rendered state, with break indentation, a visible continuation marker,
and smooth scrolling; it never inserts wrapping newlines into the source. The raw state restores the
global no-wrap policy so the option cannot leak into a later code buffer in the same window.

Pipe tables extend the plugin through its supported custom-handler boundary while retaining the
plugin's parser, redraw, conceal, and teardown lifecycle. The built-in pipe-table pass is disabled so
the adapter can measure each column's maximum visible content width. If all columns fit, the table
stays intrinsic and compact; otherwise a water-fill allocation caps short columns at their required
width and redistributes the remaining split capacity evenly among columns that still overflow. Body
cells reuse those widths for cell-local virtual continuation rows. Link destinations are removed
before measuring their visible labels. A centered header, one separator, one closing rule, faint
dashed spacing between body records, and whitespace column gaps avoid vertical-grid reconstruction.
The block is anchored at the Markdown source indentation. It may use the complete remaining width
through an 80-column threshold, so narrow views such as 27-column splits sacrifice no cell capacity.
Above that threshold, its responsive cap grows toward 80% of the split and reserves approximately
20% as external whitespace on the right in wide views. Allocation then excludes one left and two
right inner-margin cells, keeping the final column away from the rule edge without forcing a compact
table to fill its cap.
Inline-code delimiters are concealed like ordinary rendered Markdown, while the cell adapter carries
their span metadata through wrapping and renders each resulting fragment with a distinct key-like
background and the resolved `@markup.raw.markdown_inline` purple foreground.
When the cursor reaches the blank label row or any table source row, the render callback switches to
a row-local layout: every header, delimiter, and body source row owns a stable semantic overlay and
continuation extmark. Only the active row exposes raw source; changing rows updates the old and new
row decorations without moving a table-wide virtual block. The renderer uses its supported
one-millisecond event throttle, stages the complete next decoration set, and reconciles by semantic
extmark key plus structural equality. Unchanged rows are not submitted to Neovim again; only the old
and new active-row specifications can change. The namespace is therefore neither cleared nor
structurally rebuilt between rows. Full
clearing remains owned by the plugin's parse/disable/teardown lifecycle.

Raw source and rendered cell wrapping can otherwise occupy different screen-line counts. The
row-local interaction zone temporarily disables window soft wrapping and replaces the active row's
rendered continuations with background-only height reservations. Each row retains the same total
height through blank → header → delimiter → body focus transitions; leaving the interaction zone
restores ordinary rendered Markdown wrapping. The `󰈙 table` label independently overlays the blank
source line immediately before the table, so it adds no vertical margin. Tables without that
predecessor retain a fixed virtual-line fallback. Because
Neovim does not populate the number column for virtual lines, each source-backed render group carries
its original row and reproduces the window's absolute or relative number in the gutter; continuation
and decorative lines remain unnumbered. The source and virtual rows share the
subdued background of a fenced `text` block, a separate `󰈙 table` label precedes the header, and the
two rules use a foreground dimmer than ordinary text.

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

- Python, C/C++/CUDA, Lua, Shell, and Vim script participate in each query.
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

`config.git` exposes exactly three history scopes and delegates them to one
`config.git.diffview` renderer. FILE resolves only its path, SYMBOL resolves its cursor structure
through Neovim's cooperative parser callback, and REPOSITORY resolves only its root:

```text
<Space>df → file path + --follow commit selector ─────┐
<Space>ds → cursor structure + line-trace selector ──├→ bounded FileHistory → bottom list + two code panes
<Space>dr → repository root ───────────────┘
<Space>de → standalone branch/commit/issue dispatcher ── selection → FileHistory route
```

Diffview supplies expandable changed-file rows, syntax-aware historical buffers, line jumps, and
the horizontal two-way layout. `config.git.footer_loader` supplies a shared two-level demand model
for `<Space>de/df/ds/dr`: lightweight Git commit metadata is fetched in 200-row batches and retained
in a sliding 600-row list window. The first batch mounts before the rest of the current window fills
asynchronously in branch order, and its changed-file children begin hydrating from the top at the
same boundary. Background workers claim configured eight-commit batches and use paired Git streams
whose record separators preserve commit ownership; unsupported or malformed records fall back to the
single-commit Diffview path. The four-worker pool reserves one slot for an explicit action and uses
the others for background preload.
Cursor movement within the window does not replace or reprioritize that queue. `config.user` reads an optional user-level `~/.nvim` Lua table and `config.git.settings`
validates bounded overrides before the repository/loader modules consume them. Its history panel starts at ten lines at the bottom;
the first native frame focuses that panel and reports HEAD metadata and history-list work as separate
view-owned async activities. HEAD resolution runs after the panel mount and alongside Diffview's
bounded list stream; attached HEAD metadata hydrates the mounted view in place, while the uncommon
unmatched detached-HEAD route replaces it with the exact commit range. Diffview is warmed on
`VeryLazy` so normal interactive entry does not pay its module-load cost.
Normal Diffview selection changes the code shown above. `<Tab>` and `<S-Tab>` are replaced in every
main pane with window-focus traversal, preventing the list binding from advancing commits. Ordinary
initial scopes mount one native seed entry, then replace it with the first preloaded metadata batch
before asynchronously filling the retained window. Cursor movement within 30 rows of either margin fetches the adjacent metadata batch and
fills any unused list capacity in the same request. It preserves entry identity across the bounded
redraw, so direct Ex jumps such as `:180` do not bounce to a different commit. A search-selected local
or remote commit first checks containment against the attached checked-out branch. A contained target
resolves its branch offset and preloads the first 200-row metadata batch before the replacement view
mounts, reserving older context while giving recent branch commits priority. An uncontained target
is pinned as an independent preview-only footer row above the checked-out branch history, avoiding
an unrelated `<commit>^!` Diffview scope. A failed branch preload, or one whose
parsed rows omit the target, takes the same exact-object fallback. During history initialization, a
view-owned activation guard marks Diffview's implicit streaming selection inactive in
`file_open_pre` and temporarily nulls its revision files, so the plugin's required initial selection
does not read or parse a large historical blob. `file_open_post` restores those reusable file
objects; the settled list boundary retires the inactive selection
onto the native null layout. This lifecycle state stays inside
`config.git.diffview`; it does not replace Diffview's renderer, override plugin methods, or create
another navigation layer. Once a file is
explicitly opened, its selected commit compares its
parent on the left (`BEFORE`) with the commit on the right (`AFTER`); explicit winbars show both roles
and revisions before the lower-priority file path, without redundant physical-side labels. The
workflow only reads local Git state and performs no implicit fetch.
File and symbol histories preserve the single-file/line-trace query as a commit selector. The footer
mounts from lightweight matching commit rows, then waits for the initially selected commit's complete
children and matched revision buffers before reporting ready. The shared loader hydrates complete
children across the retained list window in stable top-to-bottom order, using three background
workers and reserving the fourth for an explicit action by default. A reused native seed remains incomplete until this loader
replaces its possibly partial file list. Detail redraws preserve an explicitly active child through
Diffview's native file highlight; otherwise they restore the footer commit by hash rather than row
index. Diffview's native selection action owns commit expansion, collapse, and child-file opening.
No scope performs an automatic matched-child jump. An explicit child selection renders
the file. Every expanded
row adds a plain right-pinned `MATCH · FILE/SYMBOL` tag to its scoped file
(including its rename alias), so every result retains its own target rather than only the active
entry. Commit reference tips also add non-displacing virtual branch separators. The footer winbar
keeps current checkout state and appends the branch segment under the footer cursor. A second plain
virtual line consistently carries complete review and scope metadata instead of being displaced by
branch pinning. Moving the list boundary cancels child work that fell outside the retained window.
FILE and SYMBOL preload matched revision buffers sequentially within each bounded detail worker;
repository history creates them only when a child is explicitly opened. The loader never starts a
fetch. Hidden revision buffers do not attach Tree-sitter until Diffview displays them.
SYMBOL clears Diffview's `-L` patch folds so opened code uses the
ordinary full-file fold strategy without adding a declaration jump. The adaptive metadata line adds
the FILE path or the SYMBOL label, path, and traced line range. Initial history resolution records the
exact current local ref, so the winbar leads with `CURRENT BRANCH` when HEAD is attached.
Repository and branch history use the same idle render boundary, but expanding a commit only reveals
its children; a file row must be opened explicitly before either code pane renders.
Detached status parsing never retains Git's literal `(detached)` sentinel as a branch name, so the
winbar and selected commit row consistently expose `CURRENT · DETACHED` and `DETACHED HEAD`. A
fresh detached entry performs one exact `--points-at` ref lookup. An exact local tip becomes its
read-only branch context before any remote-tracking tip; without an exact branch tip, the entry uses
`commit^!` semantics. It never infers ownership from broader containment.
`<Space>dp` calls the history panel's reversible toggle from either code pane or the list, preserving
the panel contents, selected commit, and configured restored height.
`<Space>dn` is footer-local and opens Diffview's native selected-commit detail panel. It is read-only,
and `<C-q>` closes that detail before the history layer.
Diffview revision buffers opt out of the editor-wide current-scope extmarks but retain the editor's
real pinned Tree-sitter context inside the focused code pane. The pinned source lines use a shared
restrained light-green declaration background with a distinct brighter-green lower boundary. The
remaining code render is reduced to syntax
foregrounds, one ordinary cursor-line background, and Diffview's add/change/delete backgrounds.
Render completion synchronizes Tree-sitter independently for both Diffview file buffers rather than
depending on which pane happened to receive the last `FileType` or window-enter event.
No history render performs an automatic declaration lookup, fold reveal, or cursor jump. Diffview's
native selection position remains authoritative, keeping Tree-sitter parsing out of the input path.
`<Space>fw` keeps its global project-definition-search role in Diffview and the editor. Git mode does
not install a buffer-local override, and return staging removes any stale historical-search mapping
before the working buffer becomes visible.

The Git workflow is an isolated subsystem around Diffview. Editor entry points call `config.git`,
while renderer callbacks, enrichment tokens, and transition phases remain private. The only public
callback boundary is `config.git.on(...)`, backed by `config.git.events`, which asynchronously
publishes stable `phase`, `ready`,
`return_started`, `editor_rendered`, `return_finished`, and `anchor_finished` events. Consumers do
not subscribe to raw Diffview callbacks or mutate lifecycle state. Event payloads contain only
generation, kind, phase, outcome, detail, and path metadata—never Diffview view/window objects.

The complete tab is one lifecycle unit. Each mounted history receives a monotonically increasing
generation and moves through explicit mounting/listing/enriching/rendering/ready/returning/closing/
disposed phases, with `failed` as an explicit terminal work state. Every asynchronous
callback checks both its view generation and render
sequence, so a replaced view cannot redraw, jump, or complete a newer operation. Buffer-local
`<C-q>` mappings are installed after every
layout pass, and command submission rejects interactive `:q`/`:quit` while the view is active
without interfering with Diffview's internal window replacement. The ordinary-history
`<C-q>` layer callback is accepted at every lifecycle phase. An idle history has a stable
null-layout readiness marker and returns to the untouched editor state. A history with an explicitly
opened file instead resolves only the currently selected `AFTER` file. A whole-view close cancels configuration-owned footer enrichment and focuses the editing
tab immediately while Diffview shuts down its own history stream and disposes the view
asynchronously. Before the tab switch, the return looks for the target file in the preserved editor
tab. It reuses that file's existing editor window when present; otherwise it loads the buffer hidden
and stages it in the editor's current window while Git remains visible. The switch therefore exposes
only the Git pane and the final editor pane, never an old or scratch intermediary. No historical
cursor position is captured or applied.
Lualine branch state is resolved inside the staged editor window before the tab becomes visible;
the first editor frame therefore includes the checked-out branch without relying on a subsequent
Telescope or `BufEnter` transition.
Because Diffview teardown can update lualine's active-buffer cache, disposal completion reasserts the
branch from the still-current staged editor window and redraws the statusline. The final Git-footer
state briefly displays `RETURN · restoring editor` before the immediate tab transition without
emitting a user notification.
Staging can trigger Diffview buffer hooks on the working-tree buffer. After the final buffer is
installed in the preserved editor window, return cleanup removes only mappings whose key and
description identify them as Git-owned. This happens before the first editor redraw, restoring the
global `<Space>de`/`<Space>fw` actions without deleting unrelated editor-local mappings.
Repository-search re-entry during the remaining disposal interval is stored as one keyed settled
action. Final view disposal releases it once, preserving the history-plus-search pipeline without a
polling loop or duplicate transition.
An exit at any phase cancels configuration-owned work and returns immediately. It routes a known
historical file when one exists and otherwise restores the untouched editor state; Diffview disposal
continues asynchronously after the editor is usable.
List, warm-up, or selected-render timeouts enter `failed`, retire their render callback once, and
still accept `<C-q>` so an asynchronous failure cannot trap the user in Git mode.
Return navigation performs no Tree-sitter, LSP, Telescope, Git lookup, or cursor placement; an
absent working-tree file falls back to the untouched editor state.
An idle history with no explicit file selection takes that untouched-state path directly, preserving
the editor's existing tab, window, buffer, cursor, folds, and viewport.
Footer position never participates in the target. `<Space>o` remains the ordinary jumplist-back
operation in every Git pane. Shared Telescope/Diffview highlights keep the list and code planes
visually consistent with the editor. They derive their base background and
foreground from `Normal`, use the editor `CursorLine` background for Telescope results and Diffview
footer selection, and use neutral grey edges plus bold near-white matches/carets. Within that shared
plane, the footer uses the established saturated semantic foregrounds for add/change/delete status,
counts, and hashes. Diff highlights assign background tints only, preserving syntax foregrounds on
both added and deleted lines.

Git search can be a standalone editor layer or a temporary layer above ordinary Git history. Global
`<Space>de` resolves the current workspace repository and opens the dispatcher without mounting
Diffview. `<Space>dr` passes through the same repository gate and mounts repository history
immediately. Selecting a standalone branch or commit opens Git mode directly at that review route;
selecting an issue opens its Markdown detail directly over the editor and does not mount Diffview.
The same buffer-local
`<Space>de` reopens search from Git mode, where the history view retains its commit/file panel,
selected entry, checkout, and split layout while the picker is active. Buffer-local
`<Space>de` opens `config.git.search` directly from view-owned repository/options state, including
the mount interval before Diffview assigns its panel object, as a Telescope prompt, result list, and preview; there
is no preceding footer input and `<C-b>` is not mapped in Git mode. Git search
inherits the branch view's repository/file/symbol scope and caps candidates at 50.

An exact `#<digits>` query sends a digit-boundary regexp to Git, then applies a subject-only check so
body matches and longer references cannot leak into the picker. Git is queried first across locally
available `--branches` and `--remotes`; `%S` source metadata groups each commit beneath its owning
local or remote-tracking branch. Known branches and the GitHub issue are root records.
Local branch and commit records are emitted as soon as the Git queries finish. Exact-number lookup
keeps that finder generation open and appends its issue or remote-error root when the GitHub request
finishes, so remote latency cannot leave the initial branch list in place or make local matches
unselectable. A changed prompt cancels both phases and rejects late records from the older query.
The preview renderer dispatches by level: branch to aligned commit rows with nested files, commit to
a structured changed-file list, and issue to Markdown. Repository parsing consumes machine-delimited
Git metadata before the UI boundary, so raw `git log` and `git show` output never becomes the preview.
Source, kind, branch/hash, date, and title columns have stable widths and semantic highlights.
`<Tab>` focuses the preview and `<CR>` performs the selected branch or commit action at the cursor.
Focused previews enable the normal editor `CursorLine` background so cursor position remains visible.
An unmapped branch-preview header never dispatches an action. Branch result rows and preview
commit/file rows both open read-only review; only their selected ref or commit differs.
An immediate hexadecimal commit-ID result is canonicalized asynchronously with `git rev-parse`
before it crosses from search into history, so Diffview never compares an abbreviation to full hashes.

Selecting a commit is a read-only review operation: it leaves HEAD and the working tree untouched.
If the target exists in the mounted FileHistoryView, the renderer preserves that complete ordered
history and marks the commit in place without opening a file. Otherwise it uses a bounded
current-branch metadata window only when that branch contains the target; an uncontained target is
pinned as one independent preview-only footer row and selected after Diffview has populated the
panel. No configuration-owned highlight or bold styling is applied to its title. A settled render
callback focuses that row by hash after the final list replacement. The actual branch tip therefore keeps its native `HEAD`
reference. Its panel winbar renders source and branch directly above the list, and both code panes
remain empty until a file child is opened. An empty commit retains the complete list and the same
blank code area. A replacement view is mounted before the prior history
view is disposed and remains the ordinary Git layer rather than a disposable search layer.
Footer structural annotations use a generation-checked coalesced post-render pass; commit titles
remain entirely owned by Diffview's renderer.
The configuration does not override `DiffviewFilePanelSelected` or `DiffviewCursorLine`; Diffview
and the active colorscheme own selected-row weight, foreground, and background.
Native fold renders do not trigger a configuration-owned `TextChanged` redraw or cursor restoration;
expand and collapse therefore remain a single Diffview render.
The native one-row Diffview seed is not a selection-ready boundary: target focus waits for the
footer loader's metadata window to settle before deciding that the requested hash is absent.
Render options and dispatcher options are stored separately, so reopening `<Space>de` searches repository
history rather than restricting grep to the displayed branch range.
Selecting an issue from Git mode creates a centered read-only Markdown float over the untouched
parent Diffview instead of entering either split. A standalone selection creates that same detail
over the preserved editor, without constructing a Git-history layer. Normal and Visual editor
operations remain available, including selection and yank. `q` and `<Space>de` close that float and
reconstruct the cached result picker. Related issue navigation stays
inside the Markdown buffer, and `o`/`gx` delegates to the shared asynchronous external opener. This boundary requires no
instance method replacement, renderer suspension, or split recovery. Issue rendering installs the
same URL action in Telescope previews and detail buffers, so it opens the structured issue URL once
instead of delegating to Neovim's generic Markdown URL extraction. The detached opener is not waited
on because WSL `explorer.exe` can return a nonzero status after successfully handing the URL to
Windows; synchronous handler-discovery failures remain visible. Global Normal and Visual `gx` use
the same compatibility layer. It resolves rendered Markdown labels before falling back to Neovim's
cursor and selection target discovery, so concealed destinations remain reachable. GitHub
`/issues/<number>` and `/pull/<number>` targets first resolve through the same provider and open the
same detail float; failure falls back to the asynchronous browser handoff. Direct PR resolution
carries its resource kind through the public-page fallback, preserving `/pull/` and the shared
body-and-discussion renderer. Local
file targets resolve from the current buffer and ask in the command-line footer whether to use the
current window, a vertical split, a horizontal split, or cancel. Targets within the source project
follow the ordinary file lifecycle. Cross-project targets suppress `FileType` consumers during the
open and start only Tree-sitter highlighting, preventing an unrelated workspace index from starting.
Same-project targets always follow the ordinary `FileType` and LSP lifecycle, including split opens;
lightweight external rendering is silent. Issues and pull requests use this
same renderer: the canonical URL is part of the top metadata card, and the complete available body
is followed by the shared conversation-comment pipeline. GitHub metadata normalizes CRLF and lone
carriage returns before it crosses into the renderer. The float rejects `<Tab>` so it cannot escape
into the underlying layout. Tree-sitter Markdown parsing is synchronized after each render so the
active section title uses the shared pinned-context surface; heading folds start open and remain
controllable through ordinary fold commands such as `za`, `zc`, and `zo`.

Git refs retain Git's configured transport and therefore reuse SSH configuration naturally. GitHub
issue scope is resolved from machine-readable local remote configuration: supported repositories
are deduplicated and attempted sequentially in `origin`, `upstream`, then remaining-remotes order.
`config.git.reference` normalizes direct issue/PR URLs, Git remote URLs, local repository paths, and
the bounded `git config` output into the same structured record reference before `github.lua`
performs network acquisition and `issue.lua` renders the result.
This lets a fork miss an issue before its upstream supplies it. Each candidate first uses an
authenticated `gh api` request when GitHub CLI is available, then REST (authenticated when a token is
available). Direct PR references use the PR endpoint so merged state and complete PR metadata remain
available. A failed or rate-limited REST request falls back to embedded React or schema.org page
records, with Open Graph metadata last. Public-page transport has bounded connection/transfer times
and retries transient failures. Conversation comments use the
same authenticated GitHub CLI when available, otherwise a bounded REST request retrieves up to 100
comments; failure to enrich discussion does not discard an already resolved issue or pull request.
SSH Git authorization remains owned by Git and is never extracted as an HTTP
credential. GitHub issue and pull-request metadata receives the shared proxy environment explicitly.
The Markdown detail preserves the complete available body and ordinary `j`/`k` and page scrolling.
An HTTP 404 is a structured absent result rather than a provider error. If every configured remote
confirms absence, no remote row is emitted for that exact-number query. Connectivity, parsing, and
authorization failures still become one visible `REMOTE ERROR` root record containing per-repository
details and are not cached, so changing `:Proxy` or adding `GH_TOKEN` can be retried immediately.
Tokens travel to curl through stdin headers.

`config.git.panel` models the durable workflow as
`editor ← ordinary Git history ← temporary search`, while allowing standalone search and issue-detail
layers directly above the editor. Search results/preview and issue detail are alternate renderers of
the same search layer, not separately nested modes. Standalone branch and commit results enter
ordinary Git history; standalone issue/PR results remain editor-owned. Commit and branch choices from
an existing view replace history in place without changing Git HEAD. Every
Git surface routes `<C-q>` through one pop operation: an in-mode search renderer returns to the
preserved history Diffview, a standalone search/detail returns to the editor, and ordinary history
returns to the normal editing tab. A rendered-file return captures the
rendered `AFTER` scope's declaration line and relative cursor offset, restores and redraws the editor
buffer, then asynchronously performs one in-buffer working-tree match. It reapplies the relative
offset to a match, falls back to the rendered line when the declaration is absent or ambiguous, and
refreshes lualine's checked-out branch state as part of editor restoration.
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
The resulting history view retains the detached commit hash as structured view state. Diffview's
existing reference renderer adds a highlighted `(DETACHED HEAD)` tag only to that commit row, and
the footer winbar presents `CURRENT · DETACHED`, the reviewed branch, and its separately resolved
`TIP` as three facts. The replacement history uses the prepared full ref rather than a short name,
so commits between the selected anchor and the reviewed branch tip are present in the same render
cycle instead of appearing only after another branch review. Anchor replacement preloads a bounded
200-row metadata window around the target; it does not ask Diffview to render the complete ref.
Detached checkout always replaces the mounted history from current Git state, even when the target
commit was already present. This refresh removes stale pre-checkout `HEAD -> branch` decorations
before selecting and marking the detached commit. Read-only commit review may still focus an
already-mounted row without rebuilding the list.
The mutation transition remains active through replacement rendering, not merely through
`git switch`. The old view cancels optional enrichment immediately but retains its Diffview-owned
buffers until the replacement emits a completed target-file render; only then is the old view
disposed. This prevents teardown from deleting a same-named buffer while the new view is awaiting
historical file content. Inside the successor, the idle list boundary must settle before the explicit
selected-anchor render starts; this serial handoff prevents Diffview from invalidating
its own in-flight buffer. If the selected row is still a lightweight placeholder, its detail load is
promoted ahead of nearby background work and code rendering begins only after the real child files
replace that placeholder. The footer exposes the current `ANCHOR` stage. Concise start/completion
notices go to `:messages`, while every resolve/status/ref/switch/render stage records its elapsed time
under `[Git anchor]` in Diffview's existing `:DiffviewLog` file. A failed or expired render unlocks
the transition with a warning that distinguishes completed HEAD mutation from incomplete rendering.
If detached HEAD and the selected commit equal the tip of a containing local branch, the explicit
`<Space>dm` mutation attaches that branch and rebuilds decorations; remote-only refs never create an
implicit local branch.
Each branch review also owns a prepared anchor plan with its exact ref, local/remote source, and tip
hash. `<Space>dm` consumes that plan directly and never performs a whole-ref containment search.
It still resolves the selected object, checks live porcelain-v2 dirty/HEAD state, and re-verifies a
local tip immediately before attaching it. Context-free callers use the exact commit. File, symbol,
repository, and branch reviews preserve an explicit provenance ref through their current view; a
later detached entry may recover a branch only by exact tip identity, never by graph reachability.

Branch selection is a read-only ref transition. It mounts `refs/heads/...` or the locally available
`refs/remotes/...` history before retiring the old view; it never fetches, creates a tracking branch,
or invokes `git switch`. The footer labels this as `BRANCH REVIEW` and separately exposes the actual
attached branch or detached hash. The dispatcher resolves branch containment only while branch
selection is active and stably ranks exact-tip local refs, containing local refs, exact-tip remote
refs, containing remote refs, unrelated local refs, then unrelated remote refs. For detached HEAD,
an ancestry check against the selected ref retains and selects that commit when contained; the list
preloads a bounded window around that commit so the anchor cannot fall outside the rendered range.
If it is not contained, the selected branch still opens normally. Dirty buffers and worktrees remain
valid review inputs. `<Space>dm` remains the only Git-mode action that changes the real commit anchor
and owns the mutation guard.

## Shared Network Proxy

`config.network.proxy` recognizes lowercase and uppercase proxy variables, direct `IP:port` values,
and `no_proxy` bypass lists. Process environment values take precedence; missing values are filled by
statically parsing simple assignments and variable references in `~/.bashrc`. No shell code is
executed. Discovery supplies selectable proxy information, but startup clears inherited proxy
variables before lazy.nvim can contact GitHub, then restores the last explicit `:Proxy` choice from
a versioned state file. With no valid saved state, startup remains direct and no proxy endpoint is
active by default. A `:Proxy` selection becomes the active override for subsequent GitHub,
translation, Git, and plugin child processes and is atomically persisted with user-only file
permissions. Direct mode is also persisted, so shell discovery can never silently reactivate a
proxy on the next launch. Invalid state is ignored with a warning and a safe direct fallback.

`config.network.ui` exposes the same state exclusively through `:Proxy`. Its Telescope list groups
effective routes by compact `host:port`
parents and renders the contributing HTTP, HTTPS, or ALL_PROXY fallback routes as child details. Its
centered layout is capped at 72 columns by 16 lines rather than inheriting the project-search scale.
The leading rows reduce state to `PROXY ON/OFF` and `NO_PROXY ON/OFF`; grouping uses the sanitized
endpoint rather than the URL scheme, so one endpoint cannot appear as several active proxies.
The prompt also accepts `proxy | no_proxy`, allowing one input path to update both fields. The active override is
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
Python cd/cb/ci  → empty picker → on-demand AST scan → in-memory graph query
```

`core.lua` supplies the shared picker plumbing and the recursive-walk bookkeeping
(deduplication, pending-request tracking, depth-sorted publication) used by both the clangd
hierarchy walk and the Python definition-request fallback.

Each path creates the empty picker first. Recursive C++ responses refresh it incrementally, and the
picker session owns cancellation for both initial and descendant requests.

For C++, clangd supplies standard Type Hierarchy nodes, which are deduplicated by URI, name, and
source range before recursive expansion. BasedPyright does not expose that protocol, so
`config.python.hierarchy_index` starts a background standard-library AST scan only when an explicit
Python hierarchy action first needs it. Ordinary `FileType` events—and especially generated
historical buffers—never launch project-wide indexing. It resolves local imports and aliases,
records positioned base-class references, builds
parent/child and method maps, excludes virtual
environments and build outputs during directory traversal, and serves queries from memory. A save
refreshes only an already-created index while the previous complete snapshot remains queryable. LSP requests
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
