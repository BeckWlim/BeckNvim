# Configuration Architecture

The repository separates startup assembly, reusable feature modules, and plugin declarations.

```text
init.lua
lua/
├── config/                       Reusable, testable feature modules
│   ├── init.lua                  Startup assembly
│   ├── options.lua               Editor options
│   ├── autocmds.lua              Global events
│   ├── lazy.lua                  Plugin manager bootstrap
│   ├── keybindings.lua           Global keymap assembly
│   ├── workspace_symbols.lua     Project-definition finder
│   ├── python/                   Python environment resolution
│   └── audit/                    Project scan and diagnostic audit modules
└── plugins/*.lua                 Plugin dependencies and loading conditions
```

## Module Ownership

| Module | Responsibility |
| --- | --- |
| `config/project.lua` | Project roots, path containment, and project markers |
| `config/workspace_symbols.lua` | Project-wide definition search and Telescope result entries |
| `config/telescope.lua` | Telescope defaults and keymap assembly |
| `config/lsp.lua` | Language-server configuration and BasedPyright diagnostic policy |
| `config/python/environment.lua` | Python interpreter and environment resolution |
| `config/audit/project.lua` | Batch project analysis and Overseer task coordination |
| `config/audit/diagnostic.lua` | Diagnostic-cache inspection and project reporting |
| `plugins/*.lua` | Plugin specifications, dependencies, conditions, and lightweight setup calls |

## Project Definition Search

`config.workspace_symbols` owns the `<Space>fw` workflow:

```text
<Space>fw
  → Telescope definition prompt
  → parallel language-specific ripgrep jobs
  → extension-aware definition parser
  → name / kind / relative-path result row
  → source preview
```

The query policy is shared across every supported language:

- Python, C/C++/CUDA, Lua, Shell, Vim script, and Markdown participate in each query.
- Two-character input uses a definition-name prefix.
- Longer input uses definition-name containment.
- A query emits up to 1,000 Telescope candidates.
- A new prompt cycle retires the previous generation and releases its active jobs.
- Search results enter Telescope through Neovim's scheduled main-loop callbacks.
- Picker readiness activates after Telescope setup; an earlier invocation reports its loading state.

LSP navigation has a separate ownership path: `gd` and `gD` call native definition and declaration
operations, while `gr` and `gI` use Telescope LSP pickers.

## Extension Rules

Place plugin declarations in `plugins/` and feature behavior in a responsibility-focused `config`
module. Extend project-definition support by adding the file globs, definition pattern, parser, and
focused fixture to `config.workspace_symbols` and `tests/workspace_symbols.lua`.

Project-root markers belong to `config/project.lua`. Language-specific server markers remain with
their server configuration in `config/lsp.lua`. Mason installation coverage is maintained in the
same LSP module.

Project audits share project context through `config.project`; each audit module owns its own task
or diagnostic state.

## Validation

Run the focused suite with a minimal Neovim runtime:

```bash
nvim --headless -u NONE -i NONE -l tests/run.lua
```

Use the repository `.luarc.json` for Lua Language Server checks. Startup-related changes also
receive a full headless startup check, keymap assertions, and an end-to-end query in a representative
project.
