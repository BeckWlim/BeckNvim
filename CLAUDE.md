# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal Neovim configuration using **lazy.nvim** as the plugin manager. The entry point is `init.lua`, which loads the options, plugin manager, and keymaps.

## Architecture

```
init.lua                        # Entry point
lua/
  config/
    lazy.lua                    # lazy.nvim bootstrap and plugin discovery
    keybindings.lua             # All key mappings (nvim-tree, diagnostics, LSP)
    options.lua                 # Editor, folding, font, and OSC 52 clipboard options
  plugins/                      # Plugin specs loaded via lazy.nvim setup("plugins")
    coding.lua                  # Treesitter, Telescope, Comment, autopairs, and gitsigns
    extra.lua                   # lualine, nvim-tree, toggleterm
    lsp.lua                     # Mason (LSP installer), nvim-cmp completion, LuaSnip snippets
    theme.lua                   # Monokai colorscheme, dashboard-nvim start screen
```

## Plugin Manager (lazy.nvim)

- Plugins are auto-installed on first launch via `lua/config/lazy.lua` (clones lazy.nvim from GitHub stable branch).
- Plugin specs are loaded from `lua/plugins/*.lua` — each file returns a table of plugin specs in lazy.nvim format.
- `lazy-lock.json` pins all plugin commits for reproducible installs.

## Key Configuration Details

### OSC 52 Clipboard (`lua/config/options.lua`)
Uses OSC 52 escape sequences for clipboard integration over SSH/remote connections. This bypasses the system clipboard (`unnamedplus`) and sends copy/paste through the terminal directly.

### LSP Setup
- **Mason** manages LSP server installations. `ensure_installed` in `lua/plugins/lsp.lua` lists auto-installed servers, including `basedpyright` for Python.
- **BasedPyright** automatically uses `<project-root>/.venv/bin/python` when that
  interpreter exists. Project roots are detected from Pyright config files,
  `pyproject.toml`, `setup.py`, or `.git`.
- **nvim-cmp** completion is configured with LuaSnip snippet engine, fed by LSP, path, and buffer sources.
- Keymaps in `lua/config/keybindings.lua`: `gd` (definition), `gD` (declaration), `K` (hover), `gr` (references), `<space>rn` (rename), `<space>D` (type definition), `[d`/`]d` (prev/next diagnostic), `<space>e` (diagnostic float).

### Keymappings
- `<F3>` — toggle nvim-tree file explorer
- `<C-t>` — toggle terminal (toggleterm, horizontal split)
- `<C-i>` / `<C-n>` — next/previous buffer; `<C-e>` — close buffer (via bufferline)
- `<M-e>` — fast-wrap with nvim-autopairs
- nvim-tree auto-closes on `QuitPre`

### Editor Settings
- 4-space indentation, expandtab, autoindent + smartindent
- Line numbers, cursorline, sign column enabled
- Color column at 160, scroll offset of 8 lines
- Smart case-insensitive search, incremental search, no search highlighting
- Hidden buffers allowed (no force-save on switch)
```
