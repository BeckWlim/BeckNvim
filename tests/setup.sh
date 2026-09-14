#!/usr/bin/env bash

set -Eeuo pipefail

readonly SETUP_TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Load declarations only; never run the installer, sudo, or network operations.
for function_name in dependency_available system_package_manager install_package_batch \
  install_system_packages version_at_least tree_sitter_version ensure_tree_sitter \
  termaid_compatible ensure_termaid node_version node_compatible ensure_node python_compatible \
  ensure_python ensure_pyenv system_package_installed install_python_build_packages; do
  source <(sed -n "/^${function_name}() {$/,/^}$/p" "${SETUP_TEST_ROOT}/setup.sh")
done
source <(sed -n '/^readonly BECKNVIM_MINIMUM_TREE_SITTER_VERSION=/p' "${SETUP_TEST_ROOT}/setup.sh")
source <(sed -n '/^readonly BECKNVIM_TERMAID_REPOSITORY=/p' "${SETUP_TEST_ROOT}/setup.sh")

source <(sed -n '/^activate_nvm_node() ($/,/^)/p' "${SETUP_TEST_ROOT}/setup.sh")
source <(sed -n '/^readonly BECKNVIM_.*NODE.*=/p; /^readonly BECKNVIM_NVM_VERSION=/p; /^readonly BECKNVIM_.*PYTHON.*=/p' "${SETUP_TEST_ROOT}/setup.sh")

log() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }

run_package_case() (
  local case_manager="$1"
  local scenario="$2"
  local BECKNVIM_INSTALL_CLIPBOARD=1
  local WAYLAND_DISPLAY=''
  local DISPLAY=''
  local expected_packages=''
  local installed_packages=''
  local refresh_count=0
  local expected_refresh_count=0

  case "${scenario}" in
    complete) ;;
    missing-rg) expected_packages=' ripgrep' ;;
    missing-node|missing-npm|missing-python) ;;
    wayland) WAYLAND_DISPLAY='wayland-0'; DISPLAY=':0'; expected_packages=' wl-clipboard' ;;
    x11) DISPLAY=':0'; expected_packages=' xclip' ;;
    headless) ;;
    skip-clipboard) BECKNVIM_INSTALL_CLIPBOARD=0; WAYLAND_DISPLAY='wayland-0'; DISPLAY=':0' ;;
    *) die "unknown package scenario: ${scenario}" ;;
  esac
  if [[ "${case_manager}" == 'brew' && ( "${scenario}" == 'wayland' || "${scenario}" == 'x11' ) ]]; then
    expected_packages=''
  fi
  if [[ "${case_manager}" == 'apt-get' && -n "${expected_packages}" ]]; then
    expected_refresh_count=1
  fi

  system_package_manager() { printf '%s\n' "${case_manager}"; }
  dependency_available() {
    case "$1" in
      node|npm|python|python-venv) return 1 ;;
      rg) [[ "${scenario}" != 'missing-rg' ]] ;;
      wl-copy|xclip) return 1 ;;
      *) return 0 ;;
    esac
  }
  record_packages() {
    local package_name
    [[ $# -gt 0 ]] || die 'empty package installation'
    for package_name in "$@"; do
      installed_packages+=" ${package_name}"
      case "${package_name}" in
        node|nodejs|npm|python|python3|python3-venv) die 'runtime requested from system package manager' ;;
      esac
    done
  }
  run_as_root() {
    case "$1" in
      apt-get)
        [[ "$*" == 'apt-get update' ]] || die 'unexpected apt command'
        refresh_count=$((refresh_count + 1))
        return
        ;;
      env)
        [[ "$1 $2 $3 $4 $5" == 'env DEBIAN_FRONTEND=noninteractive apt-get install -y' ]] \
          || die 'unexpected apt installation command'
        [[ ${refresh_count} -eq 1 ]] || die 'apt cache not refreshed exactly once'
        shift 5
        ;;
      dnf) [[ "$2 $3" == 'install -y' ]] || die 'unexpected dnf command'; shift 3 ;;
      pacman) [[ "$2 $3 $4" == '-Syu --needed --noconfirm' ]] || die 'unexpected pacman command'; shift 4 ;;
      zypper) [[ "$2 $3" == '--non-interactive install' ]] || die 'unexpected zypper command'; shift 3 ;;
      *) die "unexpected root invocation: $*" ;;
    esac
    record_packages "$@"
  }
  brew() {
    [[ "$1" == 'install' ]] || die 'unexpected brew invocation'
    shift
    record_packages "$@"
  }

  install_system_packages
  [[ "${installed_packages}" == "${expected_packages}" ]] \
    || die "${case_manager}/${scenario}: expected '${expected_packages}', got '${installed_packages}'"
  [[ ${refresh_count} -eq ${expected_refresh_count} ]] || die 'unexpected package refresh'
  printf 'PASS: %s / %s\n' "${case_manager}" "${scenario}"
)

for manager in apt-get dnf pacman zypper brew; do
  for scenario in complete missing-rg missing-node missing-npm missing-python wayland x11 headless skip-clipboard; do
    run_package_case "${manager}" "${scenario}"
  done
done

run_tree_sitter_case() (
  local cli_version="$1"
  local BECKNVIM_USER_BIN='/nonexistent/becknvim-test-bin'
  tree-sitter() {
    [[ "$*" == '--version' ]] || die 'unexpected tree-sitter arguments'
    printf 'tree-sitter %s\n' "${cli_version}"
  }
  platform_asset() { die 'attempted installation despite compatible Tree-sitter on PATH'; }
  ensure_tree_sitter
  printf 'PASS: existing Tree-sitter %s on PATH\n' "${cli_version}"
)
for cli_version in 0.26.1 0.26.11 0.27.0; do
  run_tree_sitter_case "${cli_version}"
