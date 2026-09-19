#!/usr/bin/env bash

set -Eeuo pipefail

readonly BECKNVIM_USER_BIN="${HOME}/.local/bin"
readonly BECKNVIM_USER_OPT="${HOME}/.local/opt"
readonly BECKNVIM_MINIMUM_NODE_VERSION='22.0.0'
readonly BECKNVIM_MINIMUM_PYTHON_VERSION='3.10.0'
readonly BECKNVIM_MINIMUM_NVIM_VERSION='0.12.0'
readonly BECKNVIM_NVIM_VERSION='0.12.2'
readonly BECKNVIM_MINIMUM_TREE_SITTER_VERSION='0.26.1'
readonly BECKNVIM_TREE_SITTER_VERSION='0.26.11'

BECKNVIM_MODE='install'
BECKNVIM_INSTALL_SYSTEM=1
BECKNVIM_INSTALL_CLIPBOARD=1
BECKNVIM_TEMP_DIR=''
BECKNVIM_FAILURES=0
BECKNVIM_NEEDS_PATH_PROMPT=0

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Install and validate BeckNvim's core external tools.

Options:
  --check           Validate dependencies without changing the system
  --skip-system     Do not install operating-system packages
  --skip-clipboard  Do not install X11 or Wayland clipboard providers
  -h, --help        Show this help

The setup checks Node.js/npm and Python for optional LSP and Termaid features.
It does not install runtime managers or language runtimes. Install LSP servers
explicitly through :Mason. Termaid uses uv when available, otherwise Python.
EOF
}

log() {
  printf '[BeckNvim] %s\n' "$*"
}

warn() {
  printf '[BeckNvim] warning: %s\n' "$*" >&2
}

die() {
  printf '[BeckNvim] error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${BECKNVIM_TEMP_DIR}" && -d "${BECKNVIM_TEMP_DIR}" ]]; then
    rm -rf -- "${BECKNVIM_TEMP_DIR}"
  fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) BECKNVIM_MODE='check' ;;
    --skip-system) BECKNVIM_INSTALL_SYSTEM=0 ;;
    --skip-clipboard) BECKNVIM_INSTALL_CLIPBOARD=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

run_as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "sudo is required to install system packages"
  fi
}

dependency_available() {
  local dependency="$1"
  case "${dependency}" in
    c) cc --version >/dev/null 2>&1 || gcc --version >/dev/null 2>&1 ;;
    cxx) c++ --version >/dev/null 2>&1 || g++ --version >/dev/null 2>&1 ;;
    build-tools)
      dependency_available c && dependency_available cxx && dependency_available make
      ;;
    certificates)
      [[ -s /etc/ssl/certs/ca-certificates.crt || -s /etc/pki/tls/certs/ca-bundle.crt \
        || -s /etc/ssl/ca-bundle.pem || -s /etc/ssl/cert.pem ]]
      ;;
    unzip) unzip -v >/dev/null 2>&1 ;;
    wl-copy|xclip) command -v "${dependency}" >/dev/null 2>&1 ;;
    *) "${dependency}" --version >/dev/null 2>&1 ;;
  esac
}

system_package_manager() {
  local manager
  for manager in apt-get dnf pacman zypper brew; do
    if command -v "${manager}" >/dev/null 2>&1; then
      printf '%s\n' "${manager}"
      return
    fi
  done
  die 'unsupported package manager; use --skip-system after installing the README requirements'
}

install_package_batch() {
  local manager="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  log "Installing missing packages with ${manager}: $*"
  case "${manager}" in
    apt-get) run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) run_as_root dnf install -y "$@" ;;
    pacman) run_as_root pacman -Syu --needed --noconfirm "$@" ;;
    zypper) run_as_root zypper --non-interactive install "$@" ;;
    brew) brew install "$@" ;;
  esac
}

