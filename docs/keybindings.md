# Default Keybindings

The default leader is `\`. Names beginning with `<Space>` use the literal Space key.

## Project and Search

| Key | Action |
| --- | --- |
| `<Space>h` | Open the project dashboard |
| `<Space>ff` | Find files |
| `<Space>fg` | Search project text |
| `<Space>fw` | Search project definitions |
| `<Tab>` / `<S-Tab>` | Move between results/preview or Git panes |
| `<C-v>` / `<C-x>` | Open a result in a vertical/horizontal split |
| `<C-q>` | Close the active UI layer |
| `<Space>o` / `<Space>p` | Jump back / forward within the current Neovim run |

Jump history starts fresh in each Neovim instance. Recent files, saved marks, registers, and
search history remain available across restarts through ShaDa.

## Git Mode

The history entry keys are editor entry points and do not mount a second Git pane while Git mode is
already active.

| Key | Action |
| --- | --- |
| `<Space>de` | Search branches, commits, issues, and pull requests |
| `<Space>df` | Current-file history with rename tracking |
| `<Space>ds` | Current-symbol line history |
| `<Space>dr` | Bounded repository history |
| `<Enter>` | Native Diffview expand/collapse or child-file open |
| `<Space>dn` | Open native commit details |
| `<Space>dm` | Guarded checkout of the selected commit |
| `<Space>dp` | Collapse or restore the footer |
| `<Space>o` | Normal jumplist back |

## Language and Tools

| Key/command | Action |
| --- | --- |
| `gd` / `gD` | Go to definition/declaration |
| `gr` / `gI` | Find references/go to implementation |
| `<Space>rn` | Rename symbol |
| `<Space>cc` | Walk outward through syntax context |
| `<Space>vj` / `<Space>vl` | Select the identifier at the cursor; repeat to move to the previous/next identifier |
| `gx` | Open a local path or URI; GitHub records prefer the editor detail float |
| `<Space>mp` | Switch the current pane between rendered Markdown and editable source |
| `<Space>t` | Open Chinese/English translation |
| `:Proxy` | Inspect or change the session HTTP proxy |
| `:Theme` | Preview bundled and personal themes; Enter saves, `<C-q>` cancels in every mode |
| `:Theme {name}` | Apply a theme immediately and save it for the next startup |

Markdown files open with prose, tables, and diagrams rendered by default. Source mode shows all
Markdown punctuation for editing. `Enter` moves to the next line while keeping the preview rendered.
Common Normal-mode edit keys (`i`/`I`, `a`/`A`, `o`/`O`, `c`, `d`, `s`, `x`, `r` and their uppercase
forms, `p`/`P`, `J`, `~`, `.`, `>`, `<`, `=`, `gu`, `gU`, `g~`) first restore the source at the mapped
cursor position. Counts, registers, and operator motions apply to raw Markdown. Returning to Normal
mode restores preview, keeping edits unsaved; this includes `Esc` or `<C-c>` after Insert mode.
Use `u` / `<C-r>` to undo/redo source edits while remaining in preview, and `:w` or `:update` to save
the underlying Markdown file. Visual selections and yanks refer to displayed text; switch to raw
source with `<Space>mp` before editing a visual selection or using other source Ex commands.
Temporary Normal mode with `<C-o>` stays in the editing buffer.
`q`, `<C-q>`, or `<Space>mp` returns to source in the same pane; `<Space>mp` renders it again.
Explicit source mode stays raw after editing until you toggle it back.
Movement, selection, scrolling,
and copying displayed text use normal Neovim behavior. Tables and diagrams refresh after source edits
and preview resizing, applying background updates after navigation pauses briefly. Pinned section
titles and `<Space>cc` also work in the rendered view.
Quick edits reuse the preview buffer and unchanged objects. Pending diagrams retain their previous
canvas and reserve provider-estimated space while background rendering finishes.
Rendered rows keep your editor line-number settings, and `<Space>h` opens the dashboard from either
Markdown mode.

## Editing

| Key | Action |
| --- | --- |
| `q` | Exit Visual mode; retains macro recording in Normal mode |
| `a` | Disabled in Normal mode; use `i` or `A` to enter Insert mode |

Use `:map` and plugin help to inspect context-specific mappings without duplicating upstream docs.
