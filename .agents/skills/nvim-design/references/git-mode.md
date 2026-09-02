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
- `<Space>o` remains the ordinary jumplist-back operation in Git mode. Interactive `:q` must not
  detach one Diffview window from the lifecycle.
- `<Space>fw` remains the global project-definition search in Git and editor panes. Do not install a
  historical-buffer override or let one survive the return boundary.

`config.git.panel` owns these transitions. Do not add a second stack or make an issue/detail float
manage the Diffview lifecycle itself.

Ordinary-history exit resolves the currently rendered `AFTER` file, that pane's cursor, its enclosing
declaration, and the cursor's relative line distance from that declaration before teardown; footer
cursor position does not select a different file or line. Restore and redraw the editor buffer first.
While Git is still visible, reuse an editor window already displaying the working file or load and
stage that buffer hidden in the preserved editor tab. Switch tabs only after the final buffer owns
the selected editor window; do not expose an old buffer, scratch buffer, or other intermediate view.
Resolve lualine's branch state inside that staged editor window before switching so the first editor
frame does not depend on a later picker or buffer transition.
Because staging may run Diffview buffer hooks, remove Git-owned buffer-local mappings only after the
working-tree buffer is installed and before the editor redraw. Match both key and Git-owned
description so unrelated editor-local mappings survive; global `<Space>de` and `<Space>fw` must be
available immediately after return.
If the restored global `<Space>de` is invoked before view disposal settles, retain one keyed re-entry
action and release it once at the settled boundary. Do not poll or queue duplicate Git transitions.
Only after a successful redraw, asynchronously match the declaration's first line once in the
working file and reapply the relative line distance. Prefer normalized declaration text, then use the
shared definition parser's name/kind with Tree-sitter hierarchy for a changed-signature or duplicate
symbol. Fall back to the rendered line when the match is absent or ambiguous. Before moving the
cursor, confirm that the restored tab, window, and buffer are still current so the callback cannot
outlive its target. Compute the final position before moving, then apply cursor placement, fold
reveal, and centering as one editor-window transaction followed by one redraw; never render an
intermediate cursor position. Only after that frame completes, log the completed alignment through
the ordinary `vim.notify` message area used by `:q` guidance and clear it after a bounded delay.
Refresh lualine's checked-out branch as part of
restoration, and log the render-gated cursor alignment in the Git footer before teardown. Do not
release the cursor task until Diffview disposal finishes; reassert branch state from the guarded
editor target at that boundary before scheduling the jump. If the target is still rendering, keep
Git mode mounted, cancel unrelated footer enrichment, show the pending return in the footer, and
update readiness from Diffview's next file/layout event rather than polling or jumping later without
another explicit `<C-q>`.

## Module ownership

- `init.lua`: editor entry points, branch review, guarded checkout, and workflow orchestration.
- `events.lua`: small asynchronous public port for editor-owned lifecycle consumers; never expose
  raw Diffview callbacks through it.
- `lifecycle.lua`: generation-checked render, return, and anchor phases plus structured logging.
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

Treat Git mode as a plugin-like subsystem. Main editor configuration may invoke its public entry
points or subscribe through the stable `config.git.on(...)` event port, but must not coordinate Diffview
file events, enrichment tokens, render sequences, or teardown callbacks itself.

## History and footer

All history entry points use Diffview's File History panel and code renderer:

- `<Space>df`: file-filtered history with `--follow`;
- `<Space>ds`: symbol-filtered line trace with Git `-L`;
- `<Space>dr`: bounded repository history;
- `<Space>de`: repository history with the temporary search dispatcher above it.

The footer presentation is consistent across scopes: commit rows can reveal child file rows, the
selected commit stays visible, and the code panes show the selected file's parent/commit comparison.
Preserve the FILE/SYMBOL filters as commit selectors. Enrich their resulting entries with Diffview's
unfiltered parent-to-commit file loader so every changed file is available beneath its commit. Keep
the initial footer collapsed on matching commit rows; do not automatically select the scoped file
during initial rendering. When the user explicitly expands an entry, select and render its scoped
child automatically, keep that child highlighted, and annotate it with a right-pinned match tag and
reference-colored filename. Apply annotations to every expanded entry, not only the selected file.
Add non-displacing branch-tip separators. Keep current checkout state in the one-line winbar and
append the branch segment under the footer cursor there. Keep review/scope metadata on a stable second
colored virtual line above the list instead of displacing it when the active branch segment changes.
For SYMBOL,
remove `-L` patch folds so the code pane uses ordinary full-file folding, and focus the traced
declaration only after the scoped file is opened.

