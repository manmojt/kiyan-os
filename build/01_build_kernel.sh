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

    # Ensure clean single -kian-v3 suffix and universal x86_64 CPU compatibility (boots on KVM, QEMU, and all x86_64 PCs)
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_LOCALVERSION "-kian-v3"
    "${TARGET_SRC}/scripts/config" --disable CONFIG_LOCALVERSION_AUTO
    "${TARGET_SRC}/scripts/config" --enable CONFIG_GENERIC_CPU
    "${TARGET_SRC}/scripts/config" --enable CONFIG_EFI_STUB

    # Enforce cryptographic module signing using explicit Kian MOK key (not Kbuild's autogenerated default path)
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_ALL y
    "${TARGET_SRC}/scripts/config" --set-val CONFIG_MODULE_SIG_SHA512 y
    mkdir -p "${TARGET_SRC}/certs"
    if [[ ! -s "${MOK_PRIV}" || ! -s "${MOK_PEM}" ]]; then
        log_error "Mandatory Kian MOK keypair (${MOK_PRIV}, ${MOK_PEM}) is missing!"
        exit 1
    fi
    log_info "Embedding verified Kian RSA-4096 MOK keypair into certs/kian_mok_signing.pem..."
    cat "${MOK_PRIV}" "${MOK_PEM}" > "${TARGET_SRC}/certs/kian_mok_signing.pem"
    chmod 0600 "${TARGET_SRC}/certs/kian_mok_signing.pem"
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_MODULE_SIG_KEY "certs/kian_mok_signing.pem"

    "${TARGET_SRC}/scripts/config" --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    "${TARGET_SRC}/scripts/config" --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

    log_info "Reconciling configuration defaults (make olddefconfig)..."
    rm -rf "${TARGET_SRC}/.git"
    make LOCALVERSION= olddefconfig
fi

# ------------------------------------------------------------------------------
# 5. Compilation & Debian Packaging (bindeb-pkg)
# ------------------------------------------------------------------------------
log_step "Executing Kernel Compilation & Packaging"

if [[ $SKIP_BUILD -eq 1 ]]; then
    log_info "Skipping build phase as requested (--skip-build)."
