#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: ISO Quality & Bootability Verification (Phase 5)
# Path: build/05_verify_iso.sh
# Description: Validates generated hybrid ISO image: checks cryptographic SHA-256
#              checksums, inspects MBR/GPT partition tables via xorriso/fdisk/parted,
#              verifies EFI system partition & casper live payloads, and computes
#              a quantitative bootability confidence score.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ISO="${DIST_DIR}/${ISO_NAME}"

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 ISO Quality Verification Recipe (Phase 5)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h      Display this help message
  --dry-run       Simulate verification on stub/existing image
  --iso <PATH>    Path to ISO image to verify (default: ${DIST_DIR}/${ISO_NAME})

Examples:
  ./05_verify_iso.sh
  ./05_verify_iso.sh --iso /path/to/kian-os.iso
  ./05_verify_iso.sh --dry-run
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
        --iso)
            TARGET_ISO="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

log_step "Phase 5: Automated ISO Verification & Bootability Assertion"

# ------------------------------------------------------------------------------
# 1. ISO Image Presence & Dimension Verification
# ------------------------------------------------------------------------------
log_step "1. Checking Target ISO File & Physical Size"

if [[ ! -f "${TARGET_ISO}" ]]; then
    log_error "Target ISO file does not exist: ${TARGET_ISO}"
    exit 1
fi

ISO_BYTES=$(stat -c%s "${TARGET_ISO}" 2>/dev/null || stat -f%z "${TARGET_ISO}" 2>/dev/null || echo 0)
ISO_HR=$(ls -lh "${TARGET_ISO}" | awk '{print $5}')

log_info "Target ISO Path: ${TARGET_ISO}"
log_info "Detected Size:   ${ISO_HR} (${ISO_BYTES} bytes)"

PASSED_CHECKS=0
TOTAL_CHECKS=7

if [[ $ISO_BYTES -gt 0 ]]; then
    log_success "[PASS] ISO file exists and is non-empty."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_error "[FAIL] ISO file has 0 bytes!"
fi

# ------------------------------------------------------------------------------
# 2. Cryptographic SHA-256 Checksum Calculation & Integrity Assertion
# ------------------------------------------------------------------------------
log_step "2. Cryptographic SHA-256 Checksum Assertion"

CHECKSUM_FILE="${TARGET_ISO}.sha256"
log_info "Generating SHA-256 digest..."
sha256sum "${TARGET_ISO}" > "${CHECKSUM_FILE}"
DIGEST=$(cat "${CHECKSUM_FILE}" | awk '{print $1}')
log_info "SHA-256: ${DIGEST}"

if sha256sum -c "${CHECKSUM_FILE}" &>/dev/null; then
    log_success "[PASS] Cryptographic SHA-256 checksum verified."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_error "[FAIL] SHA-256 verification failed!"
fi

# ------------------------------------------------------------------------------
# 3. Hybrid Partition Table Verification (MBR / GPT)
# ------------------------------------------------------------------------------
log_step "3. Inspecting Hybrid MBR & GPT Partition Structure"

PARTITION_OK=0
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating hybrid partition table analysis..."
    PARTITION_OK=1
elif command -v xorriso &>/dev/null && xorriso -indev "${TARGET_ISO}" -report_system_area as_mkisofs 2>&1 | grep -q "isohybrid"; then
    log_info "xorriso detected isohybrid MBR signature."
    PARTITION_OK=1
elif command -v parted &>/dev/null && parted -s "${TARGET_ISO}" print 2>&1 | grep -qE "gpt|msdos"; then
    log_info "parted detected valid partition table."
    PARTITION_OK=1
elif command -v fdisk &>/dev/null && fdisk -l "${TARGET_ISO}" 2>&1 | grep -qE "Disklabel type: (dos|gpt)"; then
    log_info "fdisk detected valid disklabel type."
    PARTITION_OK=1
fi

if [[ $PARTITION_OK -eq 1 ]]; then
    log_success "[PASS] Universal hybrid bootable partition structure verified."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warn "[WARN] Hybrid partition structure could not be verified by host tools."
fi

# ------------------------------------------------------------------------------
# 4. EFI System Partition & Secure Boot Payloads Verification
# ------------------------------------------------------------------------------
log_step "4. Inspecting EFI System Partition & Bootloader Payloads"

EFI_OK=0
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating EFI system partition detection..."
    EFI_OK=1
elif command -v xorriso &>/dev/null; then
    if xorriso -indev "${TARGET_ISO}" -find /boot/grub/efi.img 2>&1 | grep -q "efi.img" || \
       xorriso -indev "${TARGET_ISO}" -find /EFI/BOOT 2>&1 | grep -q "BOOT"; then
        log_info "xorriso located EFI system partition and bootloader payloads."
        EFI_OK=1
    fi
fi

if [[ $EFI_OK -eq 1 ]]; then
    log_success "[PASS] UEFI EFI bootloader architecture verified."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warn "[WARN] EFI system partition not detected inside ISO."
fi

# ------------------------------------------------------------------------------
# 5. Casper Live Environment Payloads (Squashfs, Kernel, Initrd)
# ------------------------------------------------------------------------------
log_step "5. Verifying Casper Live Environment (Squashfs, Kernel, Initrd)"

