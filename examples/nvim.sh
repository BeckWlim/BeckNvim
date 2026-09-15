#!/usr/bin/env bash
set -euo pipefail
: "${BECKNVIM_DEMO_ROOT:?Run scripts/record-demos.sh first}"
: "${BECKNVIM_DEMO_WORK:?Run scripts/record-demos.sh first}"

# Reuse installed plugins and parsers, with disposable history and preferences.
export XDG_STATE_HOME="$BECKNVIM_DEMO_WORK/state/${BECKNVIM_DEMO_SCENE}"
export XDG_CACHE_HOME="$BECKNVIM_DEMO_WORK/cache/${BECKNVIM_DEMO_SCENE}"
if [[ -f "${BECKNVIM_DEMO_PROXY_FILE:-}" ]]; then
  mkdir -p "$XDG_STATE_HOME/nvim"
  cp "$BECKNVIM_DEMO_PROXY_FILE" "$XDG_STATE_HOME/nvim/proxy.json"
fi
cd "${BECKNVIM_DEMO_CWD:?Run scripts/record-demos.sh first}"
exec nvim -n -i NONE \
  --cmd 'lua vim.opt.rtp:prepend(vim.env.BECKNVIM_DEMO_ROOT)' \
  -u "$BECKNVIM_DEMO_ROOT/init.lua" \
  -c 'lua dofile(vim.env.BECKNVIM_DEMO_ROOT .. "/examples/session.lua")' "$@"