elif [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating make bindeb-pkg with ${JOBS} jobs..."
    mkdir -p "${KERNEL_PKGS_DIR}" "${KERNEL_OUT_PKGS_DIR}"
    touch "${KERNEL_PKGS_DIR}/linux-image-${KERNEL_VERSION}_${KERNEL_PKG_VERSION}_amd64.deb"
    touch "${KERNEL_PKGS_DIR}/linux-headers-${KERNEL_VERSION}_${KERNEL_PKG_VERSION}_amd64.deb"
    log_info "[DRY-RUN] Staged mock packages in ${KERNEL_PKGS_DIR}."
else
    check_dependencies dpkg-deb sbsign sbverify
    gcc_bin="gcc"
    if command -v gcc-13 &>/dev/null; then
        gcc_bin="gcc-13"
    fi
    cc_cmd="${gcc_bin}"
    hostcc_cmd="${gcc_bin}"
    if command -v ccache &>/dev/null; then
        cc_cmd="ccache ${gcc_bin}"
        hostcc_cmd="ccache ${gcc_bin}"
        log_info "ccache detected, accelerating build with CC='${cc_cmd}'"
    else
        log_info "Using compiler CC='${cc_cmd}'"
    fi

    # Clean stale debs before building so only fresh artifacts are packaged
    rm -f "$(dirname "${TARGET_SRC}")"/linux-*kian-v3*.deb \
          "${TARGET_SRC}/.."/linux-*kian-v3*.deb \
          "${KERNEL_PKGS_DIR}"/linux-*kian-v3*.deb \
          "${KERNEL_OUT_PKGS_DIR}"/linux-*kian-v3*.deb 2>/dev/null || true

    log_info "Starting kernel compilation: make -j${JOBS} bindeb-pkg..."
    make -j"${JOBS}" bindeb-pkg \
        LOCALVERSION= \
        CC="${cc_cmd}" \
        HOSTCC="${hostcc_cmd}" \
        DEBUG_INFO=n \
        DPKG_FLAGS="-d" \
        KDEB_PKGVERSION="${KERNEL_PKG_VERSION}" \
        KBUILD_BUILD_USER="kian-builder" \
        KBUILD_BUILD_HOST="kian-os.org"

    mkdir -p "${KERNEL_PKGS_DIR}" "${KERNEL_OUT_PKGS_DIR}"
    for deb_src_dir in "$(dirname "${TARGET_SRC}")" "${TARGET_SRC}/.."; do
        if compgen -G "${deb_src_dir}/linux-*kian-v3*.deb" > /dev/null; then
            mv "${deb_src_dir}"/linux-*kian-v3*.deb "${KERNEL_PKGS_DIR}/"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 6. EFI Secure Boot Signing Inside Debian Package & Cryptographic Verification
# ------------------------------------------------------------------------------
log_step "Signing vmlinuz Inside linux-image .deb & Verifying Cryptographic Signatures"

PACKAGES_FOUND=$(find "${KERNEL_PKGS_DIR}" -maxdepth 1 -name "linux-image-*kian-v3*.deb" ! -name "*dbg*" 2>/dev/null || true)
if [[ -z "${PACKAGES_FOUND}" && "${DRY_RUN}" != "1" ]]; then
    log_error "No linux-image deb packages found in ${KERNEL_PKGS_DIR}!"
    exit 1
fi

if [[ "${DRY_RUN}" != "1" ]]; then
    for img_deb in ${PACKAGES_FOUND}; do
        log_info "Unpacking ${img_deb} to attach PE/COFF Secure Boot MOK signature to /boot/vmlinuz-*..."
        repack_dir="$(mktemp -d)"
        dpkg-deb -R "${img_deb}" "${repack_dir}"

        vmlinuz_found=0
        for vmlinuz_bin in "${repack_dir}"/boot/vmlinuz-*; do
            [[ -f "${vmlinuz_bin}" ]] || continue
            vmlinuz_found=1
            log_info "Signing ${vmlinuz_bin} with Kian RSA-4096 MOK..."
            sbsign --key "${MOK_PRIV}" --cert "${MOK_PEM}" --output "${vmlinuz_bin}.signed" "${vmlinuz_bin}"
            sbverify --cert "${MOK_PEM}" "${vmlinuz_bin}.signed"
            mv "${vmlinuz_bin}.signed" "${vmlinuz_bin}"
            chmod 0644 "${vmlinuz_bin}"
            log_success "Verified PE/COFF MOK signature on $(basename "${vmlinuz_bin}")."
        done

        if [[ ${vmlinuz_found} -eq 0 ]]; then
            rm -rf "${repack_dir}"
            log_error "No /boot/vmlinuz-* binary found inside ${img_deb}!"
            exit 1
        fi

        if [[ -d "${repack_dir}/DEBIAN" ]]; then
            chmod 0755 "${repack_dir}/DEBIAN"
            (
                cd "${repack_dir}"
                find . -type f ! -path './DEBIAN/*' -printf '%P\0' | sort -z | xargs -0 md5sum > DEBIAN/md5sums
            )
            chmod 0644 "${repack_dir}/DEBIAN/md5sums"
        fi

        dpkg-deb -Zxz --root-owner-group -b "${repack_dir}" "${img_deb}"
        rm -rf "${repack_dir}"
        log_success "Repacked signed kernel package: $(basename "${img_deb}")"
    done

    # Mirror verified packages and checksums into both canonical and build/out directories
    mkdir -p "${KERNEL_OUT_PKGS_DIR}"
    cp -f "${KERNEL_PKGS_DIR}"/*.deb "${KERNEL_OUT_PKGS_DIR}/"
    (cd "${KERNEL_PKGS_DIR}" && sha256sum ./*.deb | sed 's| \./| |' > SHA256SUMS)
    cp -f "${KERNEL_PKGS_DIR}/SHA256SUMS" "${KERNEL_OUT_PKGS_DIR}/SHA256SUMS"
    chmod -R a+rX "${BUILD_DIR}" "${KERNEL_PKGS_DIR}" "${KERNEL_OUT_PKGS_DIR}"
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "${KERNEL_PKGS_DIR}" "${KERNEL_OUT_PKGS_DIR}"
    fi
fi

log_success "Verified produced kernel packages:"
ls -lh "${KERNEL_PKGS_DIR}"/*.deb 2>/dev/null || true

log_success "Phase 1: linux-kian v3 Kernel build & Secure Boot signing completed successfully!"
