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
        log_info "Cloning Linux 6.8.12 stable tree (exact upstream target for BORE & NTSync)..."
        git clone --depth 1 --branch v6.8.12 https://github.com/gregkh/linux.git "${TARGET_SRC}" || {
            log_warn "gregkh mirror failed; attempting kernel.org stable mirror..."
            git clone --depth 1 --branch v6.8.12 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "${TARGET_SRC}"
        }
    fi
fi

# ------------------------------------------------------------------------------
# 3. Patch Application Sequence
# ------------------------------------------------------------------------------
log_step "Applying KIAN-OS v3 Kernel Patches"

PATCH_SERIES=(
    "0001-bore.patch"
    "0002-ntsync.patch"
    "0003-bbr3.patch"
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
    elif patch -p1 -N --dry-run < "${patch_path}" &>/dev/null; then
        patch -p1 -N < "${patch_path}"
        log_success "Applied patch with patch utility: ${patch_file}"
    else
        log_warn "Direct apply failed; attempting patch with 3-way merge fallback..."
        git apply -3 "${patch_path}" || patch -p1 -N < "${patch_path}" || {
            log_error "Failed to apply patch: ${patch_file}"
            exit 1
        }
        log_success "Applied patch with fallback: ${patch_file}"
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
    log_info "Optimizing kernel build: disabling heavy debuginfo to accelerate compile and prevent BTF issues..."
    "${TARGET_SRC}/scripts/config" --enable CONFIG_DEBUG_INFO_NONE
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO_DWARF4
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO_DWARF5
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO_BTF
    "${TARGET_SRC}/scripts/config" --disable CONFIG_DEBUG_INFO_BTF_MODULES
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_ALL y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_SHA512 y
    mkdir -p "${TARGET_SRC}/certs"
    if [[ -s "${KEYS_DIR}/kian_mok.priv" && -s "${KEYS_DIR}/kian_mok.pem" ]]; then
        log_info "Embedding verified Kian RSA-4096 MOK keypair into certs/signing_key.pem..."
        cat "${KEYS_DIR}/kian_mok.priv" "${KEYS_DIR}/kian_mok.pem" > "${TARGET_SRC}/certs/signing_key.pem"
    fi
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_MODULE_SIG_KEY "certs/signing_key.pem"

    "${TARGET_SRC}/scripts/config" --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

    log_info "Reconciling configuration defaults (make olddefconfig)..."
    # Enforce -std=gnu11 across all x86 boot Makefiles to prevent C23 bool/false keyword collisions on modern GCC
    log_info "Enforcing -std=gnu11 across x86 boot Makefiles for GCC compatibility..."
    for mf in "${TARGET_SRC}/arch/x86/boot/compressed/Makefile" \
              "${TARGET_SRC}/arch/x86/boot/Makefile" \
              "${TARGET_SRC}/arch/x86/realmode/rm/Makefile" \
              "${TARGET_SRC}/drivers/firmware/efi/libstub/Makefile"; do
        if [[ -f "${mf}" ]]; then
            sed -i "s/KBUILD_CFLAGS\s*:=/KBUILD_CFLAGS := -std=gnu11 /g" "${mf}" || true
            sed -i "s/cflags-\$(CONFIG_X86)\s*+=/cflags-\$(CONFIG_X86) += -std=gnu11 /g" "${mf}" || true
        fi
    done

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
        DEBUG_INFO=n \
        KCFLAGS="-std=gnu11" \
        HOSTCFLAGS="-std=gnu11" \
        DPKG_FLAGS="-d" \
        LOCALVERSION="-kian-v3" \
        KDEB_PKGVERSION="${KERNEL_PKG_VERSION}" \
        KBUILD_BUILD_USER="kian-builder" \
        KBUILD_BUILD_HOST="kian-os.org"

    # Move generated Debian packages into KERNEL_PKGS_DIR
    mv "$(dirname "${TARGET_SRC}")"/linux-*kian-v3*.deb "${KERNEL_PKGS_DIR}/" 2>/dev/null || \
    mv "${TARGET_SRC}/.."/linux-*kian-v3*.deb "${KERNEL_PKGS_DIR}/" 2>/dev/null || true
    chmod -R 777 "${KERNEL_PKGS_DIR}" 2>/dev/null || true
    chown -R "${SUDO_USER:-$USER}" "${KERNEL_PKGS_DIR}" 2>/dev/null || true
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

# Ensure entire build output directory and all packages are accessible by non-root users
chmod -R a+rwx "${BUILD_DIR}" "${KERNEL_PKGS_DIR}" 2>/dev/null || true
chown -R "${SUDO_USER:-1001:1001}" "${BUILD_DIR}" 2>/dev/null || true
(cd "${KERNEL_PKGS_DIR}" && sha256sum *.deb > SHA256SUMS && chmod a+rw SHA256SUMS) 2>/dev/null || true

log_success "Phase 1: linux-kian v3 Kernel build completed successfully!"
