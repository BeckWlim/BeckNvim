# Advanced Usage

Explain workflows by visible state and return path. The default leader is `\`; `<Space>` mappings use
the literal space key.

## Project and search workflow

- `<Space>h` opens the project dashboard. Use its drawer for recent projects/files and `f` for the
  shared folder picker.
- `<Space>ff`, `<Space>fg`, and `<Space>fw` find files, text, and project definitions. `<Tab>` moves
  between Telescope results and the real preview; `<C-v>`/`<C-x>` open vertical/horizontal splits.
- `gd`, `gD`, `gr`, and `gI` remain LSP navigation. `<Space>fw` is project-definition search, including
  historical buffers while inside Git mode.
- `<Space>cc` walks outward through syntax context. Pinned class/function context in editor, search
  preview, and Git code panes shares the same renderer and visual policy.

## Git workflow

Git mode preserves an ordinary history layer below temporary search:

```text
editor ← Git history ← search or issue detail
```

Enter with:

- `<Space>df` for rename-following current-file history;
- `<Space>ds` for the current function/class line trace;
- `<Space>dr` for repository history;
- `<Space>de` for repository history plus the branch/commit/issue dispatcher.

The footer always uses commit → file rows. FILE and SYMBOL headers expose their active filter. Use
`<Tab>`/`<S-Tab>` between footer and code panes, `<Enter>` to expand a commit or render its file, and
`<Space>dp` to collapse/restore the footer.

Inside Git mode, `<Space>de` opens search. A branch preview contains commits and files; a commit
preview contains changed files; `#<digits>` combines exact Git subject matches with the origin's
GitHub issue or pull request. Selecting a commit only reviews and highlights it. Selecting an issue
opens readable Markdown. `<C-q>` returns one layer: issue/search → history → editor.

Mutation is explicit:

- `<Space>dm` checks out the selected commit after dirty-state guards. Current branch HEAD stays
  attached; an older commit uses detached HEAD.
- Selecting a branch result uses safe `git switch`, creating a local tracking branch only for a
  remote-only ref.

If checkout or branch switching is refused, save/discard modified buffers and resolve staged,
unstaged, or untracked work deliberately; never recommend forcing the transition.

## Proxy, GitHub, and translation

`:Proxy` shows effective HTTP/HTTPS/fallback routes and NO_PROXY state. `<Enter>` selects or edits a
session route; `direct`, `off`, or `none` disables proxying for the session. Persistent changes belong
in the user's shell environment. Applying a choice refreshes the manager; `q` or `<C-q>` closes it.

Git commands retain native Git/SSH behavior. GitHub issue metadata and translation use the shared
HTTP proxy environment. Private GitHub repositories or higher API limits can use `GH_TOKEN` or
`GITHUB_TOKEN` from the process environment; never display the value.

`<Space>t` opens translation. Network/provider errors render inside its window so they can be
diagnosed without searching Neovim messages.

## Returning safely

- In ordinary Telescope/float surfaces, normal `q` closes; prompt insert mode keeps `q` as input and
  uses `<C-q>` where configured.
- In Git mode, `<C-q>` pops the active Git/search layer and `<Space>o` leaves the workflow.
- Do not use `:q` to dismantle one pane of a combined Diffview workspace.
