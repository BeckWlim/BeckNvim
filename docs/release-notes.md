# BeckNvim v0.1.0

Initial release, dated 2026-09-15.

## Highlights

- Project dashboard, recent projects, file browsing, and project context preserved across editor views.
- File, text, symbol, definition, reference, and recursive type-hierarchy search.
- Git history and Diffview review, including branch, commit, issue, and pull-request inspection.
- LSP completion, diagnostics, type information, and language-aware navigation.
- Tree-sitter highlighting, folds, pinned syntax context, and structural selection.
- Markdown previews with responsive tables, semantic-color Mermaid diagrams, pinned headings,
  and source editing in the same pane.
- Integrated terminal, translation, proxy management, and project diagnostics.

## Stabilization

- Hardened Git review lifecycle, asynchronous loading, dirty-worktree previews, and return behavior.
- Corrected pull-request commit inspection and Markdown scrolling.
- Stabilized Markdown table rendering, diagram completion, and source navigation.
- Updated setup to reuse compatible external tools and leave plugin and language-server bootstrap
  to Neovim's first launch.

## Installation and dependencies

Follow the [installation instructions](../README.md#installation). Use `./setup.sh --check` to
inspect the local dependencies.

The installer requires Neovim 0.12.0 or newer, Node.js 22 or newer with npm, Python 3.10 or newer,
and Tree-sitter CLI 0.26.1 or newer. Mermaid rendering uses the compatible BeckWlim Termaid fork.
Use a Nerd Font for icons.

The release includes `lazy-lock.json` for plugin revisions. In the original v0.1.0 installer,
Termaid defaulted to `main`, with `BECKNVIM_TERMAID_REF` selecting a revision. Current development
manages Termaid through lazy.nvim and records its revision in the plugin lockfile (see
[Mermaid installation](architecture.md#markdown-mermaid-feature)). Other external tools and
Mason-managed language servers remain separate; a BeckNvim tag alone does not pin the whole toolchain.

## Validation

Validated on 2026-09-15 with Neovim 0.12.4:

- Shell syntax checks and setup tests passed.
- The full Lua test suite, including the binding audit, passed.
- Headless startup with the installed configuration passed.
- Installed Markdown/Mermaid integration passed outside the sandbox. The sandboxed run stalled
  during embedded UI attachment.
- Documentation links and whitespace checks passed.

Release checks are documented in [Development](development.md). This validation does not establish
fresh-install coverage on every supported operating system.
