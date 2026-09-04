# Installation

## Requirements

- Neovim 0.11 or newer
- Git, ripgrep, Python 3.10+, curl, wget, and unzip
- make and a C compiler
- Node.js, npm, and the tree-sitter CLI
- CMake and Ninja for C/C++ build workflows
- a Nerd Font; `xclip` on X11 or `wl-clipboard` on Wayland for system clipboard integration

Mason manages language servers for Bash, C/C++, Lua, Markdown, Python, and Vim script. Required
Python and C++ Tree-sitter parsers install when the CLI and compiler are available.

## Install

```bash
mv ~/.config/nvim ~/.config/nvim.bak
git clone https://github.com/BeckWlim/BeckNvim.git ~/.config/nvim
nvim
```

Normal installation honors `lazy-lock.json`; plugin updates are a separate maintenance action.
After the first launch, run `:checkhealth`, `:Lazy check`, and `:Mason`.

Verify the requirement corresponding to a failed feature before clearing caches or reinstalling
plugins. See the repository's `nvim-guide` skill for evidence-based symptom routing.
