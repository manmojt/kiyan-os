#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Master Pipeline Orchestrator
# Path: build/build_all.sh
# Description: End-to-end master automation driver for KIAN-OS v3. Coordinates
#              Phase 1 (Kernel), Phase 2 (Rootfs), Phase 3 (Desktop), Phase 4 (ISO),
#              and Phase 5 (Verification) with timing, logging, and phase controls.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SKIP_KERNEL=0
SKIP_ROOTFS=0
SKIP_DESKTOP=0
SKIP_ISO=0
SKIP_VERIFY=0
CLEAN_BUILD=0
CUSTOM_KERNEL_SRC=""
CUSTOM_MIRROR=""

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Master Build Pipeline Orchestrator
Usage: sudo $(basename "$0") [OPTIONS]

Options:
  --help, -h          Display this help message
  --dry-run           Execute full dry-run simulation across all 5 phases
  --clean             Wipe build output directory before starting
  --skip-kernel       Skip Phase 1: Kernel patching, compilation, and deb packaging
  --skip-rootfs       Skip Phase 2: Debootstrap and base rootfs provisioning
  --skip-desktop      Skip Phase 3: Desktop, SDDM, Triple-Shell, and Calamares setup
  --skip-iso          Skip Phase 4: Squashfs compression and hybrid ISO mastering
  --skip-verify       Skip Phase 5: ISO checksums, partition, and boot validation
  --kernel-src <DIR>  Specify custom kernel source tree directory for Phase 1
  --jobs <N>, -j <N>  Number of parallel build threads (default: $(nproc 2>/dev/null || echo 4))
  --mirror <URL>      Specify Ubuntu archive mirror for Phase 2

Examples:
  ./build_all.sh --dry-run
  sudo ./build_all.sh
  sudo ./build_all.sh --skip-kernel --skip-rootfs
  sudo ./build_all.sh --clean -j 16
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
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --skip-kernel)
            SKIP_KERNEL=1
            shift
            ;;
        --skip-rootfs)
            SKIP_ROOTFS=1
            shift
            ;;
        --skip-desktop)
            SKIP_DESKTOP=1
            shift
            ;;
        --skip-iso)
            SKIP_ISO=1
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=1
            shift
            ;;
        --kernel-src)
            CUSTOM_KERNEL_SRC="$2"
            shift 2
            ;;
        --jobs|-j)
            export JOBS="$2"
            shift 2
            ;;
        --mirror)
            CUSTOM_MIRROR="$2"
            shift 2
            ;;
        --edition)
            export KIYAN_EDITION="$2"
            export ISO_NAME="kiyan-os-v4-${KIYAN_EDITION}-noble-amd64.iso"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

OVERALL_START=$(date +%s)

echo -e "\n${BOLD}${CYAN}================================================================================${NC}"
echo -e "${BOLD}${CYAN}           KIAN-OS v3 Production Operating System Build Pipeline                ${NC}"
echo -e "${BOLD}${CYAN}             Ubuntu 24.04 LTS (Noble Numbat) & linux-kian v3                    ${NC}"
echo -e "${BOLD}${CYAN}================================================================================${NC}\n"

log_info "Target Distribution:    ${DISTRO_NAME} v${DISTRO_VERSION} (${DISTRO_CODENAME})"
log_info "Kernel Target:          ${KERNEL_VERSION} (${KERNEL_BASELINE} LTS)"
log_info "Parallel Threads:       ${JOBS}"
log_info "Dry-Run Simulation:     $([[ "${DRY_RUN}" == "1" ]] && echo "ENABLED" || echo "DISABLED")"

# ------------------------------------------------------------------------------
# 1. Pre-Flight Host Environment Verification
# ------------------------------------------------------------------------------
log_step "Pre-Flight Host Environment & Workspace Verification"

require_root

# Check host disk free space
AVAILABLE_GB=$(df -BG "${PROJECT_ROOT}" | awk 'NR==2 {print $4}' | tr -d 'G')
log_info "Available disk space in workspace: ${AVAILABLE_GB} GB"
if [[ $AVAILABLE_GB -lt 15 && "${DRY_RUN}" != "1" ]]; then
    log_warn "Low disk space detected (<15GB). Build requires significant temporary storage."
fi

# Clean build workspace if requested
if [[ $CLEAN_BUILD -eq 1 ]]; then
    log_warn "Purging build output workspace: ${BUILD_DIR}..."
    run_cmd rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${KEYS_DIR}"

# ------------------------------------------------------------------------------
# 2. Phase 1: linux-kian v3 Kernel Orchestration & Packaging
# ------------------------------------------------------------------------------
if [[ $SKIP_KERNEL -eq 0 ]]; then
    P1_START=$(date +%s)
    P1_ARGS=()
    if [[ "${DRY_RUN}" == "1" ]]; then P1_ARGS+=(--dry-run); fi
    if [[ -n "${CUSTOM_KERNEL_SRC}" ]]; then P1_ARGS+=(--kernel-src "${CUSTOM_KERNEL_SRC}"); fi
    P1_ARGS+=(-j "${JOBS}")

    "${SCRIPT_DIR}/01_build_kernel.sh" "${P1_ARGS[@]}"
    P1_ELAPSED=$(( $(date +%s) - P1_START ))
    log_success "Phase 1 finished in ${P1_ELAPSED} seconds."
