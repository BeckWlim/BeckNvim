#!/usr/bin/env bash

set -Eeuo pipefail

readonly BECKNVIM_USER_BIN="${HOME}/.local/bin"
readonly BECKNVIM_USER_OPT="${HOME}/.local/opt"
readonly BECKNVIM_MINIMUM_NODE_VERSION='22.0.0'
readonly BECKNVIM_NODE_MAJOR='24'
readonly BECKNVIM_NVM_VERSION='0.40.7'
readonly BECKNVIM_MINIMUM_PYTHON_VERSION='3.10.0'
readonly BECKNVIM_PYTHON_VERSION='3.13'
readonly BECKNVIM_MINIMUM_NVIM_VERSION='0.12.0'
readonly BECKNVIM_NVIM_VERSION='0.12.2'
readonly BECKNVIM_MINIMUM_TREE_SITTER_VERSION='0.26.1'
readonly BECKNVIM_TREE_SITTER_VERSION='0.26.11'

BECKNVIM_MODE='install'
BECKNVIM_INSTALL_SYSTEM=1
BECKNVIM_INSTALL_CLIPBOARD=1
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
  -h, --help        Show this help
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

activate_nvm_node() (
  # nvm is sourced only in this subshell because it does not support strict
  # shell options. Keep the installer's own error handling and bindings intact.
  set +e
  set +u
  local node_path_file="$1"
  source "${NVM_DIR}/nvm.sh" --no-use || exit 1
  if nvm use --silent default && node_compatible; then
    log 'Reusing the default Node.js runtime managed by nvm'
  else
    nvm install "${BECKNVIM_NODE_MAJOR}" || exit 1
    nvm alias default "${BECKNVIM_NODE_MAJOR}" || exit 1
  fi
  node_compatible || exit 1
  command -v node > "${node_path_file}"
)

