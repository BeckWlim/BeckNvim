# Default Keybindings

The default leader is `\`. Names beginning with `<Space>` use the literal Space key.

## Project and Search

| Key | Action |
| --- | --- |
| `<Space>bt` | Toggle the file tree |
| `<Space>h` | Open the project dashboard |
| `o` / `Enter` on the homepage | Open the selected file or activate the selected project |
| `/` / `?` | Native search forward/backward through the whole current buffer; `n` / `N` repeats |
| `<Space>s` | Flash: type text, then a displayed label to jump to visible text in the current editor |
| `<Space>fn` | Flash: select a Treesitter syntax region using its label |
| `<Space>ff` | Find files |
| `<Space>fg` | Search project text |
| `<Space>fw` | Search project definitions |
| `<Tab>` / `<S-Tab>` | Move between results/preview or Git panes |
| `<C-v>` / `<C-x>` | Open a result in a vertical/horizontal split |
| `<C-q>` | Cancel an input dialog or picker |
| `<Space>o` / `<Space>p` | Jump back / forward within the current Neovim run |
| `<Space>ww` | Choose an existing pane to focus using a/b/c labels |

Jump history starts fresh in each Neovim instance. Recent files, saved marks, registers, and
search history remain available across restarts through ShaDa.

Flash uses lowercase labels. Its shortcuts work in Normal, Visual, and operator-pending modes. For example,
`d<Space>s` uses a labelled target as a delete motion, and `y<Space>fn` yanks a syntax region.
`Esc` or `<C-q>` cancels the standalone Flash prompt. These actions work in ordinary files
and rendered Markdown; panels keep their own interactions. The renderer's adapter lets
`<Space>s` jump through visible text and `<Space>fn` select the original Markdown syntax,
including wrapped tables. A syntax selection yanks or edits the original source range.
Rendered links support backward, counted, and word motions without stopping inside hidden URLs.
BeckNvim owns `<Space>mp`, which calls the renderer's public `preview()` toggle API.

Ordinary `/` and `?` use native search without Flash labels. They search the whole
buffer and may scroll during typing. In rendered Markdown they search the preview directly,
including generated table rows and off-screen matches, and keep it open throughout the search.
`n` / `N` repeat in that same buffer; source mode searches the original Markdown.
`<Space>s` keeps the view in place while choosing visible matches. `s`, `S`, `r`, `R`, `f`, `F`, `t`, `T`, `;`, and `,`
retain their existing behavior; panel searches remain owned by their panels.

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
`Y` copies the selected file or folder's full filesystem path to the system clipboard;
folder paths include a trailing separator.
Telescope searches launched from the tree, such as `<Space>fw`, jump into a code pane with
its line-number settings preserved; cancelling returns to the tree.

File opens from an editor use the current pane. Opens from the tree, file-result searches
launched there, and interactive `:e file` from the tree or terminal show a/b/c labels when several
editor panes are available. The bold labels use a contrasting theme accent. Press a letter to choose,
or `Esc`/`<C-q>` to cancel; one editor is selected automatically, and a panel-only layout creates one.
Cancelling the pane choice leaves files and layout unchanged. `<Space>wq` closes the current file
pane while keeping its buffer available,
or delegates a panel/picker close to its owner. New splits use equal sizes; reopening a split
does not restore an earlier layout's proportions.
`<Space>ww` uses the same labels to switch focus across all existing tiled panes, including
the tree, terminal, and protected editors. `Esc` / `<C-q>` cancels and restores launch focus.
Local-file `gx` asks which existing editor pane to replace when several are available; one editor
is selected automatically. It preserves split proportions and uses the same unsaved-edit guard.

`<C-t>` opens ToggleTerm in shell input mode. Press `Esc` to enter terminal Normal mode, then use
`:e file` or `<Space>ff` to open in an editor pane. The shell buffer and process remain available;
cancelling pane selection returns to terminal Normal mode.

`<Space>fr` follows the same rule when selected from its prompt or preview: launching from the
tree or terminal asks when several editors are available. Ordinary Enter preserves the layout;
`<Space>fv` and `<Space>bv` explicitly open a vertical split from either picker pane.
File, definition, grep, and LSP search prompts, results, and previews use the full editor.
The search covers the project, and ordinary selection returns to the launch pane and preserves split proportions.

Replacing a file through these pickers or typed `:e file` unlists its old buffer once no pane
displays it. The optional write boundary asks “Write this file now? (y/n)” before covering unsaved
edits. Yes writes and continues; No, cancelled input, and failed writes retain the existing view.
The same boundary applies to cross-file `<Space>o` / `<Space>p`; same-file jumps remain available.
Another pane's view and explicit splits retain their buffers.

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
| `<Space>de` | Search branches, commits, issues, and pull requests over the current graph or detail view |
| `<Space>df` | Current-file history with rename tracking |
| `<Space>ds` | Current-symbol line history |
| `<Space>dr` | Merge-aware repository graph and commit preview |
| `j` / `k` | Move through commits or branches |
| `o` / `<Enter>` | Focus the selected commit preview; in commit detail, open the selected file |
| `<Space>db` | Toggle the branch pane below the graph |
| Branch `o` / `Enter` | Review the selected local or remote branch without switching |
| Branch `f` | Fetch remotes explicitly |
| `<Space>dn` | Open native commit details in Diffview |
| `y` / `Y` in a Diffview file list | Copy the cursor file or folder's name / full absolute path to the clipboard |
| `y` on a commit row | Copy the full commit hash in the graph or Diffview history list |
| `<Space>dm` | Guarded checkout of the list/preview commit in graph or detail; switch/track in the branch pane |
| `<Space>dp` | Hide or restore the Diffview history list |
| `<Space>dv` | From commit list or message preview, open that commit's file diffs; toggle back to graph |
| `:q` | Close the complete Git mode from any graph or Diffview pane |
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
mode keeps source visible and edits unsaved; press `<Space>mp` to render again. This also applies
after `Esc`, `<C-c>`, a cancelled operator, or an edit that makes no change.
Use `u` / `<C-r>` to undo/redo source edits while remaining in preview, and `:w` or `:update` to save
the underlying Markdown file. Visual selections and yanks refer to displayed text; switch to raw
source with `<Space>mp` before editing a visual selection or using other source Ex commands.
Temporary Normal mode with `<C-o>` stays in the editing buffer.
`q`, `<C-q>`, or `<Space>mp` returns to source in the same pane; `<Space>mp` renders it again.
Source mode stays raw after editing and Flash syntax selection until you toggle it back.
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
| `p` / `P` | Paste after/before the cursor in Normal mode; uses the selected clipboard provider with `unnamedplus` |
| `<C-r>+` | Paste from the clipboard provider in Insert mode or a command-line prompt (`/`, `?`, `:`) |
| `<C-c>` | Return from Insert, Visual, or Select mode to Normal mode using normal Escape cleanup; keeps Telescope open |
| `q` | Exit Visual mode; retains macro recording in Normal mode |
| `a` | Enter Insert mode after the cursor (native append) |

Inside tmux, Neovim uses tmux's clipboard provider so yanks reach the attached terminal,
including over SSH. Direct SSH sessions use OSC 52; local sessions outside tmux use
the desktop clipboard. To paste local clipboard text over SSH, enter Insert mode and
use the terminal's Paste action; reading the clipboard with `p` depends on terminal support.

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
