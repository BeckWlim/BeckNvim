# First Install

## Preflight

Verify rather than infer:

- Neovim 0.11 or newer;
- Git;
- Python 3.10 or newer for the Python hierarchy index;
- curl for translation and GitHub metadata;
- ripgrep for text and project-definition search;
- make and a C compiler for native Telescope and parser builds;
- Node/npm plus the tree-sitter CLI for nvim-treesitter main-branch parser builds;
- wget/unzip for Mason downloads;
- a Nerd Font for icons;
- `xclip` on X11 or `wl-clipboard` on Wayland when system clipboard integration is required.

Do not prescribe the README's Ubuntu package command on another distribution. Map these capabilities
to the user's package manager.

## Install sequence

1. Resolve what to do with an existing `~/.config/nvim`. A backup or alternate path is safer than
   overwriting it.
2. Clone the repository into Neovim's config path.
3. Start Neovim. `config.startup.lazy` enables the discovered proxy environment before bootstrapping
   lazy.nvim, then plugins are restored from `lazy-lock.json`.
4. Allow nvim-treesitter to install the required Python and C++ parsers. The tree-sitter CLI and build
   toolchain must already be available.
5. Open `:Mason` and verify the language servers needed for the user's languages.
6. Run `:Lazy check` and `:checkhealth`, then restart once and verify the normal dashboard/editor UI.

Do not run a plugin update merely to complete first installation. Installation should honor pinned
versions; updating is a separate maintenance decision.

## Symptom routing

- lazy.nvim or plugins cannot clone: inspect Git connectivity, exported proxy variables, and
  `:Proxy`; confirm whether the remote uses HTTPS or SSH.
- Tree-sitter highlighting, folds, sticky context, or preview breadcrumbs are absent: check
  `tree-sitter --version`, compiler availability, parser installation, and `:checkhealth`.
- Telescope native sorter fails to build: check make and the C compiler.
- LSP executable is missing: inspect `:Mason`, Node/npm or download tools, and the server-specific
  health output.
- Icons are squares or missing: confirm the terminal/GUI is actually using a Nerd Font.
- Clipboard operations fail: inspect `:checkhealth provider` and install the backend matching X11 or
  Wayland.
- GitHub issues are missing while local Git search works: inspect the origin host, HTTP connectivity,
  proxy state, and rate-limit/auth environment without exposing token values.
- Translation fails: inspect `:Proxy`, curl connectivity, and the rendered provider error; do not
  source shell files from Neovim to work around discovery.

Prefer the first concrete failing check over reinstalling all plugins or deleting caches.
