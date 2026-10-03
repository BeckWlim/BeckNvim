# Git Mode

Repository history opens as two side-by-side windows, with 40% of the width allocated to the left
history list. The left window lists up to 600 commits
reachable from the checked-out branch by default, including merged commits and their topology.
Other unmerged branches do not add rows; a fork commit within the displayed window receives a
`[branch↗]` badge. Refs pointing at visible commits also appear as badges. `[HEAD]` and branch
badges sit at each row's right edge without abbreviating names, using trailing title space when a
title is long. Commits use consecutive text rows, with extra rows only for merge connections.
Subjects use natural spacing; theme colors distinguish Conventional Commit prefixes and leading
bracket tags such as `[Bugfix][Store]` without padding
types or titles into aligned columns. Full subjects remain in the buffer; move right or use `$`
to scroll horizontally and read the end of a long title.
The right window previews the selected commit's message, metadata, and changed files as a read-only
Git commit buffer. Moving through the list updates the preview; `o` or `Enter` focuses it. The
read-only preview colors the full subject without the 50-column commit-composition cutoff. The
current branch stays in the list header. Commits do not expand or collapse in this view. `<Tab>`
moves between windows.

When the checkout has staged, unstaged, or untracked changes, a `[WORKTREE]` item appears directly
above its HEAD commit. It is absent from clean checkouts and histories that do not contain HEAD.
`o`/`Enter` previews the changed paths and index/worktree status; `<Space>dv` opens Diffview's native
local-changes view, including staged, unstaged, and untracked files. Toggling back restores the
worktree item. Status refreshes when opening or returning to the graph or reviewing another branch.

`<Space>db` opens an optional branch list below the commit graph. Names are compact in the list;
the selected branch's full name and upstream appear in the winbar. Its selection previews the branch
tip. `o` opens that branch's history for read-only review, preserving the checkout; `Enter` is an alias.
Review updates the history in place and keeps the branch picker, its selection, focus, and split sizes.
Use `<Tab>` to move from the picker to the updated commit list.
`<Space>dm` switches to a local branch or creates a local tracking branch from a remote ref after
checking for unsaved and worktree changes. `f` explicitly
fetches all remotes and prunes stale refs. Closing and reopening the pane refreshes local branch
data. `<Space>db` hides the branch list. Fetch is never automatic and retains the reviewed history scope.

`<Space>dv` works in both the commit list and the commit-message preview. It opens the list's cursor
commit or the preview's displayed commit respectively. The branch picker keeps its `o`/`Enter`
review controls. Two code panes compare the chosen commit
with its first parent (or an empty tree for a root commit); the bottom panel lists only that
commit's changed files. `o` or `Enter` opens a file. The commit title appears in the panel header,
using the same theme colors for Conventional Commit prefixes and bracket tags. There is no second
commit-history list or background history loading in this detail layout.
Press `<Space>dv` again to return to the same graph branch and commit.
File and symbol histories continue to open directly in Diffview.

Within one Neovim process, `<Space>dr` resumes the repository's last graph or detail view after
`:q`. It remembers the reviewed branch and commit, branch picker, pane sizes, focus, and cursor
positions; detail also remembers the opened file. Each repository has its own snapshot in the
shared store's memory-only session scope. Nothing is written to disk or restored after restarting
Neovim. A removed review branch falls back to the current checkout's history.

Use `<Space>df` for file history, `<Space>ds` for symbol history, `<Space>dr` for repository history,
and `<Space>de` for branch/commit/issue search. Diffview owns file rendering and selection.
File and symbol histories retain their commit/file hierarchy and native folding.

Only one root Git history can be active. The history entry keys refuse to mount another Git pane
until `:q` closes the current mode; use `<Space>de` for temporary search inside Git mode.

`<Space>de` works from the graph, commit preview, branch pane, and Diffview without changing layouts.
Cancelling with `<C-q>` returns to the same panes and selection. In the graph, selecting a branch
reviews it in place; selecting a commit focuses its graph row or previews it beside the retained
history when it lies outside the list. Issue details return to the same search. `<Space>dv` opens
file diffs explicitly.

Branch history reviews opened through search also add a newest `WORKTREE` row when the checkout is dirty.
Opening that row previews the complete live worktree against `HEAD`, including untracked files.

Search and preview do not change HEAD. In the graph's commit list or message preview and Diffview
detail, `<Space>dm` is the explicit commit checkout action and refuses to move HEAD when buffers or
the worktree are dirty. Graph checkout retains the reviewed branch, panes, and focus. Selecting a branch
in either the search picker or branch pane reviews it without switching; `<Space>dm` in the branch
pane performs the guarded branch switch or remote tracking action.

`:q` closes the whole Git mode from any graph, Diffview, or issue-detail pane and restores the
editor's existing tab, buffer, and cursor. It does not jump to a historical file. `<C-q>` remains
the cancel key for input dialogs and pickers. Git code panes retain the editor's line-number
settings, even when Git mode was opened from the intentionally gutterless homepage.

See [Default keybindings](keybindings.md) for controls and [Architecture](architecture.md) for
ownership and state-machine details.

In the history footer, `/` and `?` search commit metadata and changed paths, including collapsed
files and rename aliases. `n`/`N` repeat the search; matching commits expand temporarily without
opening a diff. Moving to another commit match collapses the previous search-opened commit;
commits already expanded before search stay open. Cancelling a search restores its previous
temporary expansion. Search covers the retained history window and waits for pending file details on
confirmation. Incremental search previews files whose details have already loaded.
