#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Kernel Patching & Compilation (Phase 1)
# Path: build/01_build_kernel.sh
# Description: Fetches Ubuntu Noble kernel tree, applies KIAN-OS patches (BORE,
#              NTSync, IPU6, OV5693, BBRv3), configures .config with MOK keys,
#              compiles Debian packages via make bindeb-pkg, and verifies debs.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# CLI Options
CUSTOM_SRC=""
SKIP_FETCH=0
SKIP_BUILD=0

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Kernel Build Recipe (Phase 1)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h          Display this help message
  --dry-run           Simulate steps without compiling
  --kernel-src <DIR>  Use existing kernel source tree directory
  --jobs <N>, -j <N>  Number of parallel build threads (default: $(nproc 2>/dev/null || echo 4))
  --skip-fetch        Skip source tree download if directory exists
  --skip-build        Configure kernel tree only; skip compilation

Examples:
  ./01_build_kernel.sh --dry-run
  ./01_build_kernel.sh --kernel-src /usr/src/linux-source-6.8.0 -j 16
EOF
    exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_usage
            ;;
        --dry-run)
            export DRY_RUN=1
            shift
            ;;
        --kernel-src)
            CUSTOM_SRC="$2"
            shift 2
            ;;
        --jobs|-j)
            export JOBS="$2"
            shift 2
            ;;
        --skip-fetch)
            SKIP_FETCH=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

log_step "Phase 1: linux-kian v3 Kernel Build & Packaging"

# ------------------------------------------------------------------------------
# 1. Host Prerequisite & Cryptographic Verification
# ------------------------------------------------------------------------------
log_info "Verifying host toolchain and cryptographic infrastructure..."
check_dependencies git make gcc bison flex openssl

# Ensure Kian MOK Keypair is present for Secure Boot signing
ensure_mok_keys

MOK_PRIV="${KEYS_DIR}/kian_mok.priv"
MOK_PEM="${KEYS_DIR}/kian_mok.pem"
MOK_DER="${KEYS_DIR}/kian_mok.der"

mkdir -p "${BUILD_DIR}" "${KERNEL_PKGS_DIR}"

# ------------------------------------------------------------------------------
# 2. Kernel Source Acquisition
# ------------------------------------------------------------------------------
TARGET_SRC="${KERNEL_SRC_DIR}"
if [[ -n "${CUSTOM_SRC}" ]]; then
    TARGET_SRC="${CUSTOM_SRC}"
fi

log_info "Target kernel source directory: ${TARGET_SRC}"

if [[ ! -f "${TARGET_SRC}/Makefile" ]]; then
    if [[ $SKIP_FETCH -eq 1 ]]; then
        log_error "Source tree not found at ${TARGET_SRC} and --skip-fetch was requested."
        exit 1
    fi

    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY-RUN] Simulating kernel source tree preparation..."
        mkdir -p "${TARGET_SRC}"
        touch "${TARGET_SRC}/Makefile"
    else
        log_info "Cloning Ubuntu Noble kernel tree (branch: ${DISTRO_CODENAME})..."
        mkdir -p "$(dirname "${TARGET_SRC}")"
        git clone --depth 1 --branch "${DISTRO_CODENAME}" \
            git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble \
            "${TARGET_SRC}" || {
                log_warn "Launchpad git mirror unavailable; trying GitHub Ubuntu kernel mirror..."
                git clone --depth 1 --branch "Ubuntu-6.8.0-31.31" \
                    https://github.com/canonical/ubuntu-noble.git \
                    "${TARGET_SRC}"
            }
    fi
fi

# ------------------------------------------------------------------------------
# 3. Patch Application Sequence
# ------------------------------------------------------------------------------
log_step "Applying KIAN-OS v3 Kernel Patches"

PATCH_SERIES=(
    "0001-sched-bore-noble.patch"
    "0002-drivers-misc-ntsync.patch"
    "0003-drivers-media-ipu6-dphy-settle.patch"
    "0004-drivers-media-ov5693-acpi-hid.patch"
    "0005-net-ipv4-tcp-bbrv3.patch"
)

cd "${TARGET_SRC}"

for patch_file in "${PATCH_SERIES[@]}"; do
    patch_path="${PATCHES_DIR}/${patch_file}"
    if [[ ! -f "${patch_path}" ]]; then
        log_error "Mandatory patch not found: ${patch_path}"
        exit 1
    fi

    log_info "Processing patch: ${patch_file}..."
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY-RUN] Verified patch file existence: ${patch_file}"
        continue
    fi

    # Check if patch is already applied
    if git apply --reverse --check "${patch_path}" &>/dev/null; then
        log_info "Patch ${patch_file} already applied; skipping."
        continue
    fi

    # Attempt clean apply
    if git apply --check "${patch_path}" &>/dev/null; then
        git apply "${patch_path}"
        log_success "Applied patch cleanly: ${patch_file}"
    else
        log_warn "Dry apply failed; attempting patch with 3-way merge fallback..."
        git apply -3 "${patch_path}" || {
            log_error "Failed to apply patch: ${patch_file}"
            exit 1
        }
        log_success "Applied patch with 3-way merge: ${patch_file}"
    fi
