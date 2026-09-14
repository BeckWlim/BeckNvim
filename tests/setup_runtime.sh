#!/usr/bin/env bash

# Sourced by tests/setup.sh after loading the production functions.
run_node_case() (
  local scenario="$1"
  local node_test_directory
  node_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/becknvim-node-test.XXXXXX")"
  trap 'rm -rf -- "${node_test_directory}"' EXIT
  local BECKNVIM_TEMP_DIR="${node_test_directory}"
  local NVM_DIR="${node_test_directory}/nvm"
  export NVM_DIR
  export NODE_TEST_SCENARIO="${scenario}"
  export NODE_TEST_TRACE="${node_test_directory}/trace"
  export NODE_TEST_BIN="${node_test_directory}/new-bin"
  export NODE_TEST_NVM_SOURCE="${node_test_directory}/nvm-fixture.sh"
  mkdir -p "${node_test_directory}/old-bin" "${NODE_TEST_BIN}" "${NVM_DIR}"
  : > "${NODE_TEST_TRACE}"
  cat > "${node_test_directory}/old-bin/node" <<'BASH'
#!/usr/bin/env bash
case "${NODE_TEST_SCENARIO}" in
  compatible) printf 'v22.23.1\n' ;;
  newer) printf 'v24.21.0\n' ;;
  old) printf 'v18.20.0\n' ;;
  missing-npm) printf 'v22.23.1\n' ;;
  broken) exit 1 ;;
  *) exit 127 ;;
esac
BASH
  cat > "${node_test_directory}/old-bin/npm" <<'BASH'
#!/usr/bin/env bash
[[ "${NODE_TEST_SCENARIO}" != 'missing-npm' ]] || exit 127
printf '10.9.8\n'
BASH
  cat > "${NODE_TEST_BIN}/node" <<'BASH'
#!/usr/bin/env bash
printf 'v24.21.0\n'
BASH
  cat > "${NODE_TEST_BIN}/npm" <<'BASH'
#!/usr/bin/env bash
printf '11.19.0\n'
BASH
  chmod +x "${node_test_directory}/old-bin/node" "${node_test_directory}/old-bin/npm" \
    "${NODE_TEST_BIN}/node" "${NODE_TEST_BIN}/npm"
  export PATH="${node_test_directory}/old-bin:${PATH}"
  cat > "${NODE_TEST_NVM_SOURCE}" <<'BASH'
[[ "$1" == '--no-use' && "$-" != *e* && "$-" != *u* ]] || return 1
nvm() {
  printf '%s\n' "$*" >> "${NODE_TEST_TRACE}"
  case "$1" in
    use)
      [[ "${NODE_TEST_SCENARIO}" == 'cached' ]] || return 1
      export PATH="${NODE_TEST_BIN}:${PATH}"
      ;;
    install)
      [[ "$2" == '24' && "${NODE_TEST_SCENARIO}" != 'failed-install' ]] || return 1
      export PATH="${NODE_TEST_BIN}:${PATH}"
      ;;
    alias) [[ "$2 $3" == 'default 24' ]] ;;
    *) return 1 ;;
  esac
}
BASH
  if [[ "${scenario}" != 'fresh' ]]; then
    cp "${NODE_TEST_NVM_SOURCE}" "${NVM_DIR}/nvm.sh"
  fi
  download() {
    [[ "$1" == "https://raw.githubusercontent.com/nvm-sh/nvm/v${BECKNVIM_NVM_VERSION}/install.sh" ]] \
      || die 'unexpected nvm installer source'
    printf 'download\n' >> "${NODE_TEST_TRACE}"
    cat > "$2" <<'BASH'
[[ -z "${NODE_VERSION}" ]] || exit 1
cp "${NODE_TEST_NVM_SOURCE}" "${NVM_DIR}/nvm.sh"
BASH
  }
  if [[ "${scenario}" == 'failed-install' ]]; then
    if (ensure_node) >/dev/null 2>&1; then
      die 'failed nvm installation was accepted'
    fi
  else
    ensure_node
    node_compatible || die 'Node/npm unavailable after setup'
    [[ "$-" == *e* && "$-" == *u* ]] || die 'nvm changed installer shell options'
    local install_trace
    install_trace="$(cat "${NODE_TEST_TRACE}")"
    case "${scenario}" in
      compatible|newer) [[ -z "${install_trace}" ]] || die 'compatible Node was changed' ;;
      cached) [[ "${install_trace}" == 'use --silent default' ]] || die 'cached Node was reinstalled' ;;
      *) [[ "${install_trace}" == *'install 24'* && "${install_trace}" == *'alias default 24'* ]] \
        || die 'Node 24 installation or activation missing' ;;
    esac
    if [[ "${scenario}" == 'fresh' ]]; then
      [[ "${install_trace}" == *'download'* ]] || die 'nvm installer was not used'
    fi
  fi
  printf 'PASS: Node/nvm %s\n' "${scenario}"
)

for scenario in compatible newer old missing-npm missing broken cached fresh failed-install; do
  run_node_case "${scenario}"
done

