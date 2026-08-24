# Repository guidance

This is a personal Neovim configuration using lazy.nvim. Neovim 0.11 or newer is required.

## Architecture

- `init.lua` calls `require('config').setup()` and has no feature logic.
- `lua/config/init.lua` owns startup order: options, autocmds, plugins, then keymaps.
- `lua/plugins/*.lua` contains plugin specs, dependencies, loading conditions, and simple options.
- `lua/config/*.lua` contains behavior that should be reusable and testable.
- `lua/config/project.lua` is the single source of truth for roots, markers, and path containment.
- `lua/config/workspace_symbols.lua` dispatches symbol providers. Python uses
  `lua/config/python_symbols.lua`; other languages fall back to LSP workspace symbols.
- Project audits use `lua/config/project_audit.lua` and the Overseer component under
  `lua/overseer/component/project_audit/`.

Do not put project detection, asynchronous LSP workflows, or custom pickers directly in plugin specs.
See `docs/architecture.md` for extension rules.

## Validation

Run the focused tests without loading plugins:

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

Use the repository `.luarc.json` with Lua Language Server. Also perform a full headless startup check
when plugin declarations or startup wiring change.