done

run_termaid_case() (
  local scenario="$1"
  local BECKNVIM_USER_BIN='/nonexistent/becknvim-test-bin'
  local BECKNVIM_TERMAID_REF=''
  local uv_checks=0
  local installs=0
  local expected_installs=1
  local expected_ref='main'
  local expected_refresh=''
  local GIT_HTTP_LOW_SPEED_LIMIT=''
  local GIT_HTTP_LOW_SPEED_TIME=''
  case "${scenario}" in
    compatible) expected_installs=0 ;;
    incompatible|missing|broken) ;;
    custom-timeout) GIT_HTTP_LOW_SPEED_TIME=120 ;;
    explicit-ref) BECKNVIM_TERMAID_REF='v1.2.3'; expected_ref='v1.2.3'; expected_refresh=' --refresh' ;;
  esac
  termaid() {
    [[ "$*" == '--help' ]] || die 'unexpected termaid arguments'
    case "${scenario}" in
      incompatible|custom-timeout) printf 'old help\n' ;;
      missing) return 127 ;;
      *) printf 'styled-json --strict-width --fit-mode --max-height\n' ;;
    esac
    [[ "${scenario}" != 'broken' ]]
  }
  ensure_uv() { uv_checks=$((uv_checks + 1)); }
  python3() { printf '/test/python3\n'; }
  uv() {
    [[ "$*" == "tool install --force --verbose --python /test/python3 --no-python-downloads${expected_refresh} git+${BECKNVIM_TERMAID_REPOSITORY}@${expected_ref}" ]] \
      || die 'incorrect Termaid source or install options'
    [[ ${GIT_HTTP_LOW_SPEED_LIMIT} -eq 1 ]] || die 'Git stall threshold missing'
    if [[ "${scenario}" == 'custom-timeout' ]]; then
      [[ ${GIT_HTTP_LOW_SPEED_TIME} -eq 120 ]] || die 'custom Git timeout overridden'
    else
      [[ ${GIT_HTTP_LOW_SPEED_TIME} -eq 60 ]] || die 'Git stall timeout missing'
    fi
    installs=$((installs + 1))
  }
  ensure_termaid
  [[ ${uv_checks} -eq ${expected_installs} && ${installs} -eq ${expected_installs} ]] \
    || die "unexpected Termaid/uv installation: ${scenario}"
  printf 'PASS: Termaid %s\n' "${scenario}"
)
for scenario in compatible incompatible missing broken explicit-ref custom-timeout; do
  run_termaid_case "${scenario}"
done

source "${SETUP_TEST_ROOT}/tests/setup_runtime.sh"

(
  node() { return 1; }
  if dependency_available node; then
    die 'broken runtime counted as available'
  fi
  cc() { return 1; }
  gcc() { printf 'gcc test\n'; }
  dependency_available c || die 'working compiler fallback ignored'
  printf 'PASS: runtime probes reject broken tools and accept compiler alternatives\n'
)

(
  entrypoint_test_directory="$(mktemp -d "${TMPDIR:-/tmp}/becknvim-entrypoint-test.XXXXXX")"
  trap 'rm -rf -- "${entrypoint_test_directory}"' EXIT
  entrypoint_test_script="${entrypoint_test_directory}/setup.sh"
  cat > "${entrypoint_test_script}" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
BECKNVIM_MODE='install'
BECKNVIM_INSTALL_SYSTEM=1
BECKNVIM_USER_BIN="${1}/bin"
BECKNVIM_USER_OPT="${1}/opt"
BECKNVIM_ORIGINAL_PATH="${BECKNVIM_USER_BIN}"
BECKNVIM_TEMP_DIR=''
trap 'rm -rf -- "${BECKNVIM_TEMP_DIR}"' EXIT
log() { printf '%s\n' "$*"; }
warn() { :; }
install_system_packages() { :; }
ensure_node() { :; }
ensure_python() { :; }
ensure_neovim() { :; }
ensure_tree_sitter() { :; }
# Simulate the script changing while the installer is executing a slow step.
ensure_termaid() { printf '\n;;;;\n' >> "$0"; }
run_checks() { printf 'dependency checks completed\n'; }
nvim() { printf 'setup unexpectedly launched Neovim\n' >&2; exit 1; }
bootstrap_plugins() { printf 'setup unexpectedly bootstrapped plugins\n' >&2; exit 1; }
BASH
  sed -n '/^main() {$/,/^}$/p' "${SETUP_TEST_ROOT}/setup.sh" >> "${entrypoint_test_script}"
  tail -n 1 "${SETUP_TEST_ROOT}/setup.sh" >> "${entrypoint_test_script}"
  entrypoint_output="$(bash "${entrypoint_test_script}" "${entrypoint_test_directory}")"
  [[ "${entrypoint_output}" == *'dependency checks completed'* \
    && "${entrypoint_output}" == *'Open nvim; lazy.nvim and Mason will install missing plugins and language servers'* \
    && "${entrypoint_output}" == *'Setup complete'* ]] \
    || die 'installer did not complete after its script changed'
  if bash -n "${entrypoint_test_script}" 2>/dev/null; then
    die 'regression fixture did not introduce the intended syntax error'
  fi
  printf 'PASS: running installer completes even if its script is edited\n'
  printf 'PASS: setup leaves plugin and language-server installation to Neovim\n'
)