The winbar and stable metadata line communicate the active scope:

- `LOCAL · FILE · <path>`;
- `LOCAL · SYMBOL · <label> · <path>:<start>-<end>`;
- `<source> · BRANCH · <branch>`;
- `CURRENT BRANCH · <branch> · <source> · BRANCH REVIEW · <branch> · TIP · <hash>`;
- `CURRENT · DETACHED · <hash> · <source> · BRANCH REVIEW · <branch> · TIP · <hash>`;
- `<source> · REPOSITORY`.

Keep selected rows on the same neutral-grey cursor-line background used by Telescope and the editor.
Within that shared plane, use saturated semantic foregrounds for add/change/delete status, counters,
and hashes so the footer does not become uniformly grey. Commit metadata and search previews use
aligned semantic columns for source, kind, hash/branch, date, and title. Raw `git log` or `git show`
output must be parsed before rendering.

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

`<Space>dn` is a read-only footer action. Reuse Diffview's native selected-commit detail panel and
preserve the ordinary history beneath it; `<C-q>` closes the detail before history.

Search selection must not detach, switch a branch, or exit Git mode.

## Explicit mutations

`<Space>dm` is the commit-list checkout action. Resolve the commit and inspect porcelain-v2 HEAD and
worktree state before mutation. Reject staged, unstaged, untracked, or unsaved-buffer changes when a
move is required.

- If the selected commit is already the attached branch HEAD, keep the branch attached.
- If detached HEAD already equals the target, skip the duplicate switch.
- Otherwise use `git switch --detach <commit>`.

When HEAD is detached, retain the checked-out hash as view state. Mark only its commit row through
Diffview's existing highlighted reference field with `(DETACHED HEAD)`, and show
`CURRENT · DETACHED · <hash>` in the footer winbar instead of an attached-branch label. Keep the
reviewed ref and its tip separate from this current anchor.
After a detached checkout, rebuild the mounted history even when it already contains the target;
otherwise its pre-checkout `HEAD -> branch` decoration remains stale. Select the target only after
the refreshed list owns current Git decorations. Keep in-place focusing for read-only review.
Keep the mutation transition active until the requested commit's diff render completes. Cancel old
view enrichment immediately, but dispose the old history only after the replacement render is ready
so it cannot invalidate a same-named Diffview buffer still being created. Show the pending `ANCHOR`
stage in the footer, write concise lifecycle notices to `:messages`, and write timed
resolve/status/ref/switch/render stages through Diffview's logger for `:DiffviewLog`. On an incomplete
render, unlock safely and report whether the HEAD update already completed. If a detached target is
exactly a containing local branch tip, attach that branch through the explicit `<Space>dm` mutation;
do not create a branch for a remote-only ref.
Do not focus the selected anchor while the successor's automatic initial file render is still open;
wait for that file to finish before starting the selected-commit render, or Diffview may invalidate
one of its own concurrently created buffers.
Prepare exact branch ref/source/tip metadata when branch review opens and retain it as view-owned
anchor-plan state. `<Space>dm` must reuse that plan instead of searching all refs that contain the
commit. Recheck live dirty/HEAD state and verify a local tip before attachment; a context-free exact
commit remains detached without guessing a branch. Detached-history discovery may search refs, with
local branches taking precedence over remote-tracking refs. Keep the former history alive through
the successor's render, then retire it after readiness is confirmed. The successor must render the
prepared exact ref, retain its tip, and select the detached commit inside that full list so commits
ahead of the anchor appear during the same mutation cycle.

Branch result selection is read-only: replace ordinary history with the selected local or
remote-tracking ref without fetching, creating a tracking branch, or invoking `git switch`. Retain
the actual attached branch or detached hash as separate view state. When detached HEAD is contained
by the selected ref, mount enough history to keep that commit selected; otherwise open the branch at
its normal tip. `<Space>dm` remains the only Git-mode action that changes the real commit anchor.

## Code-pane rendering

The left pane is the selected commit's parent (`BEFORE`); the right is the selected commit (`AFTER`).
Winbars put role and abbreviated revision before the truncatable file path.

Reuse the actual Tree-sitter context renderer in focused historical buffers. The pinned context uses
the shared restrained light-green declaration background with a distinct green lower boundary.
Suppress editor-wide whole-scope backgrounds in
`diffview://` buffers, while retaining syntax foregrounds, one cursor-line background, and restrained
add/change/delete backgrounds. Reveal the enclosing modified definition through folds; file/repository
history keeps the cursor on the changed line, while symbol history focuses the definition.
