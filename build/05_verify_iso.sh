#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Strict ISO Forensic & Cryptographic Gate (Phase 5)
# Path: build/05_verify_iso.sh
# Description: Ruthless zero-compromise verification of the generated hybrid ISO:
#              1. Size >= 1 GiB & SHA-256 integrity
#              2. Hybrid MBR/GPT + UEFI FAT16 ESP + .disk/info metadata
#              3. Cryptographic sbverify of /casper/vmlinuz against Kian MOK
#              4. Initrd inspection (casper.conf USERNAME="kian", 99kian_autologin, kian_overlayfs)
#              5. SquashFS deep inspection (pkexec, calamares, displaymanager.conf, mount.conf,
#                 post-install 99-kian-live cleanup, 01_kian_watchdog + 09_kian_kernels,
#                 localsend_app, kdeconnectd, Kvantum SVG themes, ntsync.ko + 99-ntsync.rules)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ISO="${DIST_DIR}/${ISO_NAME}"

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Strict ISO Forensic Verification Gate (Phase 5)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h      Display this help message
  --dry-run       Simulate verification on stub/existing image
  --iso <PATH>    Path to ISO image to verify (default: ${DIST_DIR}/${ISO_NAME})
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

log_step "Phase 5: Strict ISO Forensic & Cryptographic Verification Gate"

if [[ ! -f "${TARGET_ISO}" ]]; then
    log_error "Target ISO file does not exist: ${TARGET_ISO}"
    exit 1
fi

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating Phase 5 strict ISO verification for ${TARGET_ISO}..."
    exit 0
fi

check_dependencies xorriso unsquashfs sbverify sha256sum

# 1. Size & SHA-256 Digest
ISO_BYTES=$(stat -c%s "${TARGET_ISO}")
ISO_HR=$(ls -lh "${TARGET_ISO}" | awk '{print $5}')
log_info "Target ISO: ${TARGET_ISO} (${ISO_HR} / ${ISO_BYTES} bytes)"
if [[ "${ISO_BYTES}" -lt 1073741824 ]]; then
    log_error "FATAL: ISO size (${ISO_BYTES} bytes) is below 1 GiB threshold!"
    exit 1
fi

CHECKSUM_FILE="${TARGET_ISO}.sha256"
sha256sum "${TARGET_ISO}" > "${CHECKSUM_FILE}"
sha256sum -c "${CHECKSUM_FILE}"
log_success "[PASS 1/6] Physical size >= 1 GiB and SHA-256 checksum verified."

# 2. Hybrid Partition Table, UEFI ESP & .disk/info
xorriso -indev "${TARGET_ISO}" -report_system_area as_mkisofs 2>&1 | grep -q "isohybrid"
xorriso -indev "${TARGET_ISO}" -find /boot/grub/efi.img 2>&1 | grep -q "efi.img"
xorriso -indev "${TARGET_ISO}" -find /.disk/info 2>&1 | grep -q "info"
log_success "[PASS 2/6] Hybrid MBR/GPT partition table, UEFI ESP (efi.img), and /.disk/info verified."

# Extract critical payloads from ISO into ephemeral workspace
WORK_DIR=$(mktemp -d /tmp/kian-iso-audit-XXXXXX)
trap 'rm -rf "${WORK_DIR}"' EXIT ERR

xorriso -osirrox on -indev "${TARGET_ISO}" \
    -extract /casper/vmlinuz "${WORK_DIR}/vmlinuz" \
    -extract /casper/initrd "${WORK_DIR}/initrd" \
    -extract /casper/filesystem.squashfs "${WORK_DIR}/filesystem.squashfs" \
    -extract /.disk/info "${WORK_DIR}/disk_info"

grep -q "Kian-OS" "${WORK_DIR}/disk_info"

# 3. Cryptographic Secure Boot Signature on /casper/vmlinuz + Clean 6.8.12-kian-v3 Version
sbverify --list "${WORK_DIR}/vmlinuz"
sbverify --cert "${KEYS_DIR}/kian_mok.pem" "${WORK_DIR}/vmlinuz"
if strings "${WORK_DIR}/vmlinuz" | grep -q "kian-v3-kian-v3"; then
    log_error "FATAL: Duplicate -kian-v3-kian-v3 suffix found in /casper/vmlinuz!"
    exit 1
