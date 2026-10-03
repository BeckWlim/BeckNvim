# BeckNvim Architecture

The repository separates startup assembly, reusable feature modules, and plugin declarations.

```text
init.lua
lua/
├── config/                       Reusable, testable feature modules, grouped by area
│   ├── init.lua                  Startup assembly
│   ├── project.lua               Project-root authority and path containment
│   ├── navigation.lua            Shared pane selection, file opens, closing, and native history
│   ├── state.lua                 Shared preference storage and scoped session documents
│   ├── storage/                  Replaceable memory and SQLite document backends
│   ├── startup/                  options.lua, autocmds.lua, lazy.lua, keybindings.lua
│   ├── ui/                       window_state.lua, float.lua, folder_picker.lua, dashboard.lua,
│   │                             statusline.lua, filetree.lua, terminal.lua, theme.lua, palette.lua
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
| `config/project.lua` | Project-root authority, activation gate, path containment, markers, and cached Git-host detection |
| `config/state.lua` | Shared storage API, replaceable memory/SQLite backends, namespaced global/project persistence, process-local session documents, JSON migration, and asynchronous writes |
| `config/storage/document.lua` | Versioned JSON validation shared by storage backends |
| `config/storage/memory.lua` | Process-local storage backend |
| `config/storage/sqlite.lua` | Low-level SQLite C API boundary shared by the main VM and libuv workers |
| `config/storage/sqlite_store.lua` | Replaceable long-term SQLite storage backend, migrations, async workers, and writes |
| `config/startup/logs.lua` | Direct native/plugin log destinations under the log subfolder |
| `config/startup/` | Editor options, global autocmds, lazy.nvim bootstrap, and the single keymap assembly |
| `config/ui/window_state.lua` | Window-owned editor intent and surface-option delivery, native transition reconciliation, live split proportions, and opt-in panel size memory |
| `config/navigation.lua` | Shared launch context, native file/buffer opens and jump history, cancellable editor-pane selection, and owner-aware closing |
| `config/navigation/write_guard.lua` | Optional transition boundary asking y/n to write unsaved destination contents before replacement |
| `config/ui/statusline.lua` | Explicit project identity and project-relative current-file state |
| `config/ui/theme.lua` | Theme selection, Telescope preview/rollback, and preference validation through shared storage |
| `config/ui/palette.lua` | Shared semantic palette resolved from the selected colorscheme, light/dark fallbacks, contrast, and background tints |
| `config/ui/tmux.lua` | Asynchronous pane palette publication through tmux's application hook and editor owner lifecycle |
| `config/ui/dashboard.lua` | Bounded project drawer, project-relative MRU state, and dashboard actions |
| `config/ui/folder_picker.lua` | Telescope project switching, bounded system-folder search, and asynchronous file-tree previews |
| `config/ui/filetree.lua` | Nvim-tree mappings, authoritative root synchronization, window-switching Tab preservation, and project-boundary confirmation |
| `config/ui/open_target.lua` | Shared URL routing/handoff and local-file target resolution into the navigation manager |
| `config/ui/terminal.lua` | ToggleTerm-local escape to Normal mode and registered editor-facing window options |
| `config/ui/float.lua` | Shared close-key and background-focus lock policy for ordinary floating dialogs |
| `config/search/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/search/query_picker.lua` | Empty-first Telescope lifecycle, incremental refresh, status, and cancellation |
| `config/search/lsp_locations.lua` | Cancellable LSP definition, declaration, reference, type, and implementation queries |
| `config/search/grep_preview.lua` | Telescope grep/LSP location preview loading, highlighting, and structural winbar context |
| `config/search/telescope.lua` | Telescope defaults, extensions, and previewer wiring |
| `config/search/navigation.lua` | Go-to-referenced-file jumps from prose and code |
| `config/git/init.lua` | File, symbol, and repository history entry points plus safe branch switching |
| `config/git/graph.lua` | Repository graph, commit-message preview, optional branch pane, and guarded switch/fetch actions |
| `config/git/session.lua` | Repository view snapshots through the shared memory-only session store |
| `config/git/diffview.lua` | Shared bounded history workspace, lifecycle, layout, and pane keymaps |
| `config/git/lifecycle.lua` | Generation-checked Git render/return/anchor state machine and structured diagnostics |
| `config/git/events.lua` | Asynchronous public event port between the Git subsystem and editor-owned consumers |
| `config/git/github.lua` | Cancellable read-only GitHub issue/PR acquisition and discussion-enrichment boundary |
| `config/git/issue.lua` | Exact-number and direct-URL integration, shared issue/PR rendering, and related navigation |
| `config/git/reference.lua` | Unified local-path, direct-URL, Git-remote, and Git-command-output parser for structured GitHub record references |
| `config/git/panel.lua` | Git history and temporary search layer bookkeeping |
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

`config.startup.autocmds` clears each window's restored jumplist once at `VimEnter`, after ShaDa
has loaded. Back/forward navigation therefore starts with the current Neovim process, including
windows opened with startup split arguments. ShaDa still preserves recent files, file marks,
registers, and search history; ordinary navigation continues to use native window-local jumplists.

`config.ui.window_state` remembers nested split proportions per tab during the current session.
Replacing files keeps pane sizes; opening or closing splits uses Neovim's default equal-size
policy. Each topology change replaces the in-memory layout snapshot; reopening a split does not
restore proportions from a previous layout. Terminal resizing scales the current live layout,
with hidden tabs restored when entered.
Manual resizing and explicit equalization establish new proportions. Floats are excluded, and
changed split topology is adopted rather than reconstructing closed windows.
`capture_layout()` gives each file-opening session a restore callback for its native split
proportions. Definition, file, grep, buffer, diagnostic, document-symbol, and shared LSP/type pickers capture it before opening
temporary panes; closing the picker and replacing a file restore it after plugin callbacks.
Restoration requires the same tab, window topology, and editor dimensions, so explicit splits,
closed panes, and terminal resizing retain their native behavior. Ordinary selection changes only
the launch editor's file view; panel-origin selection retains its existing destination policy.
Panels can use `panel_size(filetype, axis, default_size)` in their native size callback and call
`track_panel(winid)` after opening. Nvim-tree uses this shared memory to restore its width after
closing and reopening, including terminal resizing while hidden; its initial width is 30 columns.
`prepare_panel(filetype, axis)` preloads the saved preference asynchronously. Registered panels
persist their last adjusted ratio through `config.state`, so new tabs and later Neovim processes
inherit it; existing tabs retain their own overrides. A late startup read only adjusts an untouched
panel. Window IDs and complete split layouts stay in memory.
The same owner separates underlying editor options from temporary surface presentation.
`register(filetype, resolver, presentation)` declares a surface's editor fallback and optional
display overrides; `resolve(winid)` reads editor intent and `apply(winid, editor_options)` delivers
options with explicit window-local scope, preserving defaults for later windows. `file_buffer(winid)`
resolves a rendered Markdown pane to its real source buffer for destination selection, unsaved-change
checks, unused-buffer disposal, and statusline identity. Context snapshots
belong to each window and its displayed buffer/filetype. `WinNew` inherits intent from the source
window before Neovim replaces the copied buffer; `BufEnter`, `BufWinEnter`, `WinEnter`, and `FileType`
reconcile the actual target, restoring editor intent before applying the next registered surface.
`FileType` reconciles every view of the buffer, and `WinClosed` releases its snapshot. Ordinary editor
windows retain local changes; native horizontal, vertical, empty, and tab splits use this pipeline
without depending on the file-opening adapter. Floats do not inherit tiled-surface context.
NvimTree registers its underlying editor line-number settings with `window_state`, using the
same resolver contract as the dashboard. `config.navigation` owns file-opening and history policy:
an editor or dashboard opens in its own pane; a panel uses the sole eligible editor or asks through
transient a/b/c badges when several remain. The shared layer owns the letter picker, its buffer-local
keys, and teardown; it does not replace NvimTree's renderer or depend on its private picker.
Local-file `gx` requests destination selection even from an editor, replacing the selected existing
pane through the same guards. It offers no split strategy menu. `focus_window()` reuses the badge
renderer for `<Space>ww`, with all native tiled windows eligible, including panels and `winfixbuf`
editors; it changes focus without opening files. Cancellation restores launch focus.
Floats, special buffers, and `winfixbuf` panes are excluded
from destinations. Rendered Markdown remains an eligible editor through its underlying source;
ordinary tree selection replaces it in the existing pane, and only explicit split commands add
panes when an editor is available. Moving to another file uses the renderer's native leave/enter
lifecycle, retaining the generated buffer for native jump history and restoring pane presentation.
Explicitly reopening the current source calls the renderer's public `leave_preview()` API after
transition boundaries permit the operation. With no eligible editor, the open
layer creates one with resolved editor options. Requests
are scoped to a tab and reject superseded choices, changed sources, and replaced destination
buffers. A replacement unlists the previous ordinary file buffer only after a successful open
and when no window still displays it. Its hidden identity remains available to native jump history,
including search and file-picker navigation. Native
guards still apply to all other operations. Existing files in
another pane do not override the chosen destination. Only terminal resizing reuses live ratios;
file replacement preserves sizes and explicit splits adopt the default equal-size policy.
The tree adapts file-selection and split keys while NvimTree retains directory actions. Telescope
adapts its native file action set for file/buffer/grep, project definition, LSP location, and type
hierarchy pickers; custom theme, project, historical-buffer, and Git choices retain their owners.
Tree opens retain tree focus; file-result pickers focus the chosen editor. `capture()` returns a
shared navigation context containing the launch window, displayed buffer, tab, and proportion
restore callback. File/definition pickers and shared LSP/type sessions capture this context before
creating temporary windows and pass it to `open()` after teardown. A changed source buffer or tab
invalidates the context before any file mutation. Global file-picker
shortcuts capture their launch window before creating a picker; preview
focus and Telescope's return-window changes cannot reclassify a panel-origin open. Prompt and
preview Enter retain the same explicit split intent for `<Space>fv` and `<Space>bv`.
File results resolve against the picker's root before teardown. The open layer reconciles Normal
mode on the next loop turn when closing a prompt has already emitted `ModeChanged`.
`jump()`, `back()`, and `forward()` use native window-local jumplists, including `/` searches and
file/symbol navigation, and preserve live split proportions. Counts and the selected pane remain
native; a file already visible elsewhere does not redirect history. `<Space>o` and `<Space>p`
dispatch through this manager. There is no additional history store.
`register_boundary(name, callback)` is the manager's optional policy extension point; it returns
an unregister function and passes the transition's action, destination window, underlying file,
and target buffer. A veto cancels before the view or jump index changes. The manager contains no
save-question UI. Startup enables `config.navigation.write_guard`, which asks the native y/n
“Write this file now?” question for unwritten destinations. Yes performs a normal write before
continuing; No, write errors, and stale view/content choices abort the transition. The extension
protects both file replacement and cross-file native history, including rendered Markdown sources
and files displayed in several panes. Same-file cursor jumps and explicit splits do not replace
the protected view. There is no discard action or additional decision picker.
Dashboard and local `gx` file actions use the same native open layer. Local links retain their
lightweight syntax policy; a command wrapper applies that policy only after
the manager's destination and unsaved-change guards. Referenced-file LSP navigation uses the shared
location picker. Interactive `:e file` from NvimTree or a
terminal uses the same destination policy;
the command-line Enter adapter preserves parsed native command modifiers and dirty-buffer checks.
Editor-origin `:e file` keeps current-pane targeting and uses the same replacement guard.
Programmatic and chained Ex commands and other plugin-owned panels remain native.
Git's existing command-line
dispatcher delegates non-quit input to this adapter, preserving whole-mode Git quit behavior.
ToggleTerm registers the underlying editor line-number defaults for creating an editor from a
terminal. Terminal buffers remain excluded from destinations; cancelling selection returns to
terminal Normal mode after ToggleTerm's scheduled mode restoration.
`<Space>wq` delegates registered panel/picker/detail cleanup to its owner and otherwise closes the
current file pane without deleting its buffer. Native `:q` closes only the focused ordinary pane,
including the last editor beside a tree; it leaves other panes and tabs open. UI adapters are
released on buffer wipeout. Telescope closes its entire picker, preserving lower UI layers.
Diffview's existing code panes and history footer use the same split tracking when selecting files
and resizing the terminal. Diffview retains ownership of panel toggles and rebuilt layouts.

## Shared State Storage

Feature modules open small document stores with `require('config.state').open(namespace, options)`.
The default `memory` backend is process-scoped and never writes files; global and project stores
default to the long-term `sqlite` backend. A consumer can select `backend = 'memory'` explicitly,
or replace/register a backend with `config.state.register_backend(name, backend)`. Backends store
encoded JSON and implement synchronous/asynchronous read and write plus `when_idle`; this keeps
SQLite behind one replaceable boundary rather than making plugins depend on its C API.
Global and project scopes share `<stdpath('state')>/state.db`. Records use a key containing scope,
project-root hash, and namespace; the payload is a versioned JSON object inside SQLite.
Project scope requires an absolute `project_root` supplied by `config.project`.
Session scope uses an optional `session_id` to isolate Lua memory documents and never writes files.
Git graph/detail snapshots use `git-view` in session scope, with the normalized repository root as
the session ID. View owners capture selection, scope, dimensions, and focus before teardown and
restore them after native data loading. Snapshots exclude Git contents, jobs, and window handles;
the repository entry point resumes them only within the current Neovim process.
Storage does not detect projects or take ownership of feature lifecycles.
If the SQLite shared library cannot load, SQLite-backed scopes use isolated Lua memory for this process.
Startup warns once, existing database/JSON files remain untouched, and setting changes are transient.
`persistent_available()` exposes this capability without requiring consumers to load SQLite.

`store:read(callback)` returns a cancellation function and delivers on the main loop.
`store:write(document)` validates encoding and queues an asynchronous save;
`store:when_idle(callback)` subscribes to completion without polling. Asynchronous write errors reach
`on_error` or a notification. SQLite runs in libuv workers, using separate connections and bounded
timer-based retries for database contention. No busy timeout or shutdown wait blocks the editor.
`read_sync()` and `write_sync()` retain the proxy's startup dependency and immediate error contract.
The initial theme also reads synchronously before the first frame; subsequent UI reads and saves
use asynchronous I/O. Reads are bounded to 64 KiB by default, and documents carry a
positive integer `version` (default 1). Missing state returns no document; malformed, oversized, or
unsupported versions return an error so the feature can choose its fallback.

SQLite transactions atomically replace records in a private (0600) database, with one active write
and the latest pending document per namespace. Two processes saving the same namespace use
last-committed-write semantics; this is document replacement, not a field-level merge.
Persistence is best effort at exit; the process does not wait for pending saves.

Reads import the old namespace JSON files, including project-scoped files. Migration inserts only
missing records, validates the committed document, then removes the source JSON. Existing database
records win over stale migration files. Failed imports retain their source for recovery.
The legacy `path` option identifies an import file; its directory contains the new `state.db`.
Third-party plugin files such as `lazy/state.json` retain their native format.

`config.startup.logs` creates `<stdpath('state')>/logs/` before plugin bootstrap and configures
Neovim, LSP, LuaSnip, Mason, Telescope, and Overseer to write directly there. It uses native path
settings where available; small adapters configure Telescope's Plenary logger and Overseer's path
provider. LSP currently requires Neovim's internal filename setter. No root-level compatibility
links or ongoing migration are created. Editor state such as ShaDa and swap stays in its native format.
The separate terminal UI starts before Lua initialization and may write to the default
`<stdpath('state')>/nvim.log`. This is expected; no shell configuration is required.

Theme and proxy recognize `theme.json` and `proxy.json` only as legacy import paths. Theme accepts its old
unversioned document and adds version 1 on the next confirmed save; proxy retains its version 1
environment document and user-only permissions. Window preferences use one namespace per panel
role and axis, such as `window-NvimTree-width`. Each feature owns value validation, defaults, and
which user actions warrant saving. Native ShaDa history and live Git/request state keep their
existing owners.

## Local plugin development

`config.user` maps `NVIM_DEV`, `NVIM_DEV_PATH`, and `NVIM_DEV_PLUGINS` assignments in `~/.nvim`
to a `dev` table while preserving proxy assignments. It also accepts existing JSON settings.
`config.startup.lazy` reads that optional `dev` table before plugin setup.
It gates repository match patterns on `dev.enabled` and passes the checkout parent directory
to lazy.nvim's native development resolver, with remote fallback disabled. Plugin declarations
retain their remote source so disabling development mode restores managed installs. See
[Local plugin development](development.md#local-plugin-development) for settings.

## Project Theme System

The current code-scope background is shown only when its complete source range occupies at most
50% of the active window's height and at most 120 lines. Cursor movement, window focus, and resizing
re-evaluate this limit, clearing the background when the scope becomes too large for the view.
`config.syntax.visuals` owns this visibility policy; the theme supplies its color.
Scope refresh uses Tree-sitter's asynchronous parse callback and caches ranges by buffer changedtick.
Cursor movement uses only ready syntax; edits and buffer deletion invalidate pending completions.
Scope and rainbow whole-tree queries are skipped above 5,000 lines or 1 MiB, measured from the
loaded buffer. Native syntax highlighting remains enabled and uses Neovim's asynchronous parser.
Highlight attachment is deferred and coalesced per buffer; unloading cancels a pending attachment.

`config.ui.theme` is initialized by startup assembly after plugin registration, independently of
Monokai's plugin declaration. `:Theme` uses the theme picker in `config.search.telescope`; the theme owner handles preview
rollback and its confirmation action saves the final choice. Native `:colorscheme` changes remain
transient. The theme picker preserves the previous background setting when cancelled.
The loader clears old highlight groups before applying the next scheme, including schemes that
conditionally clear only while the previous colorscheme name is still set.
Live preview applies on the next main-loop turn, outside the picker's suppressed or non-nested
autocommands, using the original editor window's context rather than the floating prompt's
highlight mappings. Colorscheme listeners refresh the same modules as confirmation. A request token
discards superseded selections; closing the picker or deleting its preview retires queued work.

`config.ui.palette` derives one semantic schema from the active theme's `Normal`, syntax, diagnostic,
and Git groups. It reads global definitions and follows their links explicitly: resolved API lookups
can otherwise reuse the active pane's `winhighlight` mappings after redraw and feed old pane colors
back into the new palette. Missing values have separate dark/light fallbacks. Text and selected rows are checked
for contrast; ordinary surfaces share the editor base, and pinned context is a subtle grey tint of
the editor background, with a weaker filter for light themes. Telescope's pane backgrounds
and margin cells share this editor base color; border glyphs use the shared neutral edge color
with at least 3:1 contrast. Titles and selection retain their
own emphasis. Inactive editor windows use the same background so the picker has no contrasting
rectangular backing. `config.syntax.highlights` remains the sole owner of project highlight
application and optional base-palette application. Its shared refresh coordinator applies groups
immediately on `ColorScheme`, then coalesces a final `vim.schedule` pass after plugin callbacks and
lazy plugin loads. The final pass reads the current palette, so rapid switches cannot restore an
older theme. This runtime path uses no timers or polling. Plugins retain their native theme listeners;
renderers retain their named highlights, buffers, and cached data;
changing colors does not rerun Mermaid jobs or rebuild panels. The native `StatusLine` and
`StatusLineNC` groups use a subtle neutral filter over the editor background, with a weaker
inactive variant. Lualine consumes these same palette roles through its public theme callback;
all sections share the footer surface and the mode label uses bold text. ToggleTerm background
shading is disabled.
Pane-selection labels use a bold theme accent adjusted to at least 7:1 contrast against the shared
editor background; their matching borders have at least 4.5:1 contrast. Named `FilePaneLabel` and
`FilePaneBorder` groups refresh through the same colorscheme coordinator.

Saved name/background pairs have a 4 KiB bound. Before `VimEnter`, startup reads the saved record
synchronously and applies it directly, avoiding a visible default-to-saved theme switch. Database
contention fails immediately; there is no polling or lock-wait loop. Missing or invalid choices use
the default. Setup after startup reads asynchronously and keeps the current theme until resolution;
a generation counter prevents a late read from overriding a newer selection or preview. Confirmed
choices use the shared SQLite writer, with coalescing and best-effort saves at exit.

`themes/default/*.lua` contains bundled preset tables; `themes/*.lua` contains personal presets
and takes precedence for matching names. The picker lists these files and the current selection;
it does not expand installed plugins into every native variant. The loader validates each preset's native colorscheme and
optional light/dark variant, then uses the existing colorscheme path. An optional eight-color palette
is applied through the highlight owner. Personal preset files are ignored by Git; bundled files and
plugin pins remain tracked. See [Themes](../themes/README.md) for presets, file creation, and overrides.

### Tmux theme integration

Startup enables `config.ui.tmux` when `TMUX` and `TMUX_PANE` are valid, `tmux` is available,
and `~/.config/tmux/scripts/theme.sh` is executable. Publication requires an attached Neovim UI,
so headless commands do not publish. Set `vim.g.beck_tmux_theme = false` before
`require('config').setup()` in `init.lua` to opt out. Tmux's hook also verifies that the Neovim
terminal UI PID owns the pane's foreground terminal; inherited environment alone cannot claim a pane.

The adapter resolves colors through `config.ui.palette`: `bg`/`fg` use the editor base,
`surface` uses the code-block surface, `cursor` uses the active row, and `border`/`muted`
use the shared neutral roles. `green`, `cyan`, `yellow`, and `purple` use function, type,
string, and constant accents; `red` uses the deletion accent. These eleven base roles are
sent as `#RRGGBB` argv entries with `--owner` set to the `nvim-tui` channel's advertised PID,
falling back to the editor PID for older UIs. This supports Neovim's separate TUI and editor processes.

The hook accepts any nonempty subset of `ROLE=#RRGGBB` entries, with omitted base roles
falling back to tmux's night defaults. Each publication replaces the previous overrides.
It accepts color values, not a theme name or a light/dark selector. Sending all base roles
keeps light themes consistent. The optional `window_active_fg`, `window_active_bg`,
`window_inactive_fg`, and `window_inactive_bg` roles are omitted: tmux derives them from
`green`, `cursor`, `muted`, and `bg` respectively. Tmux stores publications in
`@beck_palette_*` and resolves pane/shared UI colors through `@beck_pane_*`/`@beck_ui_*`;
the adapter only calls the hook and does not depend on these internal option names.

Startup, UI attachment, colorscheme changes (including preview and rollback), and lazy plugin
loads schedule publication after highlight callbacks. One asynchronous hook runs at a time,
with a one-second timeout and one replaceable pending action. Palette resolution occurs when
the queued publication starts, so bursts use current colors. Resume and return from shell
commands republish even if the palette is unchanged. Suspend queues an owner-scoped reset
and suppresses color updates; exit retires queued publications and attempts a reset without waiting.
Sync is best effort: failed color resolution, launch errors, nonzero exits, and timeouts stay silent.
There are no retries until another editor event requests publication, and sync never delays editor exit.
Tmux owns crash and foreground-loss recovery through its watcher, including when suspension
or exit prevents Neovim's callbacks from completing. The adapter does not reset on pane focus
changes and never uses `--force` or changes tmux's global defaults.

### Tree-sitter query extensions

The renderer fork owns its Markdown table query under `after/queries/markdown/`, using
standard runtime discovery and `; extends`. BeckNvim needs no custom query runtime registration.

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

`config.ui.float` is the single definition of ordinary float close and focus-lock behavior. While a
focusable float is active, attempts to focus a non-floating window in the same tab are returned to
that float; focus may still move between floating panes, and closing the active float releases its
lock. Callers provide a buffer and close callback, or a Telescope-compatible mapping callback.
Editable floats opt into
`accepts_input`: insert-mode `q` remains content and `<C-q>` closes; after returning to normal mode,
`q` closes and `<C-q>` remains unbound for Visual Block. Read-only floats receive only normal-mode
`q`. Window layout, rendering, and feature-specific actions remain in their owning modules.

The translator, LSP detail windows, and the project-audit float consume this definition directly.
Telescope's combined panes use a separate policy in `config.search.telescope`: `<C-q>` closes the
owning picker in every mode, including Visual and command-line mode. `q`, normal-mode Escape, and
insert-mode Ctrl-C do not dismiss it; `:q` is rejected before a pane can close. A pane unexpectedly
closing retires the remaining picker through Telescope's native teardown. Focused source previews
are read-only and reject Insert/Replace mode; Tab unlocks native preview updates and returns to the
prompt. Telescope may replace the preview buffer during a layout refresh, so the shared previewer
loaded handler binds the return action to the current buffer while preview focus is active. Git
pickers retain their existing layer-pop action.
File, grep, buffer, definition, diagnostic, and shared LSP/type pickers use Telescope's native
`flex` layout across the full editor. Picker size is independent of the launch pane; the captured
navigation context still targets that pane when selecting a result and restores native split
proportions after teardown. When a native resize hides the focused preview, focus returns to the
prompt without retiring the search. Project-wide query scope is independent of the layout.
Renderer-owned scratch buffers do not set `readonly`, which would raise W10 on native result and
preview updates. Grep/definition preview text and cursor placement precede asynchronous structural
context; the winbar accepts a completion only for the current selection, buffer revision, and window.

## Markdown Rendering

`plugins/extra.lua` selects `BeckWlim/render-markdown.nvim`, whose default pipeline provides the
source-mapped preview. The plugin uses a managed install by default;
`~/.nvim` can select `~/.config/render-markdown.nvim` through the standard development settings.
The fork owns prose rendering, table projection, Mermaid jobs, source maps, incremental updates,
preview buffers, source editing, save delegation, and hidden-source file checks. BeckNvim contains
no second Markdown engine. See the fork's [preview architecture](https://github.com/BeckWlim/render-markdown.nvim/blob/main/doc/projected-preview.md)
for the provider contract, lifecycle, limits, and standalone tests.

Markdown files open rendered in the existing pane. `<Space>mp` calls the plugin's `preview()` API
to switch between source and rendered text. Tables wrap into real lines; selection and yanking
copy displayed text. Edit keys return to the mapped source position; leaving the edit restores
preview. Writes, undo, and redo operate on the source. Explicit source mode remains raw.

The host integrations use the plugin's public `source_location()`, `display_position()`, and
`leave_preview()` APIs for link opening, pinned heading context, dashboard transitions, and file
replacement. The documented `b:markdown_preview_source` marker lets shared window context resolve
the original file identity for both the statusline and file-opening policy.
Multiple panes of one source keep separate generated projections, source maps, and cursor positions
in the renderer. Closing or replacing one pane preserves the other panes' rendered views.
Project roots and relative paths resolve the source file, including searches launched from a preview.
`config.syntax.highlights` retains BeckNvim's palette overrides for the plugin's semantic highlight
groups. Read-only Markdown detail buffers continue to use the ordinary upstream renderer.

## Optional Mermaid Dependency

`plugins/termaid.lua` declares `BeckWlim/termaid`; the renderer references it as an optional lazy.nvim
dependency. Declaring Termaid opts it in without making it mandatory for the renderer. The preview
uses an available executable automatically and leaves original Mermaid fences visible when absent.
The fork owns executable discovery, validation, caching, concurrency, and cancellation.

The Termaid spec builds an editable Python environment inside its selected checkout. Use
`:Lazy build termaid` after changing checkouts or to retry a build; `:Lazy update termaid` advances
the locked revision. `setup.sh` checks Python and uv without installing either runtime. Lazy.nvim
owns the Termaid build, using uv when available or Python's `venv` and `pip` otherwise. Both paths
install into the checkout's `.venv` and keep the package editable.
The build job probes Python and skips successfully when its runtime prerequisites are unavailable;
the editor main loop performs no Python probe. A skipped or failed build leaves Mermaid source
visible through the renderer's existing fallback. Restart Neovim after adding runtimes and run
`:Lazy build termaid` to retry.
An explicit `opts.preview.mermaid.command` overrides discovery; set
`opts.preview.mermaid.enabled = false` to disable diagrams. Arrow placement is configured with
`opts.preview.mermaid.arrow_position = 'middle'` (the default is `'end'`).

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
- An invocation loads Telescope synchronously; picker readiness activates at the end of setup.

This finder is deliberately separate from `config.search.query_picker`. A query-picker session is
empty-first and async-filled, while the definition finder is prompt-driven — the prompt is the
query. Both keep insert-mode `q` as query text, use insert-mode `<C-q>` to cancel, and use
normal-mode `q` to close. Picker teardown invokes the finder's `close` and retires the active job
generation.

LSP navigation has a separate ownership path through `config.search.lsp_locations`. Every location query
opens its Telescope session before dispatching requests, streams available results, and cancels
outstanding requests when the picker closes. Cancelled primary requests are retried once; auxiliary
document-highlight failures do not turn a successful project reference request into a failed query.
Definition queries in C++ also seed from the enclosing function's Tree-sitter lexical declaration,
which covers captured locals inside nested lambdas when clangd cannot resolve the reference. These
provisional rows are removed only after a non-empty LSP batch is merged, so an empty response from one
client or batch cannot erase a valid local candidate.
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

`config.git` exposes three history scopes. FILE and SYMBOL use `config.git.diffview`;
REPOSITORY opens `config.git.graph` and uses Diffview for the selected commit's files.
FILE resolves only its path, SYMBOL resolves its cursor structure through Neovim's cooperative
parser callback, and REPOSITORY resolves only its root:

```text
<Space>df → file path + --follow commit selector ─────┐
<Space>ds → cursor structure + line-trace selector ──┘→ bounded FileHistory → history list + two code panes
<Space>dr → repository root → Git graph + commit preview → <Space>dv → selected-commit DiffView
<Space>de → standalone branch/commit/issue dispatcher ── selection → FileHistory route
```

`config.git.graph` owns the default repository tab: Git's `--graph --topo-order HEAD` output
supplies selectable commit nodes and connector rows, while a lazily loaded `gitcommit` buffer shows
the selected message and changed-file names. Unmerged branches stay outside the default history;
bounded background merge-base jobs mark their shared fork commits. Ref, fork, and `[HEAD]` badges
render as right-aligned virtual text with unabbreviated names over trailing title space. The default
graph list takes 40% of the editor width. The list formatter places hashes
close to graph nodes and preserves natural subject spacing, highlighting Conventional Commit
prefixes and leading bracket tags by type, with generic tags using the theme's identifier color.
`config.git.subject` supplies shared byte ranges and theme roles for both graph rows and the
Diffview footer's subject spans and the commit-detail header. The existing footer decoration pass reapplies these spans after
native redraws without changing Diffview's row text, selection, or file rendering.
Commit rows remain consecutive, with additional rows only for Git's merge connectors.
Each graph load also requests NUL-delimited porcelain status with the same cancellation generation.
`repository.parse_worktree_state` supplies HEAD and structured changed paths. The graph inserts a
synthetic `WORKTREE` node immediately above the matching HEAD only when dirty. Its preview uses
that status snapshot; its detail uses native Diffview local mode (including staged and untracked
files), without passing the synthetic identity to Git as a revision. The existing session snapshot
preserves this selection, and the checkout action ignores the synthetic node.
Subjects and topology retain their full text so native horizontal scrolling can reveal long rows.
It pins the current branch in the winbar and applies existing theme highlight groups by semantic
role. Connector rows are skipped during cursor movement.
The branch window splits only the left pane and uses the existing branch parser. Like Git search,
`o`/`Enter` reviews its selected ref without changing HEAD. `<Space>dm` explicitly switches or tracks
the selected branch. Read-only branch review reloads the graph in place, preserving the branch
window and its focus; cancellable, generation-checked list jobs reject superseded branch results.
Switching checks both Git status and modified repository buffers. Explicit fetch and
layout toggles preserve the reviewed ref, including remote refs whose commits also belong to HEAD.
`<Space>dv` sends the commit-list cursor or the focused preview's displayed commit directly to
Diffview's native `DiffView` using `<hash>^!`. Preview identity includes its branch ref, so a
remote-tip preview does not open the unrelated graph selection.
Its flat bottom file panel contains only that commit's changed files; the code panes compare the
first parent with the commit, with an empty tree for root commits. No containing-ref lookup,
history walk, or footer loader runs in this path. The header carries the colored commit title.
Its active and inactive winbars use the editor's `Normal` surface via native panel window options.
Toggling back mounts the graph directly before asynchronously disposing the detail tab, restoring
its branch and commit without exposing the editor or homepage. Retired detail callbacks cannot
refocus their panel. Checkout retains the same immutable diff.
Graph and detail commit checkout share `config.git.detach_commit_overview` for target resolution,
dirty-worktree and modified-buffer guards, and HEAD mutation. The graph supplies owner-validity and
render callbacks instead of mounting Diffview; its reload retains the reviewed branch, pane sizes,
focus, and preview. Retiring the graph rejects pending checkout callbacks before mutation.
Diffview owns file-list rendering, file selection, and historical buffers.
File and symbol views begin directly with its compact bottom panel. Git's own graph output owns
the repository topology rendering so merge connections remain aligned with selectable rows.
`config.git.footer_loader` supplies a shared two-level demand model
for search, file, and symbol histories: lightweight Git commit metadata is fetched in 200-row batches and retained
in a sliding 600-row list window. The first batch mounts before the rest of the current window fills
asynchronously in branch order, and its changed-file children begin hydrating from the top at the
same boundary. Background workers claim configured eight-commit batches and use paired Git streams
whose record separators preserve commit ownership; unsupported or malformed records fall back to the
single-commit Diffview path. The four-worker pool reserves one slot for an explicit action and uses
the others for background preload.
For repository scope, a dirty porcelain-v2 worktree adds one synthetic `WORKTREE` row ahead of the
branch rows. Its children use Diffview's native `HEAD → LOCAL` revisions and include untracked files;
it is not emitted for file or symbol scopes and does not alter cursor-target restoration.
Cursor movement within the window does not replace or reprioritize that queue. `config.user` reads optional user-level `~/.nvim` settings and `config.git.settings`
validates bounded overrides before the repository/loader modules consume them. The detail panel starts at ten lines at the bottom;
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
and the native detail remains part of the same Git mode; `:q` exits the mode.
Diffview revision buffers opt out of the editor-wide current-scope extmarks but retain the editor's
real pinned Tree-sitter context inside the focused code pane. The pinned source lines use a shared
restrained grey declaration background with a contrasting grey lower boundary. The
remaining code render is reduced to syntax
foregrounds, one ordinary cursor-line background, and Diffview's add/change/delete backgrounds.
Each root Git view resolves the current window through `config.ui.window_state` and captures the
editor's absolute/relative line-number intent before Diffview creates its tab. It reapplies that
intent to both code panes after every layout. The original editor window keeps its own settings.
Special surfaces register their own resolver with the shared gate: the
dashboard exposes its saved editor options rather than its deliberately gutterless presentation.
Diffview's commit/file footer remains natively unnumbered.
Render completion synchronizes Tree-sitter independently for both Diffview file buffers rather than
depending on which pane happened to receive the last `FileType` or window-enter event.
No history render performs an automatic declaration lookup, fold reveal, or cursor jump. Diffview's
native selection position remains authoritative, keeping Tree-sitter parsing out of the input path.
`<Space>fw` keeps its global project-definition-search role in Diffview and the editor. Git mode does
not install a buffer-local override, and return staging removes any stale historical-search mapping
before the working buffer becomes visible.

The Git workflow uses a dedicated repository graph and Diffview for historical file detail.
Editor entry points call `config.git`,
while renderer callbacks, enrichment tokens, and transition phases remain private. The only public
callback boundary is `config.git.on(...)`, backed by `config.git.events`, which asynchronously
publishes stable `phase`, `ready`,
`return_started`, `return_finished`, and `anchor_finished` events. Consumers do
not subscribe to raw Diffview callbacks or mutate lifecycle state. Event payloads contain only
generation, kind, phase, outcome, detail, and path metadata—never Diffview view/window objects.

Each Diffview tab is one lifecycle unit. The graph tab separately owns its two windows, branch
split, pending Git requests, and return to the editor. Public file, symbol, and repository history entry points
reject a second root history while any Git mode is active; `<Space>de` is the sole temporary layer
entry from an existing history. A pending symbol-resolution callback repeats that active-view guard
before mounting, so it cannot race a newer Git pane. History requests made during teardown are
rejected instead of being retained by a polling retry and remounting after the editor handoff.
Each mounted history receives a monotonically increasing
generation and moves through explicit mounting/listing/enriching/rendering/ready/returning/closing/
disposed phases, with `failed` as an explicit terminal work state. Every asynchronous
callback checks both its view generation and render
sequence, so a replaced view cannot redraw, jump, or complete a newer operation. The command-line
Enter dispatcher routes interactive `:q`/`:quit` from any graph or Diffview pane through a
whole-mode close without interfering with Diffview's internal window replacement.
An idle history has a stable null-layout readiness marker and returns to the untouched editor state.
A whole-view close cancels configuration-owned footer enrichment and focuses the original editing
tab immediately while Diffview shuts down its history stream and disposes the view asynchronously.
The editor keeps its tab, buffer, cursor, folds, and viewport even when a historical file was open.
Lualine branch state is refreshed in the preserved editor window before the tab switch and again
after Diffview disposal, which can update its active-buffer cache. Return cleanup removes only
mappings whose key and description identify them as Git-owned, preserving editor-local mappings.
Repository-search re-entry during the remaining disposal interval is stored as one keyed settled
action. Final view disposal releases it once, preserving the history-plus-search pipeline without a
polling loop or duplicate transition.
An exit at any phase cancels configuration-owned work and restores the untouched editor state
immediately; Diffview disposal continues asynchronously after the editor is usable.
List, warm-up, or selected-render timeouts enter `failed`, retire their render callback once, and
still accept `:q` so an asynchronous failure cannot trap the user in Git mode.
Return navigation performs no Tree-sitter, LSP, Telescope, Git lookup, or cursor placement.
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
Diffview. `<Space>dr` passes through the same repository gate and mounts the graph tab
immediately. Selecting a standalone branch or commit opens Git mode directly at that review route;
selecting an issue opens its Markdown detail directly over the editor and does not mount Diffview.
The graph's `<Space>de` opens search directly over its list, preview, or branch pane. Search dispatches
branch and commit reviews through graph-owned callbacks: branch selection reloads the existing graph,
an existing commit is selected in place, and an off-graph commit opens in the existing message preview
without replacing the retained branch history. Canonical commit IDs and branch-preview rows use the
same callbacks; retired graph owners reject late commit resolution. Cancelling search or returning
from an issue preserves the graph's panes, selection, and focus. The same buffer-local
`<Space>de` reopens search from Diffview Git mode, where the history view retains its commit/file panel,
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
Native fold renders schedule only the shared footer-annotation pass from the panel buffer boundary;
they do not trigger configuration-owned cursor restoration, so expand and collapse remain a single
Diffview render while branch separators are reattached.
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
the same compatibility layer. It resolves inline Markdown labels in any buffer before falling back
to Neovim's cursor and selection target discovery, so concealed destinations remain reachable even
when a Markdown-rendering surface uses a specialized filetype. GitHub
`/issues/<number>` and `/pull/<number>` targets first resolve through the same provider and open the
same detail float; failure emits a warning with the provider error before falling back to the
asynchronous browser handoff. Direct PR resolution
carries its resource kind through the public-page fallback, preserving `/pull/` and the shared
body-and-discussion renderer. Local
file targets resolve from the current buffer or rendered source, then use the shared a/b/c chooser
to replace an existing editor pane. A sole editor is reused automatically; cancellation preserves
files, focus, and proportions. Targets within the source project
follow the ordinary file lifecycle. Cross-project targets suppress `FileType` consumers during the
open and start only Tree-sitter highlighting, preventing an unrelated workspace index from starting.
Same-project targets always follow the ordinary `FileType` and LSP lifecycle;
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
comments. Direct `gx` navigation publishes the resolved record immediately, opens the existing
detail float with an explicit discussion-loading state, and replaces that state in place when the
optional comment request settles. Closing or replacing the float cancels that request through the
same generation-owned direct-request lifecycle. Failure to enrich discussion does not discard an
already resolved issue or pull request.
SSH Git authorization remains owned by Git and is never extracted as an HTTP
credential. GitHub issue and pull-request metadata receives the shared proxy environment explicitly.
Pull-request acquisition treats the detail endpoint's numeric commit count and head SHA as summary
metadata and does not request the full commit list, so the detail float is not delayed by a second
PR-specific network round trip. The detail card shows only the count and head SHA.
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
Git graph and Diffview panes route `:q` through whole-mode teardown. `<C-q>` remains the cancel
key for search and input dialogs; cancelling an in-mode search restores its preserved history.
Git mode exit restores the editor state preserved before entry and refreshes lualine's checked-out
branch state. A historical file selection never changes the editor's buffer or cursor on exit.
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
focused fixture to `config.search.workspace_symbols` and
`tests/search/workspace_symbols.lua`.

Project-root authority belongs to `config/project.lua`. Git repository roots outrank attached LSP
roots; LSP roots outrank `.venv`, language manifest, and build-file fallbacks. Consumers must use
this shared policy instead of maintaining their own marker order. Language-server startup markers
remain with `config/lsp/init.lua`. Language-server installation and removal belong to Mason's native
UI (`:Mason`). Mason's defaults keep installation explicit, so every server—including `bashls` and
`vimls`—is installed only through a Mason action. Mason automatically enables servers that are
already installed; it does not restore removed servers. Existing basedpyright environments carry
their own runtime. Native clangd, Lua, and Markdown servers retain normal activation after
installation. Python hierarchy indexing reports a
feature-level error when neither system Python nor a project virtual environment exists, preserving
any completed index.
The statusline resolves Markdown previews to their source buffer before requesting the project
identity and project-relative file path. Modified and read-only indicators also follow that source,
so changing between rendered and editable views preserves the file's footer identity.
Explicit project activation also passes through `config.project.activate`, which updates the current
window-local directory and publishes one authoritative, tab-owned root generation; closing the tab
tears down that retained state with it. UI consumers subscribe to the transition instead of inferring
project changes from unrelated buffer or directory events. The file-tree subscriber queues the
latest generation for the next event-loop turn and rejects stale generations before updating
nvim-tree's root and window-local directory.

`dashboard-nvim` remains responsible for the homepage buffer lifecycle. The local
startup options suppress Neovim's built-in intro (`shortmess+=I`) so it cannot flash before the
project homepage. The local
`dashboard.theme.project` module delegates its compact rendering and navigation to
`config.ui.dashboard`; the first paint contains the current project, while optional recent-file
enrichment runs after that paint. Recent files come from `vim.v.oldfiles`, are grouped through the
shared project authority policy, and are capped before rendering. The homepage layout hides the
large brand icon before reducing recent-file rows when height is limited, then
reduces padding and optional footer context. Terminal and pane resizing preserve the selected
project/file and restore the icon when space permits. Activating a project updates the dashboard
window's local working directory and context in place; an existing file tree follows the same root
without being opened or focused. The dashboard declares its gutter-free presentation through
`config.ui.window_state`; each displaying window retains its own underlying editor intent. Buffer
replacement restores that intent through the shared transition pipeline, including native splits
from the homepage. Leaving the window or tab preserves its dashboard presentation, while Git panes
and returned files resolve the underlying editor settings.

Startup-only modules remain small: keymaps retain deferred module callbacks for feature-owned
actions, and plugins that serve files, insert mode, or explicit commands load on their first relevant
event. LSP setup completes during plugin loading so Mason commands are registered before lazy.nvim
dispatches them. Completion setup remains deferred until insert mode.

`config.ui.folder_picker` owns the shared project switcher used by `<Space>fp` and the homepage's
folder action. Its Telescope finder searches direct child directories asynchronously within the
requested path, cancels stale `find` jobs as the prompt changes, and caps streamed results. The selected folder
uses a real Telescope previewer that renders a bounded, read-only file tree through a cancellable
child process. The preview loads each folder's direct children on demand; focused-preview Enter
toggles expansion and collapse, so nested content remains reachable without a fixed preview depth.
Absolute, home-relative, and relative path prefixes are expanded into their own search
scope. A partial path matches direct child folder names by literal, case-insensitive prefix;
entering `<prefix>/` lists that folder's direct children. Without a trailing slash, a complete folder name
still matches sibling names with the same prefix. Bare names match only direct child folders in the
picker's starting directory; relative paths resolve from that same directory. An invalid parent path
returns no results. Telescope preserves these matches without applying a second fuzzy filter.
The initial `.` and `..` entries are prompt shortcuts: confirming one rewrites the scope to the current
or parent directory and keeps the picker open.
Confirming a result delegates to `config.project.activate`; when the dashboard is the
active pane, its project drawer refreshes in place, while the file-tree subscriber follows the same
authoritative root transition from any other pane.

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

`config.git.footer_search` owns footer-local `/`, `?`, and `n`/`N` search sessions over the retained
history model. It reuses the bounded footer loader for pending children and Diffview native fold
and highlight methods to reveal matches without opening files. Request tokens reject superseded
search callbacks; incremental previews use already loaded metadata.
The search session owns only its temporary expansion, collapsing it when the match changes commits
and restoring the prior expansion on cancellation; existing open commits retain their fold state.

`config.keybindings` owns reusable semantic key families. It composes a family with a prefix or
key format and binds feature-provided handlers, or returns mappings for plugin setup. The direction
family supplies `h/j/k/l` to window movement, resizing, cursor movement, and Telescope; the tree
family supplies selection, folds, and search. It performs no node traversal, rendering, or I/O.
The shared selection family supplies `o`/`Enter` to the homepage and tree panels; dashboard activation
and file opening remain owned by `config.ui.dashboard`.
`config.ui.filetree`, `config.ui.folder_picker`, and `config.git.diffview` adapt these actions to
native feature behavior. Flat LSP/type-hierarchy result pickers retain their existing interactions;
source folds retain Neovim's native `z` behavior.

`config.ui.tree_search` owns bounded filesystem discovery, pattern matching, and temporary reveal
sessions for filesystem panels. It cancels child processes on leave, rejects stale root/selection
callbacks, and asks adapters to snapshot, restore, and reveal paths. Git reuses the matcher and key
family while retaining its existing footer-loader lifecycle. NvimTree renders through its public
API; the project preview renders through its existing tree renderer.
