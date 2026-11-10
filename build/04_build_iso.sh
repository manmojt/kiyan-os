#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Live ISO Mastering (Phase 4)
# Path: build/04_build_iso.sh
# Description: Sanitizes rootfs, extracts live kernel/initrd, generates Zstd-19
#              filesystem.squashfs, stages ISOLINUX BIOS and GRUB UEFI bootloaders,
#              assembles EFI FAT boot partition, and masters hybrid ISO via xorriso.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOTFS="${ROOTFS_DIR}"
TARGET_ISO="${DIST_DIR}/${ISO_NAME}"
TARGET_TREE="${ISO_TREE_DIR}"

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Live ISO Mastering Recipe (Phase 4)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h          Display this help message
  --dry-run           Simulate ISO assembly without compression or mastering
  --rootfs-dir <DIR>  Source rootfs directory (default: ${ROOTFS_DIR})
  --output <FILE>     Target ISO file path (default: ${DIST_DIR}/${ISO_NAME})
  --iso-tree <DIR>    Staging directory for ISO filesystem (default: ${ISO_TREE_DIR})

Examples:
  sudo ./04_build_iso.sh
  ./04_build_iso.sh --dry-run
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
        --rootfs-dir)
            TARGET_ROOTFS="$2"
            shift 2
            ;;
        --output)
            TARGET_ISO="$2"
            shift 2
            ;;
        --iso-tree)
            TARGET_TREE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

log_step "Phase 4: Live Squashfs Compression & Universal Hybrid ISO Mastering"

require_root
check_dependencies mksquashfs xorriso

if [[ ! -d "${TARGET_ROOTFS}" ]]; then
    log_error "Rootfs directory not found: ${TARGET_ROOTFS}"
    exit 1
fi

mkdir -p "${DIST_DIR}" "${TARGET_TREE}"

# ------------------------------------------------------------------------------
# 1. Sanitize Target Rootfs Prior to Compression
# ------------------------------------------------------------------------------
log_step "Sanitizing Rootfs Filesystem"

log_info "Unmounting any residual virtual filesystems..."
umount -l "${TARGET_ROOTFS}/dev/pts" 2>/dev/null || true
umount -l "${TARGET_ROOTFS}/dev" 2>/dev/null || true
umount -l "${TARGET_ROOTFS}/proc" 2>/dev/null || true
umount -l "${TARGET_ROOTFS}/sys" 2>/dev/null || true
umount -l "${TARGET_ROOTFS}/run" 2>/dev/null || true