done

# ------------------------------------------------------------------------------
# 4. Kernel Configuration & MOK Integration
# ------------------------------------------------------------------------------
log_step "Configuring Kernel (.config) with Kian Architecture & MOK Signatures"

if [[ ! -f "${KERNEL_CONFIG_FILE}" ]]; then
    log_error "Kernel configuration file missing: ${KERNEL_CONFIG_FILE}"
    exit 1
fi

log_info "Copying ${KERNEL_CONFIG_FILE} to ${TARGET_SRC}/.config..."
run_cmd cp "${KERNEL_CONFIG_FILE}" "${TARGET_SRC}/.config"

if [[ -f "${TARGET_SRC}/scripts/config" && "${DRY_RUN}" != "1" ]]; then
    log_info "Embedding Secure Boot MOK keys into kernel configuration..."
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_ALL y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_SHA512 y
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_MODULE_SIG_KEY "${MOK_PRIV}"
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_SYSTEM_TRUSTED_KEYS "${MOK_PEM}"

    log_info "Reconciling configuration defaults (make olddefconfig)..."
    make olddefconfig
fi

# ------------------------------------------------------------------------------
# 5. Compilation & Debian Packaging (bindeb-pkg)
# ------------------------------------------------------------------------------
log_step "Executing Kernel Compilation & Packaging"

if [[ $SKIP_BUILD -eq 1 ]]; then
    log_info "Skipping build phase as requested (--skip-build)."
elif [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating make bindeb-pkg with ${JOBS} jobs..."
    # Generate mock package artifacts for downstream testing if missing
    touch "${KERNEL_PKGS_DIR}/linux-image-${KERNEL_VERSION}_${KERNEL_PKG_VERSION}_amd64.deb"
    touch "${KERNEL_PKGS_DIR}/linux-headers-${KERNEL_VERSION}_${KERNEL_PKG_VERSION}_amd64.deb"
    log_info "[DRY-RUN] Staged mock packages in ${KERNEL_PKGS_DIR}."
else
    log_info "Starting kernel compilation: make -j${JOBS} bindeb-pkg..."
    make -j"${JOBS}" bindeb-pkg \
        LOCALVERSION="-kian-v3" \
        KDEB_PKGVERSION="${KERNEL_PKG_VERSION}" \
        KBUILD_BUILD_USER="kian-builder" \
        KBUILD_BUILD_HOST="kian-os.org"

    # Move generated Debian packages into KERNEL_PKGS_DIR
    mv "$(dirname "${TARGET_SRC}")"/linux-*kian-v3*.deb "${KERNEL_PKGS_DIR}/" 2>/dev/null || \
    mv "${TARGET_SRC}/.."/linux-*kian-v3*.deb "${KERNEL_PKGS_DIR}/" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 6. Verification and EFI Binary Secure Boot Signing
# ------------------------------------------------------------------------------
log_step "Verifying Kernel Package Artifacts & Secure Boot Signatures"

PACKAGES_FOUND=$(find "${KERNEL_PKGS_DIR}" -name "linux-image*kian-v3*.deb" 2>/dev/null || true)
if [[ -z "${PACKAGES_FOUND}" && "${DRY_RUN}" != "1" ]]; then
    log_error "No linux-image deb packages found in ${KERNEL_PKGS_DIR}!"
    exit 1
fi

log_success "Verified produced kernel packages:"
ls -lh "${KERNEL_PKGS_DIR}"/*.deb 2>/dev/null || true

# Sign vmlinuz binary if extracted or present
if command -v sbsign &>/dev/null && [[ -f "${MOK_PRIV}" && -f "${MOK_PEM}" ]]; then
    for vmlinuz in "${TARGET_SRC}/arch/x86/boot/bzImage" "${TARGET_SRC}/vmlinux"; do
        if [[ -f "${vmlinuz}" && "${DRY_RUN}" != "1" ]]; then
            log_info "Signing EFI binary ${vmlinuz} with Kian MOK..."
            sbsign --key "${MOK_PRIV}" --cert "${MOK_PEM}" --output "${vmlinuz}.signed" "${vmlinuz}" 2>/dev/null || true
            if [[ -f "${vmlinuz}.signed" ]]; then
                mv "${vmlinuz}.signed" "${vmlinuz}"
                log_success "EFI signature attached to ${vmlinuz}."
            fi
        fi
    done
fi

log_success "Phase 1: linux-kian v3 Kernel build completed successfully!"
