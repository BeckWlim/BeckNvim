---
name: nvim-guide
description: Guide first installation, environment validation, troubleshooting, and advanced daily use of this Neovim configuration. Use when setting up a new machine, diagnosing plugin/parser/LSP/network failures, explaining key workflows, or teaching complex Git, search, project, proxy, translation, and syntax-context behavior. Do not use for implementing architecture changes.
---

# Neovim Setup and Usage

Give environment-specific, evidence-backed guidance. Read `README.md` first and verify the installed
tools before recommending changes. Do not assume Ubuntu, a display server, shell, proxy, or package
manager when the environment can be inspected.

## Choose the path

- For a new machine or broken first startup, read
  [references/first-install.md](references/first-install.md).
- For keymaps, panel transitions, Git review, search, proxy management, or other advanced workflows,
  read [references/advanced-usage.md](references/advanced-usage.md).
- For configuration development or render architecture, use the project skill
  `nvim-design` instead.

## Guidance rules

- Distinguish prerequisite installation, Neovim bootstrap, plugin installation, parser installation,
  Mason-managed language servers, and optional desktop integration. Diagnose the failing layer before
  changing another.
- Treat replacing `~/.config/nvim`, installing system packages, changing shell startup files, and
  updating plugins as explicit mutations. Explain or request authority before performing them.
- Preserve `lazy-lock.json` during normal installation. If the user intentionally runs `:Lazy update`,
  include the resulting lockfile change in review.
- Reuse Git's own SSH and proxy configuration for Git operations. The shared `:Proxy` session state
  applies to HTTP-backed application features and future child processes; it is not a replacement for
  repository authentication.
- Never request that tokens be pasted into a buffer or command line. Refer to `GH_TOKEN` or
  `GITHUB_TOKEN` environment configuration without echoing its value.
- When explaining a complex workflow, describe the visible state, the next key, whether the action is
  read-only or mutating, and how to return. Avoid presenting a flat key list without lifecycle context.

## Verify a setup

Use the narrowest relevant checks, then end with a full startup check:

```sh
nvim --version
git --version
rg --version
curl --version
tree-sitter --version
nvim --headless -u init.lua '+qa'
```

Inside Neovim, use `:checkhealth`, `:Lazy check`, and `:Mason`. For repository development, also run
the headless test suite documented in the architecture skill. Report which checks passed, which tool
is missing, and which features that missing tool affects.
