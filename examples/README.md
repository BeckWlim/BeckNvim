# Recording the highlights

From the repository root:

```bash
bash scripts/record-demos.sh          # regenerate all five GIFs
bash scripts/record-demos.sh markdown # regenerate table and Mermaid demos
bash scripts/record-demos.sh table    # regenerate only the table demo
bash scripts/record-demos.sh mermaid  # regenerate only the Mermaid demo
```

The output goes to `examples/media/`. Git, symbol search, and homepage recordings use a disposable
clone of `~/code/Mooncake`; Markdown uses the bundled `WorkspaceNotes` fixture. The clone shares
Git objects but has its own working files, index, branches, and HEAD. The detached checkout is
performed there, leaving the original repository unchanged. Each scene has separate editor state.

To use a different local **Mooncake** checkout:

```bash
BECKNVIM_DEMO_PROJECT=/path/to/Mooncake bash scripts/record-demos.sh
```

## Prerequisites

- A working BeckNvim installation; complete first-start plugin and parser installation first.
- A local Mooncake checkout for `search`, `git`, and `themes`. The Git scene needs the fetched
  `upstream/codex/placement-mechanism` remote-tracking branch and commit
  `48b3ca329f01bb7c2d1ca27cfdeb59e28a8685e9`.
- GitHub connectivity for the real [Mooncake PR #3704](https://github.com/kvcache-ai/Mooncake/pull/3704).
  The recording reuses the saved `:Proxy` setting and existing GitHub authentication. It performs
  read-only API requests; it does not post comments or change the PR.
- [VHS](https://github.com/charmbracelet/vhs), `ttyd`, `ffmpeg`, and `ffprobe` on `PATH`.
- JetBrains Mono Nerd Font installed on the **recording machine**. A font installed only in your
  SSH client's terminal does not affect VHS.
- Chrome/Chromium runtime libraries. VHS downloads a headless browser if it cannot find one;
  that first run needs network access. A desktop or X11 forwarding is unnecessary.

On Ubuntu, `sudo apt-get install ttyd ffmpeg` installs the recording dependencies. Install VHS
using its [official packages or installation instructions](https://github.com/charmbracelet/vhs#installation).
Install the font for your user:

```bash
mkdir -p ~/.local/share/fonts
curl -fL https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFontMono-Regular.ttf \
  -o ~/.local/share/fonts/JetBrainsMonoNerdFontMono-Regular.ttf
fc-cache ~/.local/share/fonts
```

Alternatively, change `Set FontFamily` in [`tapes/common.tape`](tapes/common.tape) to an installed Nerd Font.

## Scenes

| Tape | Workflow |
| --- | --- |
| [`tapes/search.tape`](tapes/search.tape) | `<Space>fw`: search `submitTransfer`, `MasterService`, and the `PeerLiveness` enum; navigate previews and open definitions |
| [`tapes/git.tape`](tapes/git.tape) | Search the placement branch, inspect a commit, detach HEAD, search `#3704`, read its PR dialog |
| [`tapes/table.tape`](tapes/table.tape) | Navigate wrapped cell text, select and copy a word, quick-edit a value, undo/redo, and save |
| [`tapes/mermaid.tape`](tapes/mermaid.tape) | Navigate and copy a flowchart label, edit the short source, quick-edit prose, and save |
| [`tapes/themes.tape`](tapes/themes.tape) | Browse homepage projects/files, apply Paper Light and TokyoNight, open a recent file |

The [table sample](fixtures/project/docs/table.md) and
[Mermaid sample](fixtures/project/docs/mermaid.md) each fit on one screen at the recording size.
The table demonstrates word wrapping, splitting an oversized identifier, alignment, inline code,
and a link; the five-node flowchart demonstrates
node shapes, a decision, labeled branches, and a merge. Both scenes select visible text and show
the copied word. Table edits return to preview on Esc; diagram labels use the source toggle,
followed by a quick prose edit that returns to preview automatically.

The Mooncake recordings were prepared from local commit
`4078caa3690d37a40257751e5816b2c9d8858863`. The runner records your local HEAD and prints its hash;
refreshed source or remote refs can change results, so review the tape queries when updating the
example. GitHub PR descriptions and discussions are loaded live.

[`session.lua`](session.lua) seeds recent-file history with files from the disposable projects.
It hides diagnostics because the clone has no generated C++ headers or compilation database.
All search results, diffs, PR content, homepage rendering, and diagram layouts use the actual
BeckNvim implementations. Plugins and parsers are reused from the installed configuration.

[`tapes/common.tape`](tapes/common.tape) controls default size, font, and timing. The two Markdown
scenes use a 1200 × 900 canvas with a larger font. Edit scene tapes to change keystrokes or pauses.
Git uses screen waits for detached HEAD and PR loading; startup is hidden.
Increase initial sleeps on slower machines. The runner verifies the detached commit before
publishing the Git GIF to `examples/media/`.

The runner exports VHS's text and cursor frames and combines them with FFmpeg. This works around
VHS 0.12.0 finishing without creating a GIF and makes encoding failures explicit.

Keep the frames and sample repository when adjusting a scene:

```bash
BECKNVIM_DEMO_KEEP=1 bash scripts/record-demos.sh git
```

The script prints the temporary directory. Inspect representative frames or the generated GIF
before committing updated media. GIFs loop automatically; keep each scene focused and short.
