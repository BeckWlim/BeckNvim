# Git Mode

Git mode is a read-oriented Diffview workspace with an editor layer, ordinary history, and temporary
search or issue-detail layers.

Use `<Space>df` for file history, `<Space>ds` for symbol history, `<Space>dr` for repository history,
and `<Space>de` for branch/commit/issue search. Diffview owns footer rendering, commit folding, and
file selection. BeckNvim adds bounded asynchronous data loading and lifecycle safety, not competing
highlight, cursor, or fold behavior.

Search and preview do not change HEAD. `<Space>dm` is the explicit mutation action and refuses to
move HEAD when buffers or the worktree are dirty. Selecting a branch reviews it without switching.

`<C-q>` pops one layer. From history it opens the corresponding working-tree file when it exists,
without copying the historical cursor position; otherwise it restores the untouched editor.

See [Default keybindings](keybindings.md) for controls and [Architecture](architecture.md) for
ownership and state-machine details.