install_system_packages() {
  local manager
  manager="$(system_package_manager)"
  # Each entry pairs a package name with the capability it provides.
  local -a specifications=(cmake:cmake curl:curl git:git ripgrep:rg unzip:unzip)
  case "${manager}" in
    apt-get)
      specifications+=(build-essential:build-tools ninja-build:ninja pkg-config:pkg-config)
      ;;
    dnf)
      specifications+=(gcc:c gcc-c++:cxx make:make ninja-build:ninja
        pkgconf-pkg-config:pkg-config)
      ;;
    pacman)
      specifications+=(base-devel:build-tools ninja:ninja pkgconf:pkg-config)
      ;;
    zypper)
      specifications+=(gcc:c gcc-c++:cxx make:make ninja:ninja
        pkg-config:pkg-config)
      ;;
    brew)
      specifications+=(gcc:c gcc:cxx make:make ninja:ninja pkg-config:pkg-config)
      ;;
  esac
  if [[ "${manager}" != 'brew' ]]; then
    specifications+=(ca-certificates:certificates gzip:gzip tar:tar)
    if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 1 ]]; then
      if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        specifications+=(wl-clipboard:wl-copy)
      elif [[ -n "${DISPLAY:-}" ]]; then
        specifications+=(xclip:xclip)
      fi
    fi
  fi

  local specification package_name capability
  local -a packages=()
  for specification in "${specifications[@]}"; do
    package_name="${specification%%:*}"
    capability="${specification#*:}"
    if ! dependency_available "${capability}" && [[ " ${packages[*]} " != *" ${package_name} "* ]]; then
      packages+=("${package_name}")
    fi
  done
  if [[ ${#packages[@]} -eq 0 ]]; then
    log 'System dependencies already available; skipping package installation'
    return
  fi
  if [[ "${manager}" == 'apt-get' ]]; then
    run_as_root apt-get update
  fi
  install_package_batch "${manager}" "${packages[@]}"
}

download() {
  local url="$1"
  local destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --retry-delay 1 --silent --show-error \
      --output "${destination}" "${url}"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=3 --output-document="${destination}" "${url}"
    return
  fi
  die 'curl or wget is required to download user-local tools'
}

verify_sha256() {
  local expected="$1"
  local file="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{ print $1 }')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${file}" | awk '{ print $1 }')"
  else
    die 'sha256sum or shasum is required to verify downloaded tools'
  fi
  [[ "${actual}" == "${expected}" ]] \
    || die "checksum mismatch for ${file##*/}"
}

version_at_least() {
  local current="$1"
  local required="$2"
  local current_major current_minor current_patch
  local required_major required_minor required_patch

  [[ "${current}" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))? ]] || return 1
  current_major="${BASH_REMATCH[1]}"
  current_minor="${BASH_REMATCH[2]}"
  current_patch="${BASH_REMATCH[4]:-0}"

  [[ "${required}" =~ ^([0-9]+)\.([0-9]+)(\.([0-9]+))? ]] || return 1
  required_major="${BASH_REMATCH[1]}"
  required_minor="${BASH_REMATCH[2]}"
  required_patch="${BASH_REMATCH[4]:-0}"

  (( current_major > required_major )) && return 0
  (( current_major < required_major )) && return 1
  (( current_minor > required_minor )) && return 0
  (( current_minor < required_minor )) && return 1
  (( current_patch >= required_patch ))
}

nvim_version() {
  nvim --version 2>/dev/null | sed -n '1s/^NVIM v\([0-9.]*\).*$/\1/p'
}

node_version() {
  node --version 2>/dev/null | sed -n 's/^v\([0-9.]*\).*$/\1/p'
}

node_compatible() {
  local current_version
  current_version="$(node_version)" || return 1
  version_at_least "${current_version}" "${BECKNVIM_MINIMUM_NODE_VERSION}" \
    && npm --version >/dev/null 2>&1
}

tree_sitter_version() {
  tree-sitter --version 2>/dev/null | sed -n 's/^tree-sitter \([0-9.]*\).*$/\1/p'
}

platform_asset() {
  local tool="$1"
  local system architecture platform
  system="$(uname -s)"
  architecture="$(uname -m)"

  case "${system}:${architecture}" in
    Linux:x86_64|Linux:amd64)
      platform='linux-x64'
      ;;
    Linux:aarch64|Linux:arm64)
      platform='linux-arm64'
      ;;
    Darwin:x86_64|Darwin:amd64)
      platform='macos-x86_64'
      ;;
    Darwin:aarch64|Darwin:arm64)
      platform='macos-arm64'
      ;;
    *)
      die "${tool} has no configured binary for ${system} ${architecture}"
      ;;
  esac

  printf '%s\n' "${platform}"
}

neovim_checksum() {
  case "$1" in
    linux-x64) printf '%s\n' '31cf85945cb600d96cdf69f88bc68bec814acbff50863c5546adef3a1bcef260' ;;
    linux-arm64) printf '%s\n' 'f697d4e4582b6e4b5c3c26e76e06ce26efa08ba1768e03fd2733fcc422bb0490' ;;
    macos-x86_64) printf '%s\n' '728321db960a9b6af6c03881892a6abfd743bf759bc62d233f52fa1be64ace3c' ;;
    macos-arm64) printf '%s\n' 'eeddee1009734f9071266e6b1b8a70308cb60cbcc45f5e1c1023adc471450fee' ;;
    *) return 1 ;;
  esac
}