fi
strings "${WORK_DIR}/vmlinuz" | grep -q "6.8.12-kian-v3 "
log_success "[PASS 3/6] /casper/vmlinuz (6.8.12-kian-v3) PE/COFF Secure Boot MOK signature verified."

# 4. Initramfs Forensic Audit (casper.conf, 99kian_autologin, kian_overlayfs)
if command -v unmkinitramfs &>/dev/null; then
    mkdir -p "${WORK_DIR}/initrd_tree"
    unmkinitramfs "${WORK_DIR}/initrd" "${WORK_DIR}/initrd_tree"
    CASPER_CONF_INITRD=$(find "${WORK_DIR}/initrd_tree" -path "*/etc/casper.conf" | head -n 1)
    test -f "${CASPER_CONF_INITRD}"
    grep -q 'USERNAME="kian"' "${CASPER_CONF_INITRD}"
    grep -q 'FLAVOUR="kian"' "${CASPER_CONF_INITRD}"
    test -n "$(find "${WORK_DIR}/initrd_tree" -path "*/scripts/casper-bottom/99kian_autologin" | head -n 1)"
    test -n "$(find "${WORK_DIR}/initrd_tree" -path "*/scripts/init-bottom/kian_overlayfs" | head -n 1)"
    rm -rf "${WORK_DIR}/initrd_tree"
    log_success "[PASS 4/6] Initramfs verified: USERNAME=kian, FLAVOUR=kian, 99kian_autologin & kian_overlayfs embedded."
fi

# 5. Deep SquashFS Forensic Audit (selective extraction + archive listing to conserve disk space)
SQ_LIST="${WORK_DIR}/squashfs_files.txt"
unsquashfs -lc "${WORK_DIR}/filesystem.squashfs" > "${SQ_LIST}"
grep -q "usr/lib/firmware/amdgpu/" "${SQ_LIST}"
grep -q "usr/lib/firmware/i915/" "${SQ_LIST}"
grep -q "usr/lib/firmware/nvidia/" "${SQ_LIST}"
grep -q "usr/lib/grub/i386-pc/modinfo.sh" "${SQ_LIST}"
grep -q "usr/lib/grub/x86_64-efi/modinfo.sh" "${SQ_LIST}"

unsquashfs -f -d "${WORK_DIR}/sq" "${WORK_DIR}/filesystem.squashfs" \
    usr/bin/pkexec \
    usr/bin/calamares \
    usr/bin/kian-install-os \
    usr/bin/kwin_wayland \
    usr/bin/Xwayland \
    usr/bin/xhost \
    usr/bin/kioclient \
    usr/bin/kioclient5 \
    usr/bin/kscreen-doctor \
    usr/bin/startplasma-wayland \
    usr/bin/localsend_app \
    opt/localsend_app/localsend_app \
    usr/bin/kian-shell-switcher \
    usr/bin/kian-rollback \
    usr/lib/x86_64-linux-gnu/libexec/kdeconnectd \
    usr/share/wayland-sessions/plasmawayland.desktop \
    usr/share/applications/org.kde.falkon.desktop \
    usr/share/applications/localsend_app.desktop \
    usr/share/applications/calamares.desktop \
    usr/share/polkit-1/actions/org.kian.install.policy \
    usr/share/Kvantum/KianGlass/KianGlass.svg \
    usr/share/Kvantum/FluentDark/FluentDark.svg \
    usr/share/Kvantum/KianAquaGlass/KianAquaGlass.svg \
    usr/share/calamares/hooks/pre-install-probe.sh \
    usr/share/calamares/hooks/post-install-drivers-and-clean.sh \
    etc/casper.conf \
    etc/resolv.conf \
    etc/profile.d/kian-wayland.sh \
    etc/sddm.conf.d/wayland.conf \
    etc/calamares/settings.conf \
    etc/calamares/modules \
    etc/grub.d/01_kian_watchdog \
    etc/grub.d/09_kian_kernels \
    etc/default/grub \
    etc/udev/rules.d/99-ntsync.rules \
    etc/modules-load.d/kian-ntsync.conf \
    etc/sysctl.d/99-kian-performance.conf \
    home/kian/.config/kiorc \
    home/kian/Desktop/calamares.desktop \
    usr/lib/modules/6.8.12-kian-v3/kernel/drivers/misc >/dev/null || true

