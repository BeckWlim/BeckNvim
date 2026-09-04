# Git Mode Reference

Read the canonical [Git mode guide](../../../../docs/git-mode.md) and the Git sections of
[Architecture](../../../../docs/architecture.md) before changing `config.git`.

## Ownership

- `repository.lua`: Git commands, parsing, and process boundaries.
- `footer_loader.lua`: bounded commit metadata and child-detail queues.
- `diffview.lua`: adapter lifecycle and integration with Diffview-owned panels.
- `search.lua`: Telescope search sessions and read-only selection dispatch.
- `panel.lua`: editor/history/search/detail layer transitions.
- `lifecycle.lua` and `events.lua`: generations, readiness, cancellation, and public events.
- `init.lua`: public entry points and guarded checkout orchestration.

## Invariants

- Diffview owns footer rendering, selection, fold toggling, and file opening. Do not add competing
  highlights, cursor restoration, fold dispatch, or a second panel renderer.
- `<Space>de`, `<Space>df`, `<Space>ds`, and `<Space>dr` are read-only. `<Space>dm` is the explicit,
  dirty-state-guarded mutation.
- `<C-q>` pops one layer. History exit opens an existing working-tree file without copying the
  historical cursor; otherwise it restores the editor.
- Async work is generation-checked, cancellable, bounded, and local-only. Never fetch implicitly.
- Search-selected commits use the checked-out branch when contained. An uncontained commit may be a
  pinned independent preview row, but must not redefine the branch scope.
- Keep commit metadata structured and preserve native Git references and Diffview entry identity.

Verify focused behavior, the complete headless suite, `git diff --check`, and startup as documented
in [Development](../../../../docs/development.md).
