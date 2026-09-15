# Themes

Run `:Theme` to preview themes. Move through the results to recolor the workspace; press Enter
to apply and save. `<C-q>` in any mode cancels and restores the previous theme and
light/dark setting. `:Theme paper-light` applies and saves directly. Monokai remains the default
when no choice has been saved.

## Included choices

| Choice | Source |
| --- | --- |
| `monokai` | [vim-monokai](https://github.com/crusoexia/vim-monokai), the existing default |
| `vscode-dark` | [vscode.nvim](https://github.com/Mofiqul/vscode.nvim), VS Code Dark+ |
| `darcula-dark` | [darcula-dark.nvim](https://github.com/xiantang/darcula-dark.nvim), JetBrains-style Darcula |
| `tokyonight-night` | [TokyoNight](https://github.com/folke/tokyonight.nvim) |
| `catppuccin-mocha`, `catppuccin-latte` | [Catppuccin](https://github.com/catppuccin/nvim) |
| `gruvbox-dark` | [gruvbox.nvim](https://github.com/ellisonleao/gruvbox.nvim) |
| `paper-light` | BeckNvim's softer warm-grey palette, using the built-in Morning scheme |

For a less bright light theme, use `:Theme paper-light`. Its background is `#E6E3DB`, with
charcoal text and subdued syntax accents. The footer, selections, and grey pinned-context tint
follow this base. Catppuccin Mocha and TokyoNight Night provide modern dark choices; Latte is
the remaining upstream light option. Retained upstream presets keep their original palettes.

Theme dependencies are declared in `lua/plugins/theme.lua` and pinned in `lazy-lock.json`.
The picker lists bundled and personal preset files plus the current selection. Loading a plugin
does not add all its other variants to the picker. Native `:colorscheme` still applies upstream
schemes temporarily; `:Theme {name}` can apply and save either a preset or a native colorscheme.

## Add a theme file

```text
themes/
├── default/                Bundled presets tracked by Git
│   ├── monokai.lua
│   ├── vscode-dark.lua
│   ├── paper-light.lua
│   └── ...
├── my-theme.lua            User preset ignored by Git
└── README.md
```

Create `themes/my-theme.lua` directly in this folder:

```lua
return {
  colorscheme = 'monokai',
  background = 'dark',
}
```

Use `:Theme my-theme`, or reopen `:Theme` to see the new file. The filename is the preset name;
no registration or restart is needed. A user file takes precedence over a bundled preset with
the same name. These are ordinary Lua configuration files.

For a custom base palette, add a `palette` table with all eight RGB colors:

```lua
return {
  colorscheme = 'monokai',
  background = 'dark',
  palette = {
    background = 0x272822, foreground = 0xF8F8F2,
    red = 0xF92672, green = 0xA6E22E, yellow = 0xE6DB74,
    blue = 0x66D9EF, purple = 0xAE81FF, orange = 0xFD971F,
  },
}
```

The highlight owner applies this base schema to editor syntax, diagnostics, Git, and terminal
colors. All project surfaces derive from it, including completion, search, file tree, statusline,
Markdown, and Mermaid. Pinned context uses a subtle grey tint of the editor background, with
readable text and a contrasting boundary; it has no fixed panel background.

To include another upstream theme, add its declaration to `lua/plugins/theme.lua`, let lazy.nvim
install it, and create a preset referencing its colorscheme. To share a new bundled preset, put it
under `themes/default/`.

## Overrides and saved selection

For project-wide overrides, pass a callback to the theme setup call in `lua/config/init.lua`:

```lua
require('config.ui.theme').setup({
  default = 'monokai',
  overrides = function(colors)
    return {
      RenderMarkdownMermaidEdge = { fg = colors.syntax.type, bg = colors.block },
    }
  end,
})
```

Overrides are applied after shared highlights on each theme change. The callback receives the
resolved palette so overrides can follow the selected theme too.

Opening a file does not reload its theme or read preset files. Loaded Lua theme modules are reused;
preset files are read when selecting or restoring a theme. Shared highlights refresh on a theme
change or when a plugin first loads, independently of the opened file's size.

Confirmed choices are saved asynchronously to `stdpath('state')/theme.json`, outside this
repository. Previewing and cancelling never writes a preference. Invalid or unavailable saved
themes fall back to the configured default. `.gitignore` excludes `themes/*.lua` user files;
`themes/default/*.lua` and this guide stay tracked.