tree_sitter_checksum() {
  case "$1" in
    linux-x64) printf '%s\n' 'ff1b7f9863f2faafd78dc0e66d902ee85b37f709b314b22c009f51caf233eebd' ;;
    linux-arm64) printf '%s\n' 'db28509fe6db8902f9d14c43c486858c7486b42c3a96b30e811e73f105762336' ;;
    macos-x86_64) printf '%s\n' 'e3c2cdec71bbc60344b25df3dad5da378a174f2292af953ff0d641e06aaee099' ;;
    macos-arm64) printf '%s\n' '050f41d60a054b608ea392ba14722bba9457bdc0ab11a5706c77f034dafc68ac' ;;
    *) return 1 ;;
  esac
}

ensure_neovim() {
  local current_version=''
  if command -v nvim >/dev/null 2>&1; then
    current_version="$(nvim_version || true)"
  fi
  if version_at_least "${current_version}" "${BECKNVIM_MINIMUM_NVIM_VERSION}"; then
    log "Neovim ${current_version} already satisfies the configuration"
    return
  fi

  BECKNVIM_NEEDS_PATH_PROMPT=1

  local platform archive_platform archive_name archive_path checksum extracted target link
  platform="$(platform_asset 'Neovim')"
  case "${platform}" in
    linux-x64) archive_platform='linux-x86_64' ;;
    *) archive_platform="${platform}" ;;
  esac
  archive_name="nvim-${archive_platform}.tar.gz"
  archive_path="${BECKNVIM_TEMP_DIR}/${archive_name}"
  checksum="$(neovim_checksum "${platform}")"
  extracted="${BECKNVIM_TEMP_DIR}/nvim-${archive_platform}"
  target="${BECKNVIM_USER_OPT}/nvim-${BECKNVIM_NVIM_VERSION}-${platform}"
  link="${BECKNVIM_USER_BIN}/nvim"

  log "Installing Neovim ${BECKNVIM_NVIM_VERSION} in ${BECKNVIM_USER_OPT}"
  download \
    "https://github.com/neovim/neovim/releases/download/v${BECKNVIM_NVIM_VERSION}/${archive_name}" \
    "${archive_path}"
  verify_sha256 "${checksum}" "${archive_path}"
  tar -xzf "${archive_path}" -C "${BECKNVIM_TEMP_DIR}"
  [[ -x "${extracted}/bin/nvim" ]] || die 'downloaded Neovim archive is incomplete'
  if [[ ! -d "${target}" ]]; then
    mv "${extracted}" "${target}"
  elif [[ ! -x "${target}/bin/nvim" ]]; then
    die "existing Neovim target is incomplete: ${target}"
  fi
  if [[ -e "${link}" && ! -L "${link}" ]]; then
    die "refusing to replace the regular file ${link}"
  fi
  ln -sfn "${target}/bin/nvim" "${link}"
  hash -r
}

python_compatible() {
  local python_command="${1:-python3}"
  "${python_command}" -c \
    'import sys, venv, ensurepip; sys.exit(sys.version_info[:3] < tuple(map(int, sys.argv[1].split("."))))' \
    "${BECKNVIM_MINIMUM_PYTHON_VERSION}" >/dev/null 2>&1
}

build_tree_sitter_from_source() {
  local target="$1"
  local cargo_root="${BECKNVIM_USER_OPT}/tree-sitter-cli-${BECKNVIM_TREE_SITTER_VERSION}-$(uname -m)"

  if ! command -v cargo >/dev/null 2>&1; then
    warn "the downloaded Tree-sitter CLI is incompatible with this system's GLIBC; install Rust 1.84+ (cargo) to enable parser installation"
    return 1
  fi

  log "Building Tree-sitter CLI ${BECKNVIM_TREE_SITTER_VERSION} locally for this system"
  if ! cargo install --locked --version "${BECKNVIM_TREE_SITTER_VERSION}" \
    --root "${cargo_root}" tree-sitter-cli; then
    warn 'local Tree-sitter build failed; continuing without parser installation'
    return 1
  fi
  if [[ ! -x "${cargo_root}/bin/tree-sitter" ]]; then
    warn 'local Tree-sitter build did not produce an executable; continuing without parser installation'
    return 1
  fi
  install -m 0755 "${cargo_root}/bin/tree-sitter" "${target}"
}

