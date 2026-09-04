# First Install

Read [Installation](../../../../docs/installation.md) as the canonical requirements and bootstrap
guide. Verify tools on the actual machine before recommending a package manager command.

Route failures by layer:

- plugin clone: Git connectivity, SSH/HTTPS configuration, proxy environment;
- parser/highlight/fold: tree-sitter CLI, compiler, parser health;
- Telescope native sorter: make and C compiler;
- language server: Mason health and server runtime dependencies;
- icons or clipboard: terminal font and display-server clipboard provider;
- GitHub or translation: HTTP route, proxy state, authentication environment.

Honor `lazy-lock.json` during installation. Treat plugin updates, replacing an existing config, and
shell/proxy changes as separate explicit mutations.
