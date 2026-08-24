# Repository Guidance

This repository contains a personal Neovim configuration managed by lazy.nvim. Neovim 0.11 or
newer is required.

## Architecture

- `init.lua` calls `require('config').setup()`.
- `lua/config/init.lua` owns startup order: options, autocmds, plugins, then keymaps.
- `lua/config/` contains reusable and testable feature behavior.
- `lua/plugins/*.lua` contains plugin specifications, dependencies, loading conditions, and
  lightweight setup calls.
- `lua/config/project.lua` is the source of truth for roots, markers, and path containment.
- `lua/config/workspace_symbols.lua` owns Telescope project-definition search.
- `lua/config/query_picker.lua` owns immediate, incremental, cancellable picker sessions.
- `lua/config/lsp_locations.lua` owns semantic LSP location queries and fast local references.
- `lua/config/type_hierarchy.lua` owns C++ LSP and Python indexed hierarchy pickers.
- `lua/config/python/hierarchy_index.lua` owns the background Python AST index lifecycle.
- `lua/config/lsp.lua` owns language-server behavior and BasedPyright diagnostic policy.
- `lua/config/translation.lua` owns direct translation requests, proxy injection, and query UI.
- `lua/config/audit/` contains project and diagnostic audit modules.

## Project Definition Contract

`<Space>fw` opens a Telescope picker backed by parallel, language-specific ripgrep jobs. The finder
covers Python, C/C++/CUDA, Lua, Shell, Vim script, and Markdown definitions. Two-character input uses
prefix matching, longer input uses containment, and each query supplies up to 1,000 candidates.
Result rows contain the definition name, symbol kind, and project-relative path; Telescope provides
the source preview. Ripgrep callbacks schedule result delivery on Neovim's main loop, and picker
readiness activates after Telescope setup.

LSP navigation follows its own mapping path. Cancelable Telescope LSP sessions serve `gd`, `gD`,
`gr`, `gI`, `<Space>i`, and `<Space>D`.
They open before dispatching requests; `gr` merges document highlights before the full reference
request completes, seeds Python function-local candidates from Treesitter, and replaces provisional
candidates when semantic results arrive. `q` closes the picker after cancelling outstanding work.

## Engineering Boundaries

- Keep project detection in `lua/config/project.lua`.
- Keep asynchronous workflows and custom pickers in responsibility-focused `lua/config/` modules.
- Keep plugin specifications focused on dependencies, loading conditions, and module setup.
- Add focused fixtures and tests with every project-definition language extension.
- Preserve stable semantic roles and static types for parameters and local bindings.

See `docs/architecture.md` for the complete ownership and extension model.

## Validation

Run the focused tests with a minimal Neovim runtime:

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

Run Lua Language Server with the repository `.luarc.json`. Plugin declarations and startup wiring
also receive a full headless startup check and keymap verification.
