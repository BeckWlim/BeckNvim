# Git Mode Reference

Read this reference when changing `config.git`, Diffview integration, Git search, GitHub issue
rendering, or Git-mode key behavior.

## State model

Git mode has three visible levels but only two Git-owned panel layers:

```text
editor ← ordinary Git history ← temporary search
                                  └─ issue detail (alternate search renderer)
```

- Ordinary Git history is the durable layer. It owns the Diffview tab, code panes, and File History
  footer.
- Telescope results/preview and issue detail are alternate renderers of one temporary search layer.
  They must return to the preserved history view rather than reconstructing or closing it.
- `<C-q>` pops exactly one active layer. From history it returns to the editor; from search or issue
  detail it returns to history.
- `<Space>o` leaves Git mode. Interactive `:q` must not detach one Diffview window from the lifecycle.

`config.git.panel` owns these transitions. Do not add a second stack or make an issue/detail float
manage the Diffview lifecycle itself.

## Module ownership

- `init.lua`: editor entry points, branch switching, guarded checkout, and workflow orchestration.
- `repository.lua`: Git command construction, process boundary, and machine-output parsing.
- `diffview.lua`: history view lifecycle, footer/code-pane behavior, selection, and Git-mode mappings.
- `search.lua`: Telescope session, async result assembly, preview dispatch, and read-only selection.
- `ui.lua`: structured branch/commit/file/issue rows and semantic highlights.
- `github.lua`: origin-derived GitHub metadata boundary and proxy-aware requests.
- `issue.lua`: Markdown detail rendering and related-issue navigation.
- `panel.lua`: UI-layer stack and pop semantics.

Keep Git transport in Git so SSH configuration and Git proxy behavior remain native. Use the shared
HTTP proxy environment only for GitHub requests. Never expose authentication tokens in process
arguments, rendered buffers, or notifications.

## History and footer

All history entry points use Diffview's File History panel and code renderer:

- `<Space>df`: file-filtered history with `--follow`;
- `<Space>ds`: symbol-filtered line trace with Git `-L`;
- `<Space>dr`: bounded repository history;
- `<Space>de`: repository history with the temporary search dispatcher above it.

The footer presentation is consistent across scopes: commit rows can reveal child file rows, the
selected commit stays visible, and the code panes show the selected file's parent/commit comparison.
Do not obtain consistency by removing FILE/SYMBOL filters. Preserve Diffview's single-file/line-trace
navigation state and adapt only the entry presentation data through its existing render/redraw path.

Footer winbars communicate the active scope:

- `LOCAL · FILE · <path>`;
- `LOCAL · SYMBOL · <label> · <path>:<start>-<end>`;
- `<source> · BRANCH · <branch>`;
- `<source> · REPOSITORY`.

Keep selected rows on the shared Diffview selection background. Commit metadata and search previews
use aligned semantic columns for source, kind, hash/branch, date, and title. Raw `git log` or
`git show` output must be parsed before rendering.

## Search and selection

`<Space>de` is the Git dispatcher. Its Telescope surface always has a list and preview. Branch
previews contain commits and changed files; commit previews contain structured files; issues preview
Markdown.

An exact `#<digits>` query combines local Git subject matches across local and remote-tracking refs
with the GitHub issue/pull request for the origin project. Enforce a digit boundary and subject-only
filter so body matches and longer numbers do not leak in. Tag candidates `LOCAL` or `REMOTE`.

Selecting a search commit is read-only:

- if it is already present, retain the complete mounted list and highlight it in place;
- otherwise mount its complete owning-branch history, or its ancestry when no branch is known, and
  highlight it there;
- keep an empty commit in the list while rendering an empty code area.

Search selection must not detach, switch a branch, or exit Git mode.

## Explicit mutations

`<Space>dm` is the commit-list checkout action. Resolve the commit and inspect porcelain-v2 HEAD and
worktree state before mutation. Reject staged, unstaged, untracked, or unsaved-buffer changes when a
move is required.

- If the selected commit is already the attached branch HEAD, keep the branch attached.
- If detached HEAD already equals the target, skip the duplicate switch.
- Otherwise use `git switch --detach <commit>`.

Branch result selection uses non-forced `git switch`; remote-only refs create their local tracking
branch. Preserve Git's own conflict refusal and the editor's modified-buffer guard. After a successful
switch or checkout, remain in Git mode with a complete branch commit list and the target highlighted.

## Code-pane rendering

The left pane is the selected commit's parent (`BEFORE`); the right is the selected commit (`AFTER`).
Winbars put role and abbreviated revision before the truncatable file path.

Reuse the actual Tree-sitter context renderer in focused historical buffers. The pinned context uses
the shared light-green background without underline. Suppress editor-wide whole-scope backgrounds in
`diffview://` buffers, while retaining syntax foregrounds, one cursor-line background, and restrained
add/change/delete backgrounds. Reveal the enclosing modified definition through folds; file/repository
history keeps the cursor on the changed line, while symbol history focuses the definition.
