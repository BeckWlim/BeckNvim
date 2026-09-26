# Markdown renderer comparison plan

Status: planned; no personal settings or installed plugins changed.

## Use the existing local development selector

`config.user` reads and caches `~/.nvim`; `config.startup.lazy` passes its development settings
to lazy.nvim. The renderer declaration leaves `dev` unset, so these settings already control
which local directory supplies its code. No plugin-spec edit, lockfile edit, custom launcher,
or managed-install replacement is needed.

The current personal settings are `NVIM_DEV=false`, `NVIM_DEV_PATH=~/.config`, and
`NVIM_DEV_PLUGINS=BeckWlim/termaid`. Record the actual settings again before testing and preserve
all other entries, including proxy settings. These are assignments in `~/.nvim`, not shell
environment overrides.

Use two independent checkouts whose final directory name is `render-markdown.nvim`:

| Variant | Checkout | NVIM_DEV_PATH |
| --- | --- | --- |
| Fork | Existing `~/dev/render-markdown.nvim` | `~/dev` |
| Upstream | Separate `~/dev/upstream/render-markdown.nvim` | `~/dev/upstream` |

If the upstream checkout does not exist, create it without modifying the fork:

```bash
mkdir -p ~/dev/upstream
git clone https://github.com/MeanderingProgrammer/render-markdown.nvim.git \
  ~/dev/upstream/render-markdown.nvim
```

Record both commit hashes with `git -C <checkout> rev-parse HEAD`. The previous comparison used
upstream v8.14.0 (`640a3ec6d538bad17c328be373c7cad0293d9589`) and fork
`b40bccacb6dae7ff7906fa616e66a2026423f4e7`. Use that upstream revision for reproduction, or
record the new revision when checking whether upstream behavior has changed. Do not reset a
dirty local checkout.

For each variant, edit only the three development assignments in `~/.nvim`:

```bash
NVIM_DEV=true
NVIM_DEV_PATH=~/dev
NVIM_DEV_PLUGINS=BeckWlim/render-markdown.nvim
```

For upstream, change only `NVIM_DEV_PATH` to `~/dev/upstream`. Keep the selection pattern
`BeckWlim/render-markdown.nvim`: it matches BeckNvim's declared plugin URL, even when the local
directory contains upstream code. Select only the renderer for this comparison so other local
plugins are not looked up under the alternate parent. Missing checkouts produce an error because
development fallback is disabled.

## Verify each session before comparing

Restart Neovim without a file argument after changing `~/.nvim`. Load the renderer explicitly:

```vim
:lua require('lazy').load({ plugins = { 'render-markdown.nvim' } })
:lua local p = require('lazy.core.config').plugins['render-markdown.nvim']; print(p.dir, p.dev)
```

Confirm the expected directory and `true`. The URL displayed by Lazy remains the declared fork
URL, so the directory and its Git commit are the evidence of which implementation is loaded.

Apply identical, session-only reading settings before opening the fixture:

```vim
:lua require('render-markdown').setup({ anti_conceal = { enabled = false }, win_options = { wrap = { default = false, rendered = false }, linebreak = { default = false, rendered = false }, concealcursor = { default = 'nvic', rendered = 'nvic' } } })
:edit ~/.config/nvim/examples/fixtures/project/docs/table.md
:setlocal wrap? linebreak? concealcursor?
```

Use the same window size, font, source file, and cursor actions. Verify `nowrap`, `nolinebreak`,
and `concealcursor=nvic` in each session. The fork enables its projected preview by default;
upstream renders in the source buffer. Do not use `<Space>mp` for this comparison: BeckNvim maps
it to `preview()`, whose behavior differs between the implementations. Use `:RenderMarkdown toggle`
if an explicit enable/disable comparison is needed. Do not run Lazy update, sync, or restore during
the experiment.

## Compare the reading interaction

1. Start above the table. Confirm both implementations wrap long cells and preserve alignment.
2. Search `/whole`, then use `j` and `k`. Observe cursor movement and whether the layout changes.
3. Return to `whole`, use `viw`, then `y`; inspect the actual register with `:echo @0`.
4. Leave the table with `gg`. Check whether rows expand back into rendered content.
5. Repeat at a narrower window width. Keep the source unchanged throughout.

Previously verified behavior: upstream wraps cells even with native `wrap` disabled, but reveals
the active replacement row regardless of `anti_conceal.enabled`. The fork keeps actual preview
lines navigable and selectable. Treat this as an interaction comparison, not a performance claim.

If recording a GIF, label each implementation and revision, show the same actions, and disclose
native wrapping and anti-conceal settings. Capture actual editor output and verify the yank and
unchanged source. Keep generated media only if it is needed for the issue reply.

Mermaid can be a separate fork demonstration using `examples/fixtures/project/docs/mermaid.md`.
Verify Termaid executable discovery first. Upstream has no equivalent built-in Termaid projection;
do not present that demonstration as a like-for-like interaction comparison.

## Restore

Close the comparison sessions and restore the original three development assignments in `~/.nvim`.
Restart normally and inspect the renderer directory again. With development disabled, it should
resolve to the managed fork. Confirm `git status --short` in BeckNvim has no new configuration or
lockfile changes. Keep the existing fork checkout; remove only disposable artifacts created for
the comparison when no longer needed.