run_python_case() (
  local scenario="$1"
  local python_test_directory
  python_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/becknvim-python-test.XXXXXX")"
  trap 'rm -rf -- "${python_test_directory}"' EXIT
  local BECKNVIM_USER_BIN="${python_test_directory}/bin"
  local BECKNVIM_TEMP_DIR="${python_test_directory}"
  local PYENV_ROOT="${python_test_directory}/pyenv"
  local installed_version='3.13.7'
  local build_checks=0
  local pyenv_checks=0
  local installs=0
  local expected_installs=1
  mkdir -p "${BECKNVIM_USER_BIN}" "${PYENV_ROOT}/versions/${installed_version}/bin" \
    "${python_test_directory}/old-bin"
  export PYTHON_TEST_SCENARIO="${scenario}"
  export PATH="${BECKNVIM_USER_BIN}:${python_test_directory}/old-bin:${PATH}"
  cat > "${python_test_directory}/old-bin/python3" <<'BASH'
#!/usr/bin/env bash
[[ "${PYTHON_TEST_SCENARIO}" == 'compatible' ]] || exit 1
printf 'Python 3.11.4\n'
BASH
  cat > "${PYENV_ROOT}/versions/${installed_version}/bin/python3" <<'BASH'
#!/usr/bin/env bash
printf 'Python 3.13.7\n'
BASH
  chmod +x "${python_test_directory}/old-bin/python3" \
    "${PYENV_ROOT}/versions/${installed_version}/bin/python3"
  if [[ "${scenario}" == 'regular-file' ]]; then
    cp "${python_test_directory}/old-bin/python3" "${BECKNVIM_USER_BIN}/python3"
  fi
  ensure_pyenv() { pyenv_checks=$((pyenv_checks + 1)); }
  ensure_uv() { die 'Python installation unexpectedly requested uv'; }
  install_python_build_packages() { build_checks=$((build_checks + 1)); }
  pyenv() {
    case "$1" in
      latest)
        if [[ "$2" != '--known' && "${scenario}" != 'cached' ]]; then
          return 1
        fi
        printf '%s\n' "${installed_version}"
        ;;
      install)
        [[ "$*" == "install --skip-existing --verbose ${installed_version}" ]] || die 'unexpected pyenv install'
        [[ "${scenario}" != 'failed-install' ]] || return 1
        installs=$((installs + 1))
        ;;
      prefix) printf '%s/versions/%s\n' "${PYENV_ROOT}" "${installed_version}" ;;
      *) die 'unexpected pyenv command' ;;
    esac
  }
  case "${scenario}" in
    compatible|cached) expected_installs=0 ;;
    failed-install|regular-file)
      if (ensure_python) >/dev/null 2>&1; then
        die "Python setup incorrectly accepted ${scenario}"
      fi
      printf 'PASS: Python/pyenv %s\n' "${scenario}"
      exit 0
      ;;
  esac
  ensure_python
  python_compatible || die 'Python unavailable after setup'
  [[ ${installs} -eq ${expected_installs} && ${build_checks} -eq ${expected_installs} ]] \
    || die 'unexpected Python rebuild or build-package installation'
  if [[ "${scenario}" == 'compatible' ]]; then
    [[ ${pyenv_checks} -eq 0 && ! -e "${BECKNVIM_USER_BIN}/python3" ]] || die 'existing Python changed'
  else
    [[ -L "${BECKNVIM_USER_BIN}/python3" ]] || die 'pyenv Python not exposed on PATH'
  fi
  printf 'PASS: Python/pyenv %s\n' "${scenario}"
)

for scenario in compatible missing cached failed-install regular-file; do
  run_python_case "${scenario}"
done

run_python_build_case() (
  local case_manager="$1"
  local scenario="$2"
  local BECKNVIM_INSTALL_SYSTEM=1
  local installed_packages=''
  local refreshes=0
  [[ "${scenario}" != 'skip-system' ]] || BECKNVIM_INSTALL_SYSTEM=0
  system_package_manager() { printf '%s\n' "${case_manager}"; }
  system_package_installed() { [[ "${scenario}" == 'complete' ]]; }
  run_as_root() {
    [[ "$*" == 'apt-get update' ]] || die 'unexpected build-package command'
    refreshes=$((refreshes + 1))
  }
  install_package_batch() {
    shift
    installed_packages="$*"
    [[ " ${installed_packages} " != *' python3 '* && " ${installed_packages} " != *' python '* ]] \
      || die 'Python runtime requested as a build dependency'
  }
  install_python_build_packages
  if [[ "${scenario}" == 'missing' ]]; then
    [[ -n "${installed_packages}" ]] || die 'missing build packages not installed'
  else
    [[ -z "${installed_packages}" && ${refreshes} -eq 0 ]] || die 'redundant build-package installation'
  fi
  printf 'PASS: Python build packages %s / %s\n' "${case_manager}" "${scenario}"
)
for manager in apt-get dnf pacman zypper brew; do
  for scenario in complete missing skip-system; do
    run_python_build_case "${manager}" "${scenario}"
  done
done