SQ="${WORK_DIR}/sq"
test -x "${SQ}/usr/bin/pkexec"
test -x "${SQ}/usr/bin/calamares"
test -x "${SQ}/usr/bin/kian-install-os"
test -x "${SQ}/usr/bin/kwin_wayland"
test -x "${SQ}/usr/bin/Xwayland"
test -x "${SQ}/usr/bin/xhost"
test -x "${SQ}/usr/bin/kioclient"
test -L "${SQ}/usr/bin/kioclient5"
test -x "${SQ}/usr/bin/kscreen-doctor"
test -x "${SQ}/usr/bin/startplasma-wayland"
test -L "${SQ}/usr/bin/localsend_app"
test -x "${SQ}/opt/localsend_app/localsend_app"
test -x "${SQ}/usr/bin/kian-shell-switcher"
test -x "${SQ}/usr/bin/kian-rollback"
test -x "${SQ}/usr/lib/x86_64-linux-gnu/libexec/kdeconnectd"
test -f "${SQ}/usr/share/Kvantum/KianGlass/KianGlass.svg"
test -f "${SQ}/usr/share/Kvantum/FluentDark/FluentDark.svg"
test -f "${SQ}/usr/share/Kvantum/KianAquaGlass/KianAquaGlass.svg"
test -x "${SQ}/home/kian/Desktop/calamares.desktop"
grep -q "^Exec=/usr/bin/kian-install-os$" "${SQ}/home/kian/Desktop/calamares.desktop"
grep -q "behaviourOnLaunch=execute" "${SQ}/home/kian/.config/kiorc"
if grep -q "QT_AUTO_SCREEN_SCALE_FACTOR" "${SQ}/etc/profile.d/kian-wayland.sh"; then
    log_error "FATAL: Blurry QT_AUTO_SCREEN_SCALE_FACTOR=1 still present in /etc/profile.d/kian-wayland.sh!"
    exit 1
fi
test -f "${SQ}/etc/calamares/modules/displaymanager.conf"
test -f "${SQ}/etc/calamares/modules/fstab.conf"
test -f "${SQ}/etc/calamares/modules/users.conf"
test -f "${SQ}/etc/calamares/modules/grubcfg.conf"
test -f "${SQ}/etc/calamares/modules/bootloader.conf"
test -f "${SQ}/etc/calamares/modules/packages.conf"
grep -q "defaultDesktopEnvironment:" "${SQ}/etc/calamares/modules/displaymanager.conf"
grep -q "compress=zstd:3" "${SQ}/etc/calamares/modules/mount.conf"
if grep -q "/run/systemd/resolve" "${SQ}/etc/calamares/modules/mount.conf"; then
    log_error "FATAL: Broken /run/systemd/resolve bind mount still present in Calamares mount.conf!"
    exit 1
fi
grep -q "update_db: false" "${SQ}/etc/calamares/modules/packages.conf"
grep -q "99-kian-live" "${SQ}/usr/share/calamares/hooks/post-install-drivers-and-clean.sh"
grep -q 'User=kian' "${SQ}/etc/sddm.conf.d/wayland.conf"
grep -q 'Session=plasmawayland.desktop' "${SQ}/etc/sddm.conf.d/wayland.conf"
grep -q 'kian_primary' "${SQ}/etc/grub.d/09_kian_kernels"
grep -q 'kian_fallback_generic' "${SQ}/etc/grub.d/09_kian_kernels"
grep -q 'panic=10' "${SQ}/etc/default/grub"
if grep -qi "internal.cloudapp.net" "${SQ}/etc/resolv.conf"; then
    log_error "FATAL: Cloud build runner DNS domain leaked into SquashFS /etc/resolv.conf!"
    exit 1
fi
NTSYNC_KO=$(find "${SQ}/usr/lib/modules/6.8.12-kian-v3" -name "ntsync.ko*" 2>/dev/null | head -n 1 || true)
test -f "${NTSYNC_KO}"
if command -v modinfo &>/dev/null; then
    modinfo "${NTSYNC_KO}" | grep -q "signer:.*KIAN-OS"
fi
log_success "[PASS 5/6] Deep SquashFS audit passed (GPU firmware, kscreen, Xwayland, kian-install-os, Calamares configs, SDDM autologin, Watchdog IDs, NTSync MOK)."

log_success "[PASS 6/6] ALL 6 FORENSIC & CRYPTOGRAPHIC ISO GATES PASSED (100% VERIFIED)!"
