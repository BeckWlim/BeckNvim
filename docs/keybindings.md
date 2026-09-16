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
`i` returns to the source position beneath the cursor and enters Insert mode immediately.
`q`, `<C-q>`, or `<Space>mp` returns to source in the same pane; `<Space>mp` renders it again.
Movement, selection, scrolling,
and copying displayed text use normal Neovim behavior. Tables and diagrams refresh after source edits
and preview resizing, applying background updates after navigation pauses briefly. Pinned section
titles and `<Space>cc` also work in the rendered view.
Rendered rows keep your editor line-number settings, and `<Space>h` opens the dashboard from either
Markdown mode.

## Editing

| Key | Action |
| --- | --- |
| `q` | Exit Visual mode; retains macro recording in Normal mode |
| `a` | Disabled in Normal mode; use `i` or `A` to enter Insert mode |

Use `:map` and plugin help to inspect context-specific mappings without duplicating upstream docs.