ensure_tree_sitter() {
  local owned_binary="${BECKNVIM_USER_BIN}/tree-sitter"
  local current_version=''
  if command -v tree-sitter >/dev/null 2>&1; then
    current_version="$(tree_sitter_version || true)"
  fi
  if version_at_least "${current_version}" "${BECKNVIM_MINIMUM_TREE_SITTER_VERSION}"; then
    log "Tree-sitter CLI ${current_version} already satisfies the configuration: $(command -v tree-sitter)"
    return
  fi

  local platform archive_name archive_path checksum extract_dir
  platform="$(platform_asset 'Tree-sitter CLI')"
  case "${platform}" in
    macos-x86_64) archive_name='tree-sitter-cli-macos-x64.zip' ;;
    *) archive_name="tree-sitter-cli-${platform}.zip" ;;
  esac
  archive_path="${BECKNVIM_TEMP_DIR}/${archive_name}"
  extract_dir="${BECKNVIM_TEMP_DIR}/tree-sitter-cli"
  checksum="$(tree_sitter_checksum "${platform}")"

  log "Installing Tree-sitter CLI ${BECKNVIM_TREE_SITTER_VERSION} in ${BECKNVIM_USER_BIN}"
  download \
    "https://github.com/tree-sitter/tree-sitter/releases/download/v${BECKNVIM_TREE_SITTER_VERSION}/${archive_name}" \
    "${archive_path}"
  verify_sha256 "${checksum}" "${archive_path}"
  mkdir -p "${extract_dir}"
  unzip -q "${archive_path}" -d "${extract_dir}"
  [[ -f "${extract_dir}/tree-sitter" ]] || die 'downloaded Tree-sitter archive is incomplete'
  if ! "${extract_dir}/tree-sitter" --version >/dev/null 2>&1; then
    warn "the downloaded Tree-sitter CLI cannot run on this system (likely GLIBC incompatibility)"
    if ! build_tree_sitter_from_source "${owned_binary}"; then
      rm -f "${owned_binary}"
      warn 'continuing without Tree-sitter CLI; Neovim remains usable without installed parsers'
    fi
    hash -r
    return
  fi
  install -m 0755 "${extract_dir}/tree-sitter" "${owned_binary}"
  hash -r
}

check_command() {
  local command_name="$1"
  local feature="$2"
  if dependency_available "${command_name}"; then
    log "Found ${command_name}: $(command -v "${command_name}")"
  else
    warn "missing or unusable ${command_name} (${feature})"
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
}

check_version() {
  local name="$1"
  local current="$2"
  local required="$3"
  local feature="$4"
  if version_at_least "${current}" "${required}"; then
    log "${name} ${current} satisfies >= ${required}"
  else
    warn "${name} ${current:-unknown} is older than ${required} (${feature})"
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
}

check_clipboard() {
  if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 0 || "$(uname -s)" != 'Linux' ]]; then
    return 0
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    check_command 'wl-copy' 'Wayland clipboard integration'
  elif [[ -n "${DISPLAY:-}" ]]; then
    check_command 'xclip' 'X11 clipboard integration'
  else
    log 'No local display detected; SSH sessions use OSC 52 clipboard integration'
  fi
}

check_runtime_dependencies() {
  local runtime_failures=0
  if command -v python3 >/dev/null 2>&1; then
    check_version 'Python' "$(python3 -c 'import platform; print(platform.python_version())')" \
      "${BECKNVIM_MINIMUM_PYTHON_VERSION}" 'Termaid fallback and Python tooling'
    if ! python_compatible; then
      warn 'python3 must meet the minimum version and provide venv and ensurepip'
      runtime_failures=$((runtime_failures + 1))
    fi
  else
    warn 'missing python3 (Termaid fallback and Python tooling)'
    runtime_failures=$((runtime_failures + 1))
  fi

  if node_compatible; then
    log "Node.js $(node_version) and npm $(npm --version) are available for Node-based LSP servers"
  else
    warn 'Node.js >= 22 with npm is unavailable; install Node.js manually for Node-based LSP servers'
    runtime_failures=$((runtime_failures + 1))
  fi

  if command -v uv >/dev/null 2>&1; then
    log "uv is available for Termaid: $(command -v uv)"
  else
    log 'uv is unavailable; Termaid will use Python venv and pip when Python is available'
  fi
  return "${runtime_failures}"
}