ensure_node() {
  if node_compatible; then
    log "Node.js $(node_version) and npm $(npm --version) already satisfy the configuration"
    return
  fi

  export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    local installer="${BECKNVIM_TEMP_DIR}/nvm-install.sh"
    log "Installing nvm ${BECKNVIM_NVM_VERSION} in ${NVM_DIR}"
    download "https://raw.githubusercontent.com/nvm-sh/nvm/v${BECKNVIM_NVM_VERSION}/install.sh" \
      "${installer}"
    mkdir -p "${NVM_DIR}"
    NODE_VERSION='' bash "${installer}"
  fi

  local node_path_file="${BECKNVIM_TEMP_DIR}/node-path"
  log "Ensuring Node.js ${BECKNVIM_NODE_MAJOR} through nvm"
  activate_nvm_node "${node_path_file}" || die 'nvm could not provide a compatible Node.js and npm'
  local installed_node_path
  IFS= read -r installed_node_path < "${node_path_file}"
  [[ "${installed_node_path}" == /* && -x "${installed_node_path}" ]] \
    || die 'nvm did not provide an executable Node.js path'
  export PATH="${installed_node_path%/*}:${PATH}"
  hash -r
  node_compatible || die 'Node.js or npm is unavailable after nvm installation'
  log "Node.js $(node_version) and npm $(npm --version) are ready"
  log "Open a new shell, or source ${NVM_DIR}/nvm.sh before launching nvim"
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
  if uv --version >/dev/null 2>&1; then
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

python_compatible() {
  local python_command="${1:-python3}"
  "${python_command}" -c \
    'import sys, venv, ensurepip; sys.exit(sys.version_info[:3] < tuple(map(int, sys.argv[1].split("."))))' \
    "${BECKNVIM_MINIMUM_PYTHON_VERSION}" >/dev/null 2>&1
}

system_package_installed() {
  local manager="$1"
  local package_name="$2"
  case "${manager}" in
    apt-get) [[ "$(dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null)" == 'install ok installed' ]] ;;
    dnf|zypper) rpm -q "${package_name}" >/dev/null 2>&1 ;;
    pacman) pacman -Q "${package_name}" >/dev/null 2>&1 ;;
    brew) [[ -n "$(brew list --versions "${package_name}" 2>/dev/null)" ]] ;;
  esac
}

install_python_build_packages() {
  if [[ ${BECKNVIM_INSTALL_SYSTEM} -eq 0 ]]; then
    log 'Skipping Python build packages; using the existing build environment'
    return
  fi
  local manager
  manager="$(system_package_manager)"
  local -a build_packages=()
  case "${manager}" in
    apt-get)
      build_packages=(build-essential patch libssl-dev zlib1g-dev libbz2-dev libreadline-dev
        libsqlite3-dev libncursesw5-dev xz-utils libffi-dev liblzma-dev)
      ;;
    dnf)
      build_packages=(gcc make patch openssl-devel zlib-devel bzip2-devel readline-devel
        sqlite-devel ncurses-devel xz xz-devel libffi-devel)
      ;;
    pacman) build_packages=(base-devel openssl zlib bzip2 readline sqlite ncurses xz libffi) ;;
    zypper)
      build_packages=(gcc make patch openssl-devel zlib-devel libbz2-devel readline-devel
        sqlite3-devel ncurses-devel xz xz-devel libffi-devel)
      ;;
    brew) build_packages=(openssl@3 readline sqlite3 xz zlib bzip2 libffi pkgconfig) ;;
  esac
  local package_name
  local -a missing_packages=()
  for package_name in "${build_packages[@]}"; do
    if ! system_package_installed "${manager}" "${package_name}"; then
      missing_packages+=("${package_name}")
    fi
  done
  [[ ${#missing_packages[@]} -gt 0 ]] || return 0
  if [[ "${manager}" == 'apt-get' ]]; then
    run_as_root apt-get update
  fi
  install_package_batch "${manager}" "${missing_packages[@]}"
}

ensure_pyenv() {
  export PYENV_ROOT="${PYENV_ROOT:-${HOME}/.pyenv}"
  export PATH="${PYENV_ROOT}/bin:${PATH}"
  if pyenv --version >/dev/null 2>&1; then
    return
  fi
  local installer="${BECKNVIM_TEMP_DIR}/pyenv-install.sh"
  log "Installing pyenv in ${PYENV_ROOT}"
  download 'https://pyenv.run' "${installer}"
  bash "${installer}"
  hash -r
  pyenv --version >/dev/null 2>&1 || die 'pyenv installation did not provide an executable'
}

ensure_python() {
  if python_compatible; then
    log "$(python3 --version) with venv support already satisfies the configuration"
    return
  fi

  local python_link="${BECKNVIM_USER_BIN}/python3"
  if [[ -e "${python_link}" && ! -L "${python_link}" ]]; then
    die "refusing to replace the regular file ${python_link}"
  fi
  ensure_pyenv
  local existing_python_version=''
  existing_python_version="$(pyenv latest "${BECKNVIM_PYTHON_VERSION}" 2>/dev/null || true)"
  local selected_python_version=''
  if [[ -n "${existing_python_version}" ]] \
    && python_compatible "${PYENV_ROOT}/versions/${existing_python_version}/bin/python3"; then
    selected_python_version="${existing_python_version}"
    log "Reusing Python ${selected_python_version} managed by pyenv"
  else
    install_python_build_packages
    log "Installing Python ${BECKNVIM_PYTHON_VERSION} through pyenv; compiling may take several minutes"
    # Resolve the latest patch known to pyenv, then reuse it on subsequent runs.
    selected_python_version="$(pyenv latest --known "${BECKNVIM_PYTHON_VERSION}")"
    pyenv install --skip-existing --verbose "${selected_python_version}" \
      || die "pyenv could not install Python ${selected_python_version}"
  fi
  local installed_python_prefix
  installed_python_prefix="$(pyenv prefix "${selected_python_version}")"
  local installed_python_path
  installed_python_path="${installed_python_prefix}/bin/python3"
  [[ "${installed_python_path}" == /* && -x "${installed_python_path}" ]] \
    || die 'pyenv did not provide an executable Python path'
  python_compatible "${installed_python_path}" || die 'installed Python does not satisfy the configuration'
  ln -sfn "${installed_python_path}" "${python_link}"
  hash -r
  python_compatible || die "add ${BECKNVIM_USER_BIN} to PATH to use the installed Python"
  log "$(python3 --version) with venv support is ready"
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

run_checks() {
  BECKNVIM_FAILURES=0
  check_command 'git' 'plugin and repository workflows'
  check_command 'rg' 'Telescope and workspace search'
  check_command 'curl' 'translation and HTTP-backed features'
  check_command 'unzip' 'plugin and tool extraction'
  if command -v python3 >/dev/null 2>&1; then
    check_version 'Python' "$(python3 -c 'import platform; print(platform.python_version())')" \
      "${BECKNVIM_MINIMUM_PYTHON_VERSION}" 'Python hierarchy and project analysis'
    if ! python_compatible; then
      warn 'python3 must meet the minimum version and provide venv and ensurepip (Mason Python packages)'
      BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
    fi
  else
    warn 'missing python3 (Python hierarchy and project analysis)'
    BECKNVIM_FAILURES=$((BECKNVIM_FAILURES + 1))
  fi
  check_version 'Node.js' "$(node_version || true)" "${BECKNVIM_MINIMUM_NODE_VERSION}" \
    'Mason language servers and parser generation'
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

  check_command 'uv' 'lazy.nvim Termaid builds'
  check_clipboard

  if [[ ${BECKNVIM_FAILURES} -gt 0 ]]; then
    warn "dependency validation found ${BECKNVIM_FAILURES} problem(s)"
    return 1
  fi
  log 'All required external dependencies are available'
}

main() {
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

  ensure_node
  ensure_python
  ensure_neovim
  ensure_tree_sitter
  ensure_uv
  run_checks

  if [[ ":${BECKNVIM_ORIGINAL_PATH}:" != *":${BECKNVIM_USER_BIN}:"* ]]; then
    warn "add ${BECKNVIM_USER_BIN} to PATH before starting Neovim from a new shell"
  fi
  warn 'install a Nerd Font manually and select it in the terminal application'
  log 'Setup complete'
  log 'Open nvim; lazy.nvim and Mason will install missing plugins and language servers'
}

# Parse the entrypoint and exit together so edits during installation cannot
# make Bash resume reading a changed script after the long-running work.
main; exit
