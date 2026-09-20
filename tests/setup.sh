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

# Load setup functions without running the installer. Each case gets fresh state.
test_tree_sitter_install() (
  local scenario="$1"
  source <(sed '/^main; exit$/d' "${setup_root}/setup.sh") --skip-system
  local npm_install_calls=0
  local npm_version_calls=0
  local -a npm_install_args=()

  command() {
    if [[ "$1" == '-v' && "$2" == 'tree-sitter' ]]; then
      [[ "${scenario}" == 'existing' || "${scenario}" == 'outdated' ]]
    elif [[ "$1" == '-v' && "$2" == 'npm' ]]; then
      [[ "${scenario}" != 'missing-npm' ]]
    else
      builtin command "$@"
    fi
  }
  tree_sitter_version() {
    if [[ "${scenario}" == 'outdated' ]]; then
      printf '0.25.0\n'
    else
      printf '0.26.11\n'
    fi
  }
  npm() {
    if [[ "$1" == '--version' ]]; then
      npm_version_calls=$((npm_version_calls + 1))
      [[ "${scenario}" != 'broken-npm' ]]
    else
      npm_install_calls=$((npm_install_calls + 1))
      npm_install_args=("$@")
      [[ "${scenario}" != 'failed-install' ]]
    fi
  }
  download() { printf 'unexpected direct download\n' >&2; exit 1; }
  cargo() { printf 'unexpected Cargo invocation\n' >&2; exit 1; }

  ensure_tree_sitter
  case "${scenario}" in
    existing|missing-npm|broken-npm)
      [[ ${npm_install_calls} -eq 0 ]]
      [[ ${BECKNVIM_NEEDS_PATH_PROMPT} -eq 0 ]]
      if [[ "${scenario}" != 'broken-npm' ]]; then
        [[ ${npm_version_calls} -eq 0 ]]
      fi
      ;;
    install|outdated|failed-install)
      [[ ${npm_version_calls} -eq 1 && ${npm_install_calls} -eq 1 ]]
      [[ ${#npm_install_args[@]} -eq 5 ]]
      [[ "${npm_install_args[0]}" == 'install' ]]
      [[ "${npm_install_args[1]}" == '--global' ]]
      [[ "${npm_install_args[2]}" == '--prefix' ]]
      [[ "${npm_install_args[3]}" == "${BECKNVIM_USER_BIN%/bin}" ]]
      [[ "${npm_install_args[4]}" == "tree-sitter-cli@${BECKNVIM_TREE_SITTER_VERSION}" ]]
      if [[ "${scenario}" == 'failed-install' ]]; then
        [[ ${BECKNVIM_NEEDS_PATH_PROMPT} -eq 0 ]]
      else
        [[ ${BECKNVIM_NEEDS_PATH_PROMPT} -eq 1 ]]
      fi
      ;;
  esac
  printf 'PASS: Tree-sitter CLI %s\n' "${scenario}"
)

for scenario in existing missing-npm broken-npm install outdated failed-install; do
  test_tree_sitter_install "${scenario}"
done