run_checks() {
  BECKNVIM_FAILURES=0
  check_command 'git' 'plugin and repository workflows'
  check_command 'rg' 'Telescope and workspace search'
  check_command 'curl' 'translation and HTTP-backed features'
  check_command 'unzip' 'plugin and tool extraction'
  check_command 'make' 'native Telescope sorter compilation'
  check_command 'cmake' 'CMake project workflow'
  check_command 'ninja' 'CMake Ninja builds'
  if command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    log "Found C compiler: $(command -v gcc || command -v cc)"
  else
    warn 'missing a C compiler (native plugins and Treesitter parsers)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  if command -v g++ >/dev/null 2>&1 || command -v c++ >/dev/null 2>&1; then
    log "Found C++ compiler: $(command -v g++ || command -v c++)"
  else
    warn 'missing a C++ compiler (Treesitter parser tooling)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  if command -v nvim >/dev/null 2>&1; then
    check_version 'Neovim' "$(nvim_version)" "${BECKNVIM_MINIMUM_NVIM_VERSION}" \
      'the pinned nvim-treesitter main branch'
  else
    warn 'missing nvim (editor runtime)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  if command -v tree-sitter >/dev/null 2>&1; then
    check_version 'Tree-sitter CLI' "$(tree_sitter_version)" \
      "${BECKNVIM_MINIMUM_TREE_SITTER_VERSION}" 'parser installation'
  else
    warn 'missing tree-sitter (parser installation)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  check_clipboard
  if [[ ${BECKNVIM_FAILURES} -gt 0 ]]; then
    warn "core dependency validation found ${BECKNVIM_FAILURES} problem(s)"
    return 1
  fi
  log 'Core Neovim dependencies are available'

  if ! check_runtime_dependencies; then
    warn 'optional runtime requirements are incomplete; Neovim remains usable and Mason/Termaid features will be limited'
    [[ "${BECKNVIM_MODE}" != 'check' ]] || return 1
  fi
}

path_has_user_bin() {
  [[ ":${PATH}:" == *":${BECKNVIM_USER_BIN}:"* ]]
}

offer_user_bin_path() {
  [[ ${BECKNVIM_NEEDS_PATH_PROMPT} -eq 1 ]] || return 0
  path_has_user_bin && return 0

  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "add ${BECKNVIM_USER_BIN} to PATH before starting Neovim from a new shell"
    return 0
  fi

  local answer=''
  printf '[BeckNvim] Add %s to ~/.bashrc? [Y/n] ' "${BECKNVIM_USER_BIN}"
  IFS= read -r answer || answer=''
  case "${answer}" in
    ''|y|Y|yes|YES|Yes)
      local bashrc="${HOME}/.bashrc"
      local path_line='export PATH="$HOME/.local/bin:$PATH"'
      if ! grep -Fqx "${path_line}" "${bashrc}" 2>/dev/null; then
        printf '\n# BeckNvim user-local tools\n%s\n' "${path_line}" >> "${bashrc}"
      fi
      export PATH="${BECKNVIM_USER_BIN}:${PATH}"
      hash -r
      log "Added ${BECKNVIM_USER_BIN} to ~/.bashrc"
      ;;
    *)
      warn "PATH was not changed; start Neovim with ${BECKNVIM_USER_BIN}/nvim or update PATH manually"
      ;;
  esac
}

main() {
  if [[ "${BECKNVIM_MODE}" == 'check' ]]; then
    run_checks
    exit $?
  fi

  BECKNVIM_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/becknvim-setup.XXXXXX")"
  mkdir -p "${BECKNVIM_USER_BIN}" "${BECKNVIM_USER_OPT}"
  if [[ ${BECKNVIM_INSTALL_SYSTEM} -eq 1 ]]; then
    install_system_packages
  else
    log 'Skipping operating-system package installation'
  fi
  ensure_neovim
  offer_user_bin_path
  ensure_tree_sitter
  run_checks || true
  if ! path_has_user_bin; then
    warn "add ${BECKNVIM_USER_BIN} to PATH before starting Neovim from a new shell"
  fi
  warn 'install a Nerd Font manually and select it in the terminal application'
  log 'Setup complete'
  log 'Open nvim; use :Mason to install or remove language servers'
}

# Parse the entrypoint and exit together so edits during installation cannot
# make Bash resume reading a changed script after the long-running work.
main; exit