if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Truncating machine-id and clearing temporary staging caches..."
    truncate -s 0 "${TARGET_ROOTFS}/etc/machine-id" 2>/dev/null || true
    rm -rf "${TARGET_ROOTFS}/tmp"/* "${TARGET_ROOTFS}/var/tmp"/* 2>/dev/null || true
    rm -rf "${TARGET_ROOTFS}/var/cache/apt/archives"/*.deb 2>/dev/null || true
    rm -rf "${TARGET_ROOTFS}/var/lib/apt/lists"/* 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. Stage ISO Directory Tree Hierarchy
# ------------------------------------------------------------------------------
log_step "Preparing ISO Tree Hierarchy & Casper Live Environment"

rm -rf "${TARGET_TREE}"
mkdir -p "${TARGET_TREE}"/{casper,isolinux,EFI/BOOT,boot/grub}

# Locate and extract latest kernel and initramfs
log_info "Extracting live kernel and initramfs images..."
LIVE_KERNEL=""
LIVE_INITRD=""

# Preference 1: linux-kian v3 kernel
LIVE_KERNEL=$(find "${TARGET_ROOTFS}/boot" -maxdepth 1 -name "vmlinuz*kian-v3*" 2>/dev/null | sort -V | tail -n 1 || true)
LIVE_INITRD=$(find "${TARGET_ROOTFS}/boot" -maxdepth 1 -name "initrd.img*kian-v3*" 2>/dev/null | sort -V | tail -n 1 || true)

# Ensure initramfs is generated if vmlinuz-kian-v3 exists but initrd was pending
if [[ -n "${LIVE_KERNEL}" && ( -z "${LIVE_INITRD}" || ! -f "${LIVE_INITRD}" ) ]]; then
    KVER=$(basename "${LIVE_KERNEL}" | sed "s/^vmlinuz-//")
    log_info "Generating dedicated initramfs for ${KVER}..."
    chroot "${TARGET_ROOTFS}" update-initramfs -c -k "${KVER}" 2>/dev/null || true
    LIVE_INITRD=$(find "${TARGET_ROOTFS}/boot" -maxdepth 1 -name "initrd.img*${KVER}*" 2>/dev/null | sort -V | tail -n 1 || true)
fi

# Preference 2: generic stock kernel (fallback only)
if [[ -z "${LIVE_KERNEL}" || ! -f "${LIVE_KERNEL}" ]]; then
    log_warn "linux-kian v3 not found, falling back to generic kernel..."
    LIVE_KERNEL=$(find "${TARGET_ROOTFS}/boot" -maxdepth 1 -name "vmlinuz*" 2>/dev/null | sort -V | tail -n 1 || true)
fi
if [[ -z "${LIVE_INITRD}" || ! -f "${LIVE_INITRD}" ]]; then
    LIVE_INITRD=$(find "${TARGET_ROOTFS}/boot" -maxdepth 1 -name "initrd.img*" 2>/dev/null | sort -V | tail -n 1 || true)
fi

if [[ "${LIVE_KERNEL}" == *"kian-v3"* ]]; then
    log_success ":: VERIFIED linux-kian v3 superkernel active: $(basename "${LIVE_KERNEL}")"
else
    log_warn ":: WARNING: Selected kernel is not linux-kian v3: $(basename "${LIVE_KERNEL}")"
fi

if [[ -n "${LIVE_KERNEL}" && -f "${LIVE_KERNEL}" ]]; then
    log_info "Selected live kernel: $(basename "${LIVE_KERNEL}")"
    run_cmd cp "${LIVE_KERNEL}" "${TARGET_TREE}/casper/vmlinuz"
else
    log_warn "No vmlinuz found in rootfs /boot."
    if [[ "${DRY_RUN}" == "1" ]]; then
        touch "${TARGET_TREE}/casper/vmlinuz"
    else
        log_error "Cannot build ISO without a bootable kernel binary."
        exit 1
    fi
fi

if [[ -n "${LIVE_INITRD}" && -f "${LIVE_INITRD}" ]]; then
    log_info "Selected live initrd: $(basename "${LIVE_INITRD}")"
    run_cmd cp "${LIVE_INITRD}" "${TARGET_TREE}/casper/initrd"
else
    log_warn "No initrd found in rootfs /boot."
    if [[ "${DRY_RUN}" == "1" ]]; then
        touch "${TARGET_TREE}/casper/initrd"
    else
        log_error "Cannot build ISO without a bootable initramfs image."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 3. Compress Rootfs into Squashfs with Zstandard-19
# ------------------------------------------------------------------------------
log_step "Compressing Rootfs with Zstandard Level 19"

SQUASHFS_FILE="${TARGET_TREE}/casper/filesystem.squashfs"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating mksquashfs with -comp zstd -Xcompression-level 19..."
    touch "${SQUASHFS_FILE}"
    echo "1048576000" > "${TARGET_TREE}/casper/filesystem.size"
else
    log_info "Executing mksquashfs (blocksize: 1MB, zstd:19)..."
    mksquashfs "${TARGET_ROOTFS}" "${SQUASHFS_FILE}" \
        -comp zstd -Xcompression-level 19 -b 1048576 -noappend

    # Calculate uncompressed filesystem size
    printf $(du -sx --block-size=1 "${TARGET_ROOTFS}" | cut -f1) > "${TARGET_TREE}/casper/filesystem.size"
fi

# ------------------------------------------------------------------------------
# 4. Configure UEFI GRUB Bootloader & EFI System Partition
# ------------------------------------------------------------------------------
log_step "Configuring UEFI GRUB Bootloader & EFI FAT System Partition"

cat << 'EOF' > "${TARGET_TREE}/boot/grub/grub.cfg"
set default="0"
set timeout=10

insmod all_video
insmod font
insmod gfxterm

menuentry "Try or Install KIAN-OS v3 (linux-kian v3, Pure Wayland)" --class kian --class os {
    linux /casper/vmlinuz boot=casper console=tty0 console=ttyS0,115200 quiet splash acpi_osi="Windows 2020" ---
    initrd /casper/initrd
}

menuentry "Try or Install KIAN-OS v3 (Safe Graphics Mode - Nomodeset)" --class recovery --class os {
    linux /casper/vmlinuz boot=casper nomodeset console=tty0 console=ttyS0,115200 quiet splash ---
    initrd /casper/initrd
}

menuentry "Boot from System Hard Drive" --class harddrive {
    set root=(hd0)
    chainloader +1
}
EOF

# Stage EFI Binaries
SHIM_BIN=""
GRUB_BIN=""
MM_BIN=""

for path in \
    "${TARGET_ROOTFS}/usr/lib/shim/shimx64.efi.signed" \
    "/usr/lib/shim/shimx64.efi.signed" \
    "/boot/efi/EFI/BOOT/BOOTX64.EFI"; do
    if [[ -f "$path" ]]; then
        SHIM_BIN="$path"
        break
    fi
done

for path in \
    "${TARGET_ROOTFS}/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" \
    "/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" \
    "/boot/efi/EFI/BOOT/grubx64.efi"; do
    if [[ -f "$path" ]]; then
        GRUB_BIN="$path"
        break
    fi
done

for path in \
    "${TARGET_ROOTFS}/usr/lib/shim/mmx64.efi" \
    "/usr/lib/shim/mmx64.efi"; do
    if [[ -f "$path" ]]; then
        MM_BIN="$path"
        break
    fi
done

if [[ -n "${SHIM_BIN}" ]]; then
    run_cmd cp "${SHIM_BIN}" "${TARGET_TREE}/EFI/BOOT/BOOTX64.EFI"
fi
if [[ -n "${GRUB_BIN}" ]]; then
    run_cmd cp "${GRUB_BIN}" "${TARGET_TREE}/EFI/BOOT/grubx64.efi"
fi
if [[ -n "${MM_BIN}" ]]; then
    run_cmd cp "${MM_BIN}" "${TARGET_TREE}/EFI/BOOT/mmx64.efi"
fi

# Also place grub.cfg in EFI/BOOT so grubx64.efi finds it immediately in UEFI mode
cp "${TARGET_TREE}/boot/grub/grub.cfg" "${TARGET_TREE}/EFI/BOOT/grub.cfg"

# Assemble FAT16 EFI Boot Partition Image
EFI_IMG="${TARGET_TREE}/boot/grub/efi.img"
log_info "Assembling FAT16 EFI system partition image: ${EFI_IMG}..."

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating mkfs.vfat and mcopy for efi.img..."
    touch "${EFI_IMG}"
else
    dd if=/dev/zero of="${EFI_IMG}" bs=1M count=16 status=none
    mkfs.vfat -F 16 -n "KIAN_EFI" "${EFI_IMG}" >/dev/null

    if command -v mmd &>/dev/null && command -v mcopy &>/dev/null; then
        mmd -i "${EFI_IMG}" ::/EFI 2>/dev/null || true
        mmd -i "${EFI_IMG}" ::/EFI/BOOT 2>/dev/null || true
        if compgen -G "${TARGET_TREE}/EFI/BOOT/*" > /dev/null; then
            mcopy -i "${EFI_IMG}" -s "${TARGET_TREE}/EFI/BOOT"/* ::/EFI/BOOT/ 2>/dev/null || true
        mmd -i "${EFI_IMG}" ::/boot 2>/dev/null || true
        mmd -i "${EFI_IMG}" ::/boot/grub 2>/dev/null || true
        mcopy -i "${EFI_IMG}" "${TARGET_TREE}/boot/grub/grub.cfg" ::/boot/grub/grub.cfg 2>/dev/null || true
        fi
    else
        # Fallback to loopback mount
        EFI_TMP_MNT=$(mktemp -d /tmp/kian-efi-mnt-XXXXXX)
        mount -o loop "${EFI_IMG}" "${EFI_TMP_MNT}"
        mkdir -p "${EFI_TMP_MNT}/EFI/BOOT"
        cp -r "${TARGET_TREE}/EFI/BOOT"/* "${EFI_TMP_MNT}/EFI/BOOT/" 2>/dev/null || true
        umount "${EFI_TMP_MNT}"
        rmdir "${EFI_TMP_MNT}"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Configure Legacy BIOS ISOLINUX Bootloader
# ------------------------------------------------------------------------------
log_step "Configuring Legacy BIOS ISOLINUX Bootloader"

ISOLINUX_BIN=""
for path in /usr/lib/ISOLINUX/isolinux.bin /usr/lib/syslinux/isolinux.bin; do
    if [[ -f "$path" ]]; then
        ISOLINUX_BIN="$path"
        break
    fi
done

if [[ -n "${ISOLINUX_BIN}" ]]; then
    run_cmd cp "${ISOLINUX_BIN}" "${TARGET_TREE}/isolinux/isolinux.bin"
fi

# Copy syslinux helper modules if present
for module_dir in /usr/lib/syslinux/modules/bios /usr/lib/syslinux; do
    if [[ -d "$module_dir" ]]; then
        cp "$module_dir"/*.c32 "${TARGET_TREE}/isolinux/" 2>/dev/null || true
    fi
done

cat << 'EOF' > "${TARGET_TREE}/isolinux/isolinux.cfg"
UI menu.c32
PROMPT 0
TIMEOUT 100
DEFAULT kian

MENU TITLE KIAN-OS v3 (Noble Numbat 24.04 LTS)

LABEL kian
  MENU LABEL Try or Install KIAN-OS v3 (Pure Wayland)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper console=tty0 console=ttyS0,115200 quiet splash acpi_osi="Windows 2020" ---

LABEL safe
  MENU LABEL Try or Install KIAN-OS v3 (Safe Graphics Mode)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper nomodeset console=tty0 console=ttyS0,115200 quiet splash ---
EOF

# ------------------------------------------------------------------------------
# 6. Master Universal Hybrid Bootable ISO with xorriso
# ------------------------------------------------------------------------------
log_step "Mastering Universal Hybrid Bootable ISO via xorriso"

ISOHDPFX=""
for path in \
    /usr/lib/ISOLINUX/isohdpfx.bin \
    /usr/lib/syslinux/modules/bios/isohdpfx.bin \
    /usr/lib/syslinux/isohdpfx.bin; do
    if [[ -f "$path" ]]; then
        ISOHDPFX="$path"
        break
    fi
done

XORRISO_ARGS=(
    -as mkisofs
    -iso-level 3
    -full-iso9660-filenames
    -volid "KIAN_OS_V3"
    -output "${TARGET_ISO}"
)

# Attach BIOS El Torito boot if isolinux.bin exists
if [[ -f "${TARGET_TREE}/isolinux/isolinux.bin" ]]; then
    XORRISO_ARGS+=(
        -eltorito-boot isolinux/isolinux.bin
        -eltorito-catalog isolinux/boot.cat
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
fi

# Attach MBR hybrid partition table if isohdpfx exists
if [[ -n "${ISOHDPFX}" && -f "${ISOHDPFX}" ]]; then
    XORRISO_ARGS+=(-isohybrid-mbr "${ISOHDPFX}" -partition_offset 16)
fi

# Attach UEFI El Torito alt boot image if efi.img exists
if [[ -f "${EFI_IMG}" ]]; then
    XORRISO_ARGS+=(
        -eltorito-alt-boot
        -e boot/grub/efi.img
        -no-emul-boot
        -isohybrid-gpt-basdat
    )
fi

XORRISO_ARGS+=("${TARGET_TREE}")

log_info "Executing xorriso to generate ${TARGET_ISO}..."
if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating xorriso execution..."
    touch "${TARGET_ISO}"
else
    xorriso "${XORRISO_ARGS[@]}"
fi

log_success "Phase 4: Universal Hybrid ISO created successfully at: ${TARGET_ISO}"
if [[ -f "${TARGET_ISO}" ]]; then
    ls -lh "${TARGET_ISO}"
fi
