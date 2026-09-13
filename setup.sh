#!/usr/bin/env bash

set -Eeuo pipefail

readonly BECKNVIM_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly BECKNVIM_USER_BIN="${HOME}/.local/bin"
readonly BECKNVIM_USER_OPT="${HOME}/.local/opt"
readonly BECKNVIM_MINIMUM_NVIM_VERSION='0.12.0'
readonly BECKNVIM_NVIM_VERSION='0.12.2'
readonly BECKNVIM_MINIMUM_TREE_SITTER_VERSION='0.26.1'
readonly BECKNVIM_TREE_SITTER_VERSION='0.26.11'
readonly BECKNVIM_TERMAID_REPOSITORY='https://github.com/BeckWlim/termaid.git'

BECKNVIM_MODE='install'
BECKNVIM_INSTALL_SYSTEM=1
BECKNVIM_INSTALL_CLIPBOARD=1
BECKNVIM_BOOTSTRAP_PLUGINS=1
BECKNVIM_TEMP_DIR=''
BECKNVIM_FAILURES=0
BECKNVIM_ORIGINAL_PATH="${PATH}"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [options]

Install and validate the external tools used by BeckNvim.

Options:
  --check           Validate dependencies without changing the system
  --skip-system     Do not install operating-system packages
  --skip-clipboard  Do not install X11 or Wayland clipboard providers
  --skip-plugins    Do not restore the plugins pinned by lazy-lock.json
  -h, --help        Show this help

Environment:
  BECKNVIM_TERMAID_REF  Git branch, tag, or commit to install (default: main)
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
    --check)
      BECKNVIM_MODE='check'
      ;;
    --skip-system)
      BECKNVIM_INSTALL_SYSTEM=0
      ;;
    --skip-clipboard)
      BECKNVIM_INSTALL_CLIPBOARD=0
      ;;
    --skip-plugins)
      BECKNVIM_BOOTSTRAP_PLUGINS=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
  shift
done

export PATH="${BECKNVIM_USER_BIN}:${PATH}"

run_as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "sudo is required to install system packages"
  fi
}

install_system_packages() {
  local -a packages

  if command -v apt-get >/dev/null 2>&1; then
    packages=(
      build-essential ca-certificates cmake curl git gzip ninja-build nodejs npm
      pkg-config python3 python3-venv ripgrep tar unzip wget
    )
    if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 1 ]]; then
      packages+=(wl-clipboard xclip)
    fi
    log 'Installing Debian/Ubuntu system packages'
    run_as_root apt-get update
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    packages=(
      ca-certificates cmake curl gcc gcc-c++ git gzip make ninja-build nodejs npm
      pkgconf-pkg-config python3 ripgrep tar unzip wget
    )
    if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 1 ]]; then
      packages+=(wl-clipboard xclip)
    fi
    log 'Installing Fedora/RHEL system packages'
    run_as_root dnf install -y "${packages[@]}"
    return
  fi

  if command -v pacman >/dev/null 2>&1; then
    packages=(
      base-devel ca-certificates cmake curl git gzip ninja nodejs npm pkgconf python
      ripgrep tar unzip wget
    )
    if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 1 ]]; then
      packages+=(wl-clipboard xclip)
    fi
    log 'Installing Arch Linux system packages'
    run_as_root pacman -Syu --needed --noconfirm "${packages[@]}"
    return
  fi

  if command -v zypper >/dev/null 2>&1; then
    packages=(
      ca-certificates cmake curl gcc gcc-c++ git gzip make ninja nodejs npm
      pkg-config python3 ripgrep tar unzip wget
    )
    if [[ ${BECKNVIM_INSTALL_CLIPBOARD} -eq 1 ]]; then
      packages+=(wl-clipboard xclip)
    fi
    log 'Installing openSUSE system packages'
    run_as_root zypper --non-interactive install "${packages[@]}"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    packages=(cmake curl gcc git ninja node python ripgrep unzip wget)
    log 'Installing macOS Homebrew packages'
    brew install "${packages[@]}"
    return
  fi

  die 'unsupported package manager; use --skip-system after installing the README requirements'
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
    current_version="$(nvim_version)"
  fi
  if version_at_least "${current_version}" "${BECKNVIM_MINIMUM_NVIM_VERSION}"; then
    log "Neovim ${current_version} already satisfies the configuration"
    return
  fi

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

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already available at $(command -v uv)"
    return
  fi

  local installer="${BECKNVIM_TEMP_DIR}/uv-install.sh"
  log "Installing uv in ${BECKNVIM_USER_BIN}"
  download 'https://astral.sh/uv/install.sh' "${installer}"
  UV_INSTALL_DIR="${BECKNVIM_USER_BIN}" UV_NO_MODIFY_PATH=1 sh "${installer}"
  hash -r
  command -v uv >/dev/null 2>&1 || die 'uv installation did not provide an executable'
}

