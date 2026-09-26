# Git Mode

Git mode is a read-oriented Diffview workspace with an editor layer, ordinary history, and temporary
search or issue-detail layers.

Use `<Space>df` for file history, `<Space>ds` for symbol history, `<Space>dr` for repository history,
and `<Space>de` for branch/commit/issue search. Diffview owns footer rendering, commit folding, and
file selection. In the history panel, `hjkl` move the cursor; `o` (or `Enter`) toggles a commit
or opens a child file. BeckNvim adds bounded asynchronous data loading and lifecycle safety, not competing
highlight, cursor, or fold behavior.

Only one root Git history can be active. The history entry keys refuse to mount another Git pane
until `<C-q>` closes the current mode; use `<Space>de` for temporary search inside Git mode.

Repository history also adds a newest `WORKTREE` row whenever the checkout is dirty. Opening that
row previews the complete live worktree against `HEAD`, including untracked files; it does not move
the editor cursor or create an additional jump action.

Search and preview do not change HEAD. `<Space>dm` is the explicit mutation action and refuses to
move HEAD when buffers or the worktree are dirty. Selecting a branch reviews it without switching.

`<C-q>` pops one layer. From history it opens the corresponding working-tree file when it exists,
without copying the historical cursor position; otherwise it restores the untouched editor.
Git code panes and the returned working-tree window retain the editor's line-number settings, even
when Git mode was opened from the intentionally gutterless homepage.

See [Default keybindings](keybindings.md) for controls and [Architecture](architecture.md) for
ownership and state-machine details.

In the history footer, `/` and `?` search commit metadata and changed paths, including collapsed
files and rename aliases. `n`/`N` repeat the search; matching commits expand temporarily without
opening a diff. Moving to another commit match collapses the previous search-opened commit;
commits already expanded before search stay open. Cancelling a search restores its previous
temporary expansion. Search covers the retained history window and waits for pending file details on
confirmation. Incremental search previews files whose details have already loaded.