else
    log_warn "Skipping Phase 1: Kernel Build (--skip-kernel requested)."
fi

# ------------------------------------------------------------------------------
# 3. Phase 2: Clean-Slate Ubuntu 24.04 LTS Rootfs Debootstrap
# ------------------------------------------------------------------------------
if [[ $SKIP_ROOTFS -eq 0 ]]; then
    P2_START=$(date +%s)
    P2_ARGS=()
    if [[ "${DRY_RUN}" == "1" ]]; then P2_ARGS+=(--dry-run); fi
    if [[ -n "${CUSTOM_MIRROR}" ]]; then P2_ARGS+=(--mirror "${CUSTOM_MIRROR}"); fi

    "${SCRIPT_DIR}/02_bootstrap_rootfs.sh" "${P2_ARGS[@]}"
    P2_ELAPSED=$(( $(date +%s) - P2_START ))
    log_success "Phase 2 finished in ${P2_ELAPSED} seconds."
else
    log_warn "Skipping Phase 2: Rootfs Debootstrap (--skip-rootfs requested)."
fi

# ------------------------------------------------------------------------------
# 4. Phase 3: Desktop Customization, Triple-Shell & Calamares
# ------------------------------------------------------------------------------
if [[ $SKIP_DESKTOP -eq 0 ]]; then
    P3_START=$(date +%s)
    P3_ARGS=(--edition "${KIYAN_EDITION:-core}")
    if [[ "${DRY_RUN}" == "1" ]]; then P3_ARGS+=(--dry-run); fi

    "${SCRIPT_DIR}/03_customize_desktop.sh" "${P3_ARGS[@]}"
    P3_ELAPSED=$(( $(date +%s) - P3_START ))
    log_success "Phase 3 finished in ${P3_ELAPSED} seconds."
else
    log_warn "Skipping Phase 3: Desktop Customization (--skip-desktop requested)."
fi

# ------------------------------------------------------------------------------
# 5. Phase 4: Live Squashfs Compression & Hybrid ISO Mastering
# ------------------------------------------------------------------------------
if [[ $SKIP_ISO -eq 0 ]]; then
    P4_START=$(date +%s)
    P4_ARGS=()
    if [[ "${DRY_RUN}" == "1" ]]; then P4_ARGS+=(--dry-run); fi

    "${SCRIPT_DIR}/04_build_iso.sh" "${P4_ARGS[@]}"
    P4_ELAPSED=$(( $(date +%s) - P4_START ))
    log_success "Phase 4 finished in ${P4_ELAPSED} seconds."
else
    log_warn "Skipping Phase 4: ISO Mastering (--skip-iso requested)."
fi

# ------------------------------------------------------------------------------
# 6. Phase 5: Automated ISO Verification & Bootability Assertion
# ------------------------------------------------------------------------------
if [[ $SKIP_VERIFY -eq 0 ]]; then
    P5_START=$(date +%s)
    P5_ARGS=()
    if [[ "${DRY_RUN}" == "1" ]]; then P5_ARGS+=(--dry-run); fi

    "${SCRIPT_DIR}/05_verify_iso.sh" "${P5_ARGS[@]}"
    P5_ELAPSED=$(( $(date +%s) - P5_START ))
    log_success "Phase 5 finished in ${P5_ELAPSED} seconds."
else
    log_warn "Skipping Phase 5: ISO Verification (--skip-verify requested)."
fi

# ------------------------------------------------------------------------------
# 7. Final Pipeline Summary Banner
# ------------------------------------------------------------------------------
TOTAL_ELAPSED=$(( $(date +%s) - OVERALL_START ))
TOTAL_MIN=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SEC=$(( TOTAL_ELAPSED % 60 ))

echo -e "\n${BOLD}${GREEN}================================================================================${NC}"
echo -e "${BOLD}${GREEN}            KIAN-OS v3 Production Build Completed Successfully!                 ${NC}"
echo -e "${BOLD}${GREEN}================================================================================${NC}"
echo "Total Pipeline Duration: ${TOTAL_MIN} minutes ${TOTAL_SEC} seconds"
echo ""
echo "Output Deliverables:"
echo "  1. Live Hybrid ISO:    ${DIST_DIR}/${ISO_NAME}"
echo "  2. SHA-256 Checksum:   ${DIST_DIR}/${ISO_NAME}.sha256"
echo "  3. Secure Boot MOK:    ${KEYS_DIR}/kian_mok.der"
echo "  4. Kernel Packages:    ${KERNEL_PKGS_DIR}"
echo ""
echo "Deployment Instructions:"
echo "  - Flash to USB drive:  sudo dd if=${DIST_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress oflag=sync"
echo "  - Test under QEMU:     qemu-system-x86_64 -m 4G -enable-kvm -cdrom ${DIST_DIR}/${ISO_NAME}"
echo -e "${BOLD}${GREEN}================================================================================${NC}\n"