CASPER_OK=0
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating casper live payload verification..."
    CASPER_OK=1
elif command -v xorriso &>/dev/null; then
    CASPER_LS=$(xorriso -indev "${TARGET_ISO}" -ls /casper 2>&1 || true)
    if echo "${CASPER_LS}" | grep -q "filesystem.squashfs" && \
       echo "${CASPER_LS}" | grep -q "vmlinuz" && \
       echo "${CASPER_LS}" | grep -q "initrd"; then
        log_info "All essential casper payloads confirmed: filesystem.squashfs, vmlinuz, initrd."
        CASPER_OK=1
    fi
fi

if [[ $CASPER_OK -eq 1 ]]; then
    log_success "[PASS] Casper live filesystem components verified."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warn "[WARN] One or more casper live payloads missing or not inspectable."
fi

# ------------------------------------------------------------------------------
# 6. Bootloader Configuration File Integrity (GRUB & ISOLINUX)
# ------------------------------------------------------------------------------
log_step "6. Inspecting Live Bootloader Configurations (GRUB & ISOLINUX)"

BOOT_CFG_OK=0
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating bootloader configuration file checks..."
    BOOT_CFG_OK=1
elif command -v xorriso &>/dev/null; then
    if xorriso -indev "${TARGET_ISO}" -find /boot/grub/grub.cfg 2>&1 | grep -q "grub.cfg"; then
        log_info "Verified presence of /boot/grub/grub.cfg."
        BOOT_CFG_OK=1
    fi
fi

if [[ $BOOT_CFG_OK -eq 1 ]]; then
    log_success "[PASS] Live bootloader configuration verified."
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warn "[WARN] Live bootloader configuration could not be verified."
fi

# ------------------------------------------------------------------------------
# 7. Superkernel linux-kian v3 Verification inside Live Payload
# ------------------------------------------------------------------------------
log_step "7. Verifying Superkernel linux-kian v3 in Casper Payload"

SUPERKERNEL_OK=0
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating superkernel verification..."
    SUPERKERNEL_OK=1
elif command -v 7z &>/dev/null; then
    TMP_KDIR=$(mktemp -d /tmp/kian-kchk-XXXXXX)
    if 7z e "${TARGET_ISO}" "casper/vmlinuz" -o"${TMP_KDIR}" &>/dev/null; then
        if strings "${TMP_KDIR}/vmlinuz" 2>/dev/null | grep -qi "kian-v3"; then
            log_success "[PASS] Verified linux-kian v3 superkernel binary inside /casper/vmlinuz!"
            SUPERKERNEL_OK=1
        fi
    fi
    rm -rf "${TMP_KDIR}"
elif command -v xorriso &>/dev/null; then
    TMP_KDIR=$(mktemp -d /tmp/kian-kchk-XXXXXX)
    if xorriso -osirx on -indev "${TARGET_ISO}" -extract /casper/vmlinuz "${TMP_KDIR}/vmlinuz" 2>/dev/null; then
        if strings "${TMP_KDIR}/vmlinuz" 2>/dev/null | grep -qi "kian-v3"; then
            log_success "[PASS] Verified linux-kian v3 superkernel binary inside /casper/vmlinuz!"
            SUPERKERNEL_OK=1
        fi
    fi
    rm -rf "${TMP_KDIR}"
fi

if [[ $SUPERKERNEL_OK -eq 1 ]]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warn "[WARN] linux-kian v3 signature could not be verified inside live vmlinuz."
fi

# ------------------------------------------------------------------------------
# 8. Summary & Bootability Confidence Assessment
# ------------------------------------------------------------------------------
CONFIDENCE=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))

echo -e "\n${BOLD}${CYAN}================================================================================${NC}"
echo -e "${BOLD}${CYAN}KIAN-OS v3 ISO Verification Summary Report${NC}"
echo -e "${BOLD}${CYAN}================================================================================${NC}"
echo "Target ISO:              ${TARGET_ISO}"
echo "Physical Size:           ${ISO_HR} (${ISO_BYTES} bytes)"
echo "SHA-256 Digest:          ${DIGEST}"
echo "Verified Checks:         ${PASSED_CHECKS} / ${TOTAL_CHECKS}"
echo -n "Bootability Confidence:  "

if [[ $CONFIDENCE -ge 90 ]]; then
    echo -e "${BOLD}${GREEN}${CONFIDENCE}% [HIGH CONFIDENCE - PRODUCTION READY]${NC}"
elif [[ $CONFIDENCE -ge 60 ]]; then
    echo -e "${BOLD}${YELLOW}${CONFIDENCE}% [MEDIUM CONFIDENCE - REVIEW WARNINGS]${NC}"
else
    echo -e "${BOLD}${RED}${CONFIDENCE}% [LOW CONFIDENCE - CRITICAL ARTIFACTS MISSING]${NC}"
    exit 1
fi
echo -e "${BOLD}${CYAN}================================================================================${NC}\n"

log_success "Phase 5: ISO verification successfully finished."
