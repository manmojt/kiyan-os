#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Shared Configuration & Primitives
# Path: build/common.sh
# Description: Defines global variables, directories, ANSI color logging,
#              dependency checks, error trapping, and MOK cryptographic helpers.
# ==============================================================================

# Guard against duplicate sourcing
if [[ -n "${_KIAN_COMMON_SH_SOURCED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_KIAN_COMMON_SH_SOURCED=1

set -euo pipefail

# ==============================================================================
# Global Distribution & Architecture Metadata
# ==============================================================================
export DISTRO_NAME="KIAN-OS"
export DISTRO_VERSION="4.0.0"
export DISTRO_CODENAME="noble"
export DISTRO_ARCH="amd64"
export KIYAN_EDITION="${KIYAN_EDITION:-core}"
export KERNEL_VERSION="7.3.4-1-liquorix-amd64"
export KERNEL_BASELINE="7.3"
export KERNEL_PKG_VERSION="4.0.0-1"
export ISO_NAME="kiyan-os-v4-${KIYAN_EDITION}-noble-amd64.iso"

# ==============================================================================
# Workspace & Directory Topography
# ==============================================================================
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Build Artifact Directories
export BUILD_DIR="${PROJECT_ROOT}/build/out"
export KERNEL_SRC_DIR="${BUILD_DIR}/kernel_src"
export KERNEL_PKGS_DIR="${PROJECT_ROOT}/build/kernel_pkgs"
export KERNEL_OUT_PKGS_DIR="${BUILD_DIR}/kernel_pkgs"
export ROOTFS_DIR="${BUILD_DIR}/rootfs"
export ISO_TREE_DIR="${BUILD_DIR}/iso_tree"
export DIST_DIR="${PROJECT_ROOT}/dist"
export KEYS_DIR="${PROJECT_ROOT}/keys"

# Source & Configuration References
export KERNEL_DIR="${PROJECT_ROOT}/kernel"
export PATCHES_DIR="${KERNEL_DIR}/patches"
export KERNEL_CONFIG_FILE="${KERNEL_DIR}/config-6.8-kian-v3"
export DESKTOP_DIR="${PROJECT_ROOT}/desktop"
export INSTALLER_DIR="${PROJECT_ROOT}/installer"
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# Execution Controls
export DRY_RUN="${DRY_RUN:-0}"
export JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

# ==============================================================================
# ANSI Color Palettes & Structured Logging
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_step() {
    echo -e "\n${BLUE}================================================================================${NC}"
    echo -e "${BOLD}${CYAN}:: [STEP] ${1}${NC}"
    echo -e "${BLUE}================================================================================${NC}"
}

log_info()    { echo -e "${GREEN}:: [INFO]${NC} ${1}"; }
log_warn()    { echo -e "${YELLOW}:: [WARN]${NC} ${1}"; }
log_error()   { echo -e "${RED}:: [ERROR]${NC} ${1}" >&2; }
log_success() { echo -e "${BOLD}${GREEN}:: [SUCCESS]${NC} ${1}"; }

# ==============================================================================
# Error Trapping Handler
# ==============================================================================
error_handler() {
    local exit_code="$1"
    local line_no="$2"
    local bash_cmd="${BASH_COMMAND:-unknown}"
    local script_name="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

    echo -e "\n${RED}================================================================================${NC}" >&2
    echo -e "${BOLD}${RED}[FATAL ERROR] Build pipeline failure in ${script_name}${NC}" >&2
    echo -e "${RED}Failing Line: ${line_no}${NC}" >&2
    echo -e "${RED}Command:      ${bash_cmd}${NC}" >&2
    echo -e "${RED}Exit Code:    ${exit_code}${NC}" >&2
    echo -e "${RED}================================================================================${NC}\n" >&2
    exit "${exit_code}"
}
trap 'error_handler $? $LINENO' ERR

# ==============================================================================
# Command Runner with Dry-Run Dispatch
# ==============================================================================
run_cmd() {
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute:${NC} $*"
    else
        "$@"
    fi
}

# ==============================================================================
# Dependency Verification
# ==============================================================================
check_dependencies() {
    local required_tools=("$@")
    local missing=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing tools: ${missing[*]}"
        if [[ "${DRY_RUN}" == "1" || "${KIAN_TEST_MODE:-0}" == "1" ]]; then
            log_warn "[DRY-RUN / TEST MODE] Continuing without missing host tools: ${missing[*]}"
            return 0
        fi
        log_error "Mandatory tools missing from host PATH. Please run:"
        log_error "sudo apt-get update && sudo apt-get install -y ${missing[*]}"
        exit 1
    fi
    return 0
}

# ==============================================================================
# Privilege Verification
# ==============================================================================
require_root() {
    if [[ $EUID -ne 0 ]]; then
        if [[ "${DRY_RUN}" == "1" || "${KIAN_TEST_MODE:-0}" == "1" ]]; then
            log_warn "[DRY-RUN / TEST MODE] Bypassing root privilege requirement."
            return 0
        fi
        log_error "This stage requires root privileges (sudo). Please re-run as root."
        exit 1
    fi
}

# ==============================================================================
# Cryptographic MOK Key Generation Helper
# ==============================================================================
ensure_mok_keys() {
    local mok_priv="${KEYS_DIR}/kian_mok.priv"
    local mok_der="${KEYS_DIR}/kian_mok.der"
    local mok_pem="${KEYS_DIR}/kian_mok.pem"
    local mok_cnf="${KEYS_DIR}/kian_mok.cnf"

    if [[ -s "${mok_priv}" && -s "${mok_pem}" && -s "${mok_der}" ]]; then
        log_info "Existing Kian MOK keypair detected at ${KEYS_DIR}."
        return 0
    fi

    log_step "Generating Cryptographic 4096-bit RSA Kian MOK Keypair..."
    mkdir -p "${KEYS_DIR}"
    chmod 0700 "${KEYS_DIR}"

    cat <<EOF > "${mok_cnf}"
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
O = KIAN-OS Foundation
CN = KIAN-OS v3 Kernel & Module Master Signing Authority
emailAddress = security@kian-os.org

[ myexts ]
basicConstraints = critical,CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning, 1.3.6.1.4.1.2312.16.1.2
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF

    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY-RUN] Would generate RSA-4096 MOK keypair with OpenSSL."
        touch "${mok_priv}" "${mok_der}" "${mok_pem}"
        return 0
    fi

    openssl req -new -x509 -newkey rsa:4096 \
        -keyout "${mok_priv}" \
        -out "${mok_der}" \
        -outform DER \
        -days 3650 \
        -nodes \
        -config "${mok_cnf}" >/dev/null 2>&1

    # Convert DER to PEM format for sbsign and kernel inclusion
    openssl x509 -in "${mok_der}" -inform DER -out "${mok_pem}" -outform PEM >/dev/null 2>&1

    chmod 0400 "${mok_priv}"
    chmod 0644 "${mok_der}" "${mok_pem}"
    log_success "Kian MOK keypair generated successfully in ${KEYS_DIR}."
}
