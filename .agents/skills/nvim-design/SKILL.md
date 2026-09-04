---
name: nvim-design
description: Design, implement, or review UI and workflow changes in this Neovim configuration while preserving its module ownership, Git/Telescope/Diffview state model, shared render strategy, key behavior, and verification standards. Use for changes under lua/config or lua/plugins that affect interactive panels, pickers, previews, Git history, syntax context, navigation, or shared UI infrastructure.
---

# Neovim UI Architecture

Keep interactive features visually consistent and architecturally small. Extend the module that
already owns a behavior; do not create a parallel UI, lifecycle, parser, or key-dispatch path.

## Start from ownership

Before editing, read the relevant section of `docs/architecture.md`, inspect the owning module and
its focused test, and identify these boundaries:

- data acquisition and parsing;
- workflow/state transitions;
- reusable rendering and interaction policy;
- feature-specific presentation;
- mutation and safety checks.

Prefer structured data at module boundaries. Parse command/network output before it reaches a
renderer, and keep rendering functions free of Git, network, or filesystem side effects.

Use the existing shared owners:

- `config.search.telescope` and `config.search.query_picker` for picker lifecycle and layout;
- `config.ui.float` for ordinary float close behavior;
- `config.syntax.treesitter_context`, `config.syntax.highlights`, and `config.syntax.visuals` for
  code context and colors;
- `config.network.proxy` for child-process network environment;
- `config.git.*` for Git mode. Read [references/git-mode.md](references/git-mode.md) before changing
  Git history, search, issue rendering, checkout, or Diffview behavior.

## Keep I/O asynchronous and bounded

Do not block Neovim's main loop on child-process, filesystem, LSP, or network work. Use bounded
parallel jobs for naturally independent partitions, stream structured partial results through
scheduled callbacks, and make the smallest useful list interactive before optional enrichment.

Every async workflow must own a generation or request token, cancellation handles, a readiness
boundary, and teardown behavior. Reject stale callbacks by both generation and current target when
selection can change inside one session. Use result caps and lazy per-item work as backpressure;
never fan out one Git or network request per rendered row. A timeout must enter an explicit failure
state that the user can still close safely.

## Render through existing components

Reuse the renderer that already owns the surface. Adapt structured input or supported configuration
instead of replacing plugin instance methods, copying a renderer, or rebuilding an established panel
as a new float.

- Telescope search is a results list plus a real preview pane; do not move preview content into a
  footer or prompt hint.
- Diffview owns historical code panes, footer rendering, folds, selection, and file opening. Preserve
  its objects and render lifecycle; Git integration adds data and lifecycle safety only.
- File, symbol, and repository histories share the commit → file footer hierarchy. FILE keeps
  `--follow`; SYMBOL keeps Git `-L`; their footer metadata identifies the active filter.
- Use winbars for stable scope/role metadata. Do not add configuration-owned footer highlights,
  cursor restoration, fold dispatch, or competing backgrounds.
- Keep layouts adaptive and restrained. Reuse shared dimensions, border groups, close policy, and
  focus transitions before adding feature-local constants.

## Keep one visual language

- Treat the resolved editor `Normal` background and foreground as the canonical base plane for the
  editor, file tree, ordinary floats, completion, Telescope, and Diffview. Do not introduce a
  feature-specific base background when these surfaces should read as one workspace.
- Reuse the editor `CursorLine` background for configuration-owned active rows. Leave Diffview footer
  selection styling to Diffview and the active colorscheme.
- Use dark neutral backgrounds, grey borders and secondary text, and grey-white primary text. Make
  matches, carets, and focused metadata visible through contrast and weight; avoid neon accents or
  blue-tinted selection backgrounds for ordinary focus.
- Reserve chromatic color for semantics: syntax, diagnostics, native Git add/change/delete states,
  and the pinned declaration context. The pinned context intentionally keeps its
  restrained light-green background and distinct green lower boundary.

## Preserve interaction invariants

- Give one key one role per active surface. Avoid overloads that depend on an invisible state.
- `<C-q>` pops the active UI layer; it must not tear down a lower preserved layer.
- Search and preview actions are read-only. A mutation requires an explicit action and its existing
  dirty-buffer/worktree guard.
- Keep editor operations available in readable detail buffers unless the feature truly requires a
  modal control surface.
- Preserve the user's current list, cursor target, and lower panel when opening a temporary search or
  detail layer.

## Keep changes tidy

Prefer a small adapter in the existing owner over a new module. Add a module only when it owns a
distinct state machine, external boundary, or reusable policy. If a new module is justified, wire it
from the existing assembly point and document the ownership in `docs/architecture.md`.

Follow the repository's binding and type-safety rules. Keep raw/resolved/rendered values in distinct
names, do not reassign parameters, and preserve traceback behavior. Avoid global state when view- or
session-owned state is sufficient.

## Verify behavior, not wording

Add focused tests beside the owning feature, then run:

```sh
XDG_CACHE_HOME=/tmp/nvim-test-cache XDG_STATE_HOME=/tmp/nvim-test-state \
  nvim --headless -u NONE -i NONE -l tests/run.lua
git diff --check
nvim --headless -u init.lua '+qa'
```

Run the configured static checker when one exists. Otherwise run the repository binding audit over
the changed Lua modules and report that static-checker coverage is unavailable. For renderer or
lifecycle changes, also exercise the real installed plugin against a disposable or read-only Git
repository; assert observable panel state, selection, scope, and return behavior rather than matching
only text.

Update `README.md` for user-visible keys or behavior and `docs/architecture.md` for ownership,
lifecycle, or render-strategy changes.
