#!/usr/bin/env bash

set -Eeuo pipefail

setup_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${setup_root}/setup.sh"
help_output="$(bash "${setup_root}/setup.sh" --help)"
[[ "${help_output}" == *'checks Node.js/npm and Python'* ]] || {
  printf 'setup help does not describe runtime checks\n' >&2
  exit 1
}
for obsolete_option in --with-uv --with-nvm --with-node --with-pyenv; do
  if bash "${setup_root}/setup.sh" "${obsolete_option}" >/dev/null 2>&1; then
    printf 'obsolete option still accepted: %s\n' "${obsolete_option}" >&2
    exit 1
  fi
done

printf 'PASS: setup only checks runtimes and does not manage runtime installers\n'