ensure_tree_sitter() {
  local owned_binary="${BECKNVIM_USER_BIN}/tree-sitter"
  local owned_version=''
  if [[ -x "${owned_binary}" ]]; then
    owned_version="$(${owned_binary} --version 2>/dev/null \
      | sed -n 's/^tree-sitter \([0-9.]*\).*$/\1/p')"
  fi
  if version_at_least "${owned_version}" "${BECKNVIM_TREE_SITTER_VERSION}"; then
    log "Tree-sitter CLI ${owned_version} already installed in ${BECKNVIM_USER_BIN}"
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
  install -m 0755 "${extract_dir}/tree-sitter" "${owned_binary}"
  hash -r
}

ensure_termaid() {
  local ref="${BECKNVIM_TERMAID_REF:-main}"
  [[ "${ref}" =~ ^[A-Za-z0-9._/-]+$ ]] \
    || die 'BECKNVIM_TERMAID_REF contains unsupported characters'
  local source="git+${BECKNVIM_TERMAID_REPOSITORY}@${ref}"
  log "Installing Termaid from BeckWlim/termaid@${ref}"
  UV_TOOL_BIN_DIR="${BECKNVIM_USER_BIN}" \
    uv tool install --force --refresh "${source}"
  hash -r
}

check_command() {
  local command="$1"
  local feature="$2"
  if command -v "${command}" >/dev/null 2>&1; then
    log "Found ${command}: $(command -v "${command}")"
  else
    warn "missing ${command} (${feature})"
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

check_termaid_contract() {
  if ! command -v termaid >/dev/null 2>&1; then
    warn 'missing termaid (semantic Mermaid rendering)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
    return
  fi

  local help_output
  help_output="$(termaid --help 2>&1 || true)"
  if [[ "${help_output}" == *'styled-json'* \
      && "${help_output}" == *'--strict-width'* \
      && "${help_output}" == *'--fit-mode'* \
      && "${help_output}" == *'--max-height'* ]]; then
    log "Termaid supports the BeckNvim renderer contract: $(command -v termaid)"
  else
    warn 'termaid does not support styled-json and strict reflow rendering'
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

run_checks() {
  BECKNVIM_FAILURES=0
  check_command 'git' 'plugin and repository workflows'
  check_command 'rg' 'Telescope and workspace search'
  check_command 'curl' 'translation and HTTP-backed features'
  check_command 'wget' 'download fallback'
  check_command 'unzip' 'plugin and tool extraction'
  if command -v python3 >/dev/null 2>&1; then
    check_version 'Python' "$(python3 -c 'import platform; print(platform.python_version())')" \
      '3.10.0' 'Python hierarchy and project analysis'
  else
    warn 'missing python3 (Python hierarchy and project analysis)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  check_command 'node' 'Mason language servers and parser generation'
  check_command 'npm' 'Node-backed Mason packages'
  check_command 'make' 'native Telescope sorter compilation'
  check_command 'cmake' 'CMake project workflow'
  check_command 'ninja' 'CMake Ninja builds'
  if command -v gcc >/dev/null 2>&1; then
    log "Found C compiler: $(command -v gcc)"
  elif command -v cc >/dev/null 2>&1; then
    log "Found C compiler: $(command -v cc)"
  else
    warn 'missing a C compiler (native plugins and Treesitter parsers)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  if command -v g++ >/dev/null 2>&1; then
    log "Found C++ compiler: $(command -v g++)"
  elif command -v c++ >/dev/null 2>&1; then
    log "Found C++ compiler: $(command -v c++)"
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

  check_command 'uv' 'isolated Termaid installation'
  check_termaid_contract
  check_clipboard

  if [[ ${BECKNVIM_FAILURES} -gt 0 ]]; then
    warn "dependency validation found ${BECKNVIM_FAILURES} problem(s)"
    return 1
  fi
  log 'All required external dependencies are available'
}

bootstrap_plugins() {
  log 'Restoring plugins pinned by lazy-lock.json'
  (
    cd "${BECKNVIM_ROOT}"
    nvim --headless -u init.lua -i NONE '+Lazy! sync' '+qa'
  )
  log 'Checking a complete headless startup'
  (
    cd "${BECKNVIM_ROOT}"
    nvim --headless -u init.lua -i NONE '+qa'
  )
}

if [[ "${BECKNVIM_MODE}" == 'check' ]]; then
  run_checks
  exit 0
fi

BECKNVIM_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/becknvim-setup.XXXXXX")"
mkdir -p "${BECKNVIM_USER_BIN}" "${BECKNVIM_USER_OPT}"

if [[ ${BECKNVIM_INSTALL_SYSTEM} -eq 1 ]]; then
  install_system_packages
else
  log 'Skipping operating-system package installation'
fi

ensure_neovim
ensure_uv
ensure_tree_sitter
ensure_termaid
run_checks

if [[ ${BECKNVIM_BOOTSTRAP_PLUGINS} -eq 1 ]]; then
  bootstrap_plugins
else
  log 'Skipping Neovim plugin bootstrap'
fi

if [[ ":${BECKNVIM_ORIGINAL_PATH}:" != *":${BECKNVIM_USER_BIN}:"* ]]; then
  warn "add ${BECKNVIM_USER_BIN} to PATH before starting Neovim from a new shell"
fi
warn 'install a Nerd Font manually and select it in the terminal application'
log 'Setup complete'
