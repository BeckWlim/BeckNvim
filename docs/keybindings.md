# Default Keybindings

The default leader is `\`. Names beginning with `<Space>` use the literal Space key.

## Project and Search

| Key | Action |
| --- | --- |
| `<Space>bt` | Toggle the file tree |
| `<Space>h` | Open the project dashboard |
| `o` / `Enter` on the homepage | Open the selected file or activate the selected project |
| `<Space>s` | Search forward in the current buffer (`/`); `n` / `N` repeats forward/backward |
| `<Space>ff` | Find files |
| `<Space>fg` | Search project text |
| `<Space>fw` | Search project definitions |
| `<Tab>` / `<S-Tab>` | Move between results/preview or Git panes |
| `<C-v>` / `<C-x>` | Open a result in a vertical/horizontal split |
| `<C-q>` | Close the active UI layer |
| `<Space>o` / `<Space>p` | Jump back / forward within the current Neovim run |

Jump history starts fresh in each Neovim instance. Recent files, saved marks, registers, and
search history remain available across restarts through ShaDa.

## Command-line completion

For `:e` filename completion, `Tab` / `Shift-Tab` or `Ctrl-N` / `Ctrl-P` select a match.
`Ctrl-Y` accepts it without running the command; continue typing or use Down Arrow to enter a
directory while the menu is open. Up Arrow returns to its parent. `Enter` executes `:e`.

## Tree panels

Git history, Diffview's file panel, NvimTree, and the project picker preview share these actions:

| Key | Action |
| --- | --- |
| `o` / `Enter` | Toggle a parent or open a file |
| `zo` / `zc` / `za` | Expand / collapse / toggle the current parent |
| `zR` / `zM` | Expand / collapse all available parents |

In NvimTree, `o` / `Enter` opens a file while keeping focus and selection in the tree.
Telescope searches launched from the tree, such as `<Space>fw`, jump into a code pane with
its line-number settings preserved; cancelling returns to the tree.

Git history, NvimTree, and the focused project preview also share `/`, `?`, and `n`/`N` for
searching collapsed paths. Search-opened parents collapse when moving to a different match;
manually expanded parents stay open. Cancelling restores the previous expansion.
Filesystem discovery uses ripgrep, respects ignore files, skips `.git`, and caps discovery at
5,000 files. NvimTree search omits hidden files; the project preview includes them. Incremental
search uses known paths; confirming searches undiscovered paths asynchronously. A new search
refreshes discovery; `n`/`N` reuse the results.

Expansion stays bounded by the owning panel: Git uses retained commits, NvimTree its native
folder-discovery limit, and the project preview folders whose children have already loaded.
The project picker's main prompt continues to select projects; these tree keys apply in its preview.

## Git Mode

The history entry keys are editor entry points and do not mount a second Git pane while Git mode is
already active.

| Key | Action |
| --- | --- |
| `<Space>de` | Search branches, commits, issues, and pull requests |
| `<Space>df` | Current-file history with rename tracking |
| `<Space>ds` | Current-symbol line history |
| `<Space>dr` | Bounded repository history |
| `h` / `j` / `k` / `l` | Move the history cursor left / down / up / right |
| `o` / `<Enter>` | Native Diffview expand/collapse or child-file open |
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

### Windows

| Key | Action |
| --- | --- |
| `<Space>wh` / `wj` / `wk` / `wl` | Focus the window left/down/up/right |
| `<Space>rh` / `rl` | Decrease/increase current window width by 5 columns |
| `<Space>rj` / `rk` | Increase/decrease current window height by 3 rows |
| `<Space>r=` | Equalize window sizes |

Resize keys change the current window's size; the border that moves depends on the split layout.

### Cursor and input

| Key | Action |
| --- | --- |
| `<C-a>` / `<C-e>` | Move to beginning/end of line in Normal, Visual, Insert, and command-line modes, including Telescope input |
| `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | Move left/down/up/right in Normal, Visual, and Insert modes |
| `p` / `P` | Paste after/before the cursor in Normal mode; uses the system clipboard with `unnamedplus` |
| `<C-r>+` | Paste the system clipboard in Insert mode or a command-line prompt (`/`, `?`, `:`) |
| `<C-c>` | Return from Insert, Visual, or Select mode to Normal mode using normal Escape cleanup; keeps Telescope open |
| `q` | Exit Visual mode; retains macro recording in Normal mode |
| `a` | Enter Insert mode after the cursor (native append) |

`<C-a>` goes before indentation. Visual mode extends the selection; Insert mode dismisses
completion before moving. These replace native number increment (`<C-a>`) and scroll-down
(`<C-e>`) shortcuts in Normal/Visual mode.
In Telescope input, `<C-h>` / `<C-l>` move within the query
and `<C-j>` / `<C-k>` move down/up through results, matching the arrow keys.

Clipboard paste uses native keys: press `Ctrl+r`, then `+` to read the `+` register.
In Insert mode, `Ctrl+r`, `Ctrl+o`, then `+` preserves pasted indentation.
`Ctrl+p` retains completion navigation in Insert mode, history navigation in command-line
prompts, and the previous-result action in Telescope.

Use `:map` and plugin help to inspect context-specific mappings without duplicating upstream docs.
