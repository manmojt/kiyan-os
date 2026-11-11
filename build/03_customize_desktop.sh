#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Desktop, Installer & Recovery Staging (Phase 3)
# Path: build/03_customize_desktop.sh
# Description: Installs KWin Wayland, Plasma minimal, SDDM, Kvantum, fontconfig;
#              deploys SDDM Wayland greeter; installs Inter Display & Vazirmatn;
#              deploys kian-shell-switcher & Triple-Shell layouts; configures
#              Calamares 3.3.x & hooks; deploys P2P sync services; installs
#              kian-rollback, btrfs-apt-hook, 41_kian_snapshots, and boot watchdog.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOTFS="${ROOTFS_DIR}"

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Desktop & Installer Assembly Recipe (Phase 3)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h          Display this help message
  --dry-run           Simulate file deployment and configuration
  --rootfs-dir <DIR>  Target rootfs directory (default: ${ROOTFS_DIR})

Examples:
  sudo ./03_customize_desktop.sh
  ./03_customize_desktop.sh --dry-run
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
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

log_step "Phase 3: Desktop Environment, Installer & Recovery Customization"

require_root

if [[ ! -d "${TARGET_ROOTFS}" ]]; then
    log_error "Target rootfs directory not found: ${TARGET_ROOTFS}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. In-Chroot Desktop & Graphics Stack Installation
# ------------------------------------------------------------------------------
log_step "Installing KWin Wayland, Minimal Plasma, SDDM, Kvantum & Calamares"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating chroot package installation of desktop stack..."
    log_info "[DRY-RUN] Packages: plasma-workspace-wayland kwin-wayland sddm calamares kvantum fontconfig"
else
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -euo pipefail << 'CHROOT_EOF'
apt-get update
apt-get install -y --no-install-recommends \
    plasma-workspace-wayland \
    kwin-wayland \
    plasma-desktop konsole dolphin plasma-discover plasma-discover-backend-flatpak flatpak plasma-nm plasma-pa systemsettings falkon ark vlc kate gwenview plymouth plymouth-theme-spinner \
    sddm \
    sddm-theme-breeze \
    qt5-style-kvantum \
    qt5-style-kvantum-themes \
    fontconfig \
    fonts-inter \
    fonts-vazirmatn \
    fonts-firacode \
    calamares \
    calamares-settings-ubuntu-common \
    rsync \
    efibootmgr \
    dosfstools \
    btrfs-progs

# Mask legacy X11 session desktop files so SDDM exclusively offers Wayland
if [[ -f /usr/share/xsessions/plasma.desktop ]]; then
    mv /usr/share/xsessions/plasma.desktop /usr/share/xsessions/plasma.desktop.disabled 2>/dev/null || true
fi

# Set animated boot splash theme
plymouth-set-default-theme -R spinner 2>/dev/null || true

apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF
fi

# ------------------------------------------------------------------------------
# 2. SDDM Pure Wayland Greeter Configuration
# ------------------------------------------------------------------------------
log_step "Configuring SDDM Pure Wayland Greeter"

mkdir -p "${TARGET_ROOTFS}/etc/sddm.conf.d"
if [[ -f "${DESKTOP_DIR}/sddm/wayland.conf" ]]; then
    log_info "Deploying ${DESKTOP_DIR}/sddm/wayland.conf..."
    run_cmd cp "${DESKTOP_DIR}/sddm/wayland.conf" "${TARGET_ROOTFS}/etc/sddm.conf.d/wayland.conf"
else
    log_info "Writing default SDDM Wayland configuration..."
    cat << 'EOF' > "${TARGET_ROOTFS}/etc/sddm.conf.d/wayland.conf"
[General]
DisplayServer=wayland
GreeterEnvironment=QT_QPA_PLATFORM=wayland

[Wayland]
CompositorCommand=kwin_wayland --no-global-shortcuts --no-lockscreen --locale1
EOF
fi

# ------------------------------------------------------------------------------
# 3. Subpixel Typography & Font Rendering
# ------------------------------------------------------------------------------
log_step "Deploying Subpixel Typography Configuration (Inter Display & Vazirmatn)"

mkdir -p "${TARGET_ROOTFS}/etc/fonts/conf.d"
if [[ -f "${DESKTOP_DIR}/fonts/50-kian-subpixel-typography.conf" ]]; then
    log_info "Deploying 50-kian-subpixel-typography.conf..."
    run_cmd cp "${DESKTOP_DIR}/fonts/50-kian-subpixel-typography.conf" "${TARGET_ROOTFS}/etc/fonts/conf.d/50-kian-subpixel-typography.conf"
    run_cmd cp "${DESKTOP_DIR}/fonts/50-kian-subpixel-typography.conf" "${TARGET_ROOTFS}/etc/fonts/local.conf"
fi

# ------------------------------------------------------------------------------
# 4. Triple-Shell Interface Engine & Kvantum Dark Crystal Theme
# ------------------------------------------------------------------------------
log_step "Deploying Triple-Shell Engine, Layouts, and Kvantum Glass Theme"

# Deploy kian-shell-switcher CLI / DBus script
mkdir -p "${TARGET_ROOTFS}/usr/local/bin" "${TARGET_ROOTFS}/usr/bin"
if [[ -f "${DESKTOP_DIR}/triple-shell/kian-shell-switcher" ]]; then
    log_info "Deploying kian-shell-switcher..."
    run_cmd cp "${DESKTOP_DIR}/triple-shell/kian-shell-switcher" "${TARGET_ROOTFS}/usr/local/bin/kian-shell-switcher"
    run_cmd cp "${DESKTOP_DIR}/triple-shell/kian-shell-switcher" "${TARGET_ROOTFS}/usr/bin/kian-shell-switcher"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/local/bin/kian-shell-switcher" "${TARGET_ROOTFS}/usr/bin/kian-shell-switcher"
fi

# Deploy Shell Layout Templates (Kian Native, Windows Fluent, macOS Aqua)
mkdir -p "${TARGET_ROOTFS}/usr/share/kian/shell-layouts" "${TARGET_ROOTFS}/usr/share/kian/triple-shell"
if [[ -d "${DESKTOP_DIR}/triple-shell/layouts" ]]; then
    log_info "Deploying Triple-Shell layout templates..."
    run_cmd cp -r "${DESKTOP_DIR}/triple-shell/layouts"/* "${TARGET_ROOTFS}/usr/share/kian/shell-layouts/"
    run_cmd ln -sfn "/usr/share/kian/shell-layouts" "${TARGET_ROOTFS}/usr/share/kian/triple-shell/layouts"
fi

# Deploy Kvantum Glassmorphic Theme (KianGlass)
mkdir -p "${TARGET_ROOTFS}/usr/share/Kvantum/KianGlass" "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/KianGlass"
if [[ -d "${DESKTOP_DIR}/triple-shell/kvantum/KianGlass" ]]; then
    log_info "Deploying KianGlass Kvantum theme..."
    run_cmd cp -r "${DESKTOP_DIR}/triple-shell/kvantum/KianGlass"/* "${TARGET_ROOTFS}/usr/share/Kvantum/KianGlass/"
    run_cmd cp -r "${DESKTOP_DIR}/triple-shell/kvantum/KianGlass"/* "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/KianGlass/"
fi

# Set default Kvantum configuration to KianGlass
cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/kvantum.kvconfig"
[General]
theme=KianGlass
EOF

# ------------------------------------------------------------------------------
# 5. Calamares Graphical Installer Configuration & Hooks
# ------------------------------------------------------------------------------
log_step "Configuring Calamares 3.3.x Installer, Modules, and Hooks"

mkdir -p "${TARGET_ROOTFS}/etc/calamares/modules" \
         "${TARGET_ROOTFS}/usr/share/calamares/hooks" \
         "${TARGET_ROOTFS}/usr/lib/calamares/hooks"

# Deploy settings.conf
if [[ -f "${INSTALLER_DIR}/calamares/settings.conf" ]]; then
    log_info "Deploying Calamares settings.conf..."
    run_cmd cp "${INSTALLER_DIR}/calamares/settings.conf" "${TARGET_ROOTFS}/etc/calamares/settings.conf"
fi

# Deploy Calamares Modules
if [[ -d "${INSTALLER_DIR}/calamares/modules" ]]; then
    log_info "Deploying Calamares module descriptors..."
    run_cmd cp -r "${INSTALLER_DIR}/calamares/modules"/* "${TARGET_ROOTFS}/etc/calamares/modules/"
fi

# Deploy Calamares Branding
if [[ -d "${INSTALLER_DIR}/calamares/branding" ]]; then
    log_info "Deploying Calamares branding descriptors..."
    mkdir -p "${TARGET_ROOTFS}/etc/calamares/branding" "${TARGET_ROOTFS}/usr/share/calamares/branding"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/branding"/* "${TARGET_ROOTFS}/etc/calamares/branding/"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/branding"/* "${TARGET_ROOTFS}/usr/share/calamares/branding/"
fi

# Deploy Calamares Hooks to both /usr/share/calamares/hooks and /usr/lib/calamares/hooks
if [[ -d "${INSTALLER_DIR}/calamares/hooks" ]]; then
    log_info "Deploying Calamares pre/post-install hooks..."
    run_cmd cp -r "${INSTALLER_DIR}/calamares/hooks"/* "${TARGET_ROOTFS}/usr/share/calamares/hooks/"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/hooks"/* "${TARGET_ROOTFS}/usr/lib/calamares/hooks/"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/share/calamares/hooks"/*.sh 2>/dev/null || true
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/lib/calamares/hooks"/*.sh 2>/dev/null || true
fi

# Deploy Live Desktop Launcher for Calamares
mkdir -p "${TARGET_ROOTFS}/etc/skel/Desktop" "${TARGET_ROOTFS}/home/kian/Desktop"
cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Install Kian-OS v3
GenericName=Live Operating System Installer
Comment=Install KIAN-OS v3 cleanly to disk with automated Btrfs layout
Exec=pkexec /usr/bin/calamares
Icon=calamares
Terminal=false
Categories=Qt;System;
StartupNotify=true
EOF
chmod +x "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
cp "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop" "${TARGET_ROOTFS}/home/kian/Desktop/" 2>/dev/null || true
chmod +x "${TARGET_ROOTFS}/home/kian/Desktop/"*.desktop 2>/dev/null || true
chown -R 1000:1000 "${TARGET_ROOTFS}/home/kian" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Local Offline P2P Synchronization Services
# ------------------------------------------------------------------------------
log_step "Deploying Offline P2P Sync Units (LocalSend & KDE Connect Clipboard)"

mkdir -p "${TARGET_ROOTFS}/usr/lib/systemd/user" \
         "${TARGET_ROOTFS}/etc/systemd/user/default.target.wants" \
         "${TARGET_ROOTFS}/etc/systemd/user/graphical-session.target.wants"

if [[ -f "${DESKTOP_DIR}/sync/localsend.service" ]]; then
    log_info "Deploying localsend.service (user unit)..."
    run_cmd cp "${DESKTOP_DIR}/sync/localsend.service" "${TARGET_ROOTFS}/usr/lib/systemd/user/localsend.service"
    ln -sf "/usr/lib/systemd/user/localsend.service" "${TARGET_ROOTFS}/etc/systemd/user/default.target.wants/localsend.service"
fi

if [[ -f "${DESKTOP_DIR}/sync/kdeconnect-clipboard.service" ]]; then
    log_info "Deploying kdeconnect-clipboard.service (user unit)..."
    run_cmd cp "${DESKTOP_DIR}/sync/kdeconnect-clipboard.service" "${TARGET_ROOTFS}/usr/lib/systemd/user/kdeconnect-clipboard.service"
    ln -sf "/usr/lib/systemd/user/kdeconnect-clipboard.service" "${TARGET_ROOTFS}/etc/systemd/user/graphical-session.target.wants/kdeconnect-clipboard.service"
fi

# ------------------------------------------------------------------------------
# 7. Btrfs Snapshot Engine, Rollback CLI & GRUB Watchdog
# ------------------------------------------------------------------------------
log_step "Deploying Btrfs Rollback Engine, APT Snapshot Hooks & GRUB Watchdog"

mkdir -p "${TARGET_ROOTFS}/usr/lib/kian" "${TARGET_ROOTFS}/etc/apt/apt.conf.d" \
         "${TARGET_ROOTFS}/etc/grub.d" "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom"

# Deploy kian-rollback CLI
if [[ -f "${SCRIPTS_DIR}/kian-rollback" ]]; then
    log_info "Deploying kian-rollback utility..."
    run_cmd cp "${SCRIPTS_DIR}/kian-rollback" "${TARGET_ROOTFS}/usr/local/bin/kian-rollback"
    run_cmd cp "${SCRIPTS_DIR}/kian-rollback" "${TARGET_ROOTFS}/usr/bin/kian-rollback"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/local/bin/kian-rollback" "${TARGET_ROOTFS}/usr/bin/kian-rollback"
fi

# Deploy btrfs-apt-hook & apt configuration
if [[ -f "${SCRIPTS_DIR}/btrfs-apt-hook" ]]; then
    log_info "Deploying btrfs-apt-hook..."
    run_cmd cp "${SCRIPTS_DIR}/btrfs-apt-hook" "${TARGET_ROOTFS}/usr/lib/kian/btrfs-apt-hook"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/lib/kian/btrfs-apt-hook"
fi

cat << 'EOF' > "${TARGET_ROOTFS}/etc/apt/apt.conf.d/80kian-btrfs-snapshot"
// KIAN-OS v3: Automatic Pre/Post Transaction Atomic Btrfs Snapshots
DPkg::Pre-Invoke  { "/usr/lib/kian/btrfs-apt-hook pre"; };
DPkg::Post-Invoke { "/usr/lib/kian/btrfs-apt-hook post"; };
EOF

# Deploy dynamic GRUB snapshot menu generator
if [[ -f "${SCRIPTS_DIR}/41_kian_snapshots" ]]; then
    log_info "Deploying 41_kian_snapshots GRUB menu generator..."
    run_cmd cp "${SCRIPTS_DIR}/41_kian_snapshots" "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
    run_cmd chmod +x "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
fi

# Deploy Dual-Kernel GRUB Bootcounter Watchdog
cat << 'EOF' > "${TARGET_ROOTFS}/etc/grub.d/01_kian_watchdog"
#!/bin/sh
set -e
cat << 'GRUB_WATCHDOG'
# KIAN-OS v3 Dual-Kernel Bootcounter Watchdog
load_env

if [ -z "${bootcount}" ]; then
    set bootcount=0
fi
if [ -z "${bootlimit}" ]; then
    set bootlimit=3
fi

if [ "${bootcount}" -ge "${bootlimit}" ]; then
    echo ":: [WARNING] KIAN-OS Watchdog: Boot limit reached (${bootcount}/${bootlimit})."
    echo ":: Primary kernel (linux-kian v3) failed; failing over to Generic Fallback..."
    set default="kian_fallback_generic"
else
    if [ "${bootcount}" = "2" ]; then
        set bootcount=3
    elif [ "${bootcount}" = "1" ]; then
        set bootcount=2
    elif [ "${bootcount}" = "0" ]; then
        set bootcount=1
    else
        set bootcount=1
    fi
    save_env bootcount
    set default="kian_primary"
fi
GRUB_WATCHDOG
EOF
chmod +x "${TARGET_ROOTFS}/etc/grub.d/01_kian_watchdog"

# Deploy kian-boot-success.service
if [[ -f "${SCRIPTS_DIR}/kian-boot-success.service" ]]; then
    log_info "Deploying kian-boot-success.service..."
    run_cmd cp "${SCRIPTS_DIR}/kian-boot-success.service" "${TARGET_ROOTFS}/etc/systemd/system/kian-boot-success.service"
    mkdir -p "${TARGET_ROOTFS}/etc/systemd/system/graphical.target.wants"
    ln -sf "/etc/systemd/system/kian-boot-success.service" "${TARGET_ROOTFS}/etc/systemd/system/graphical.target.wants/kian-boot-success.service"
fi

# Deploy Initramfs Ephemeral OverlayFS Early Boot Hook
log_info "Deploying initramfs kian_overlayfs hook..."
cat << 'EOF' > "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom/kian_overlayfs"
#!/bin/sh
# /etc/initramfs-tools/scripts/init-bottom/kian_overlayfs
# Hook to assemble OverlayFS over a read-only Btrfs snapshot during boot
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0;; esac

. /scripts/functions

OVERLAY_ENABLED=0
for cmd in $(cat /proc/cmdline); do
    case "$cmd" in
        kian.overlay=1)
            OVERLAY_ENABLED=1
            ;;
    esac
done

if [ "$OVERLAY_ENABLED" -ne 1 ]; then
    exit 0
fi

log_begin_msg "KIAN-OS: Engaging Ephemeral OverlayFS on Read-Only Snapshot Root"

mkdir -p /run/overlay_tmpfs
mount -t tmpfs -o mode=0755,size=50% tmpfs_root /run/overlay_tmpfs

mkdir -p /run/overlay_tmpfs/upper
mkdir -p /run/overlay_tmpfs/work
mkdir -p /run/overlay_newroot

mount -t overlay overlay -o lowerdir=${rootmnt},upperdir=/run/overlay_tmpfs/upper,workdir=/run/overlay_tmpfs/work /run/overlay_newroot

mkdir -p /run/overlay_newroot/mnt/.ro_snapshot
mount --move ${rootmnt} /run/overlay_newroot/mnt/.ro_snapshot
mount --move /run/overlay_newroot ${rootmnt}

log_end_msg
exit 0
EOF
chmod +x "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom/kian_overlayfs"

# ------------------------------------------------------------------------------
# 8. Full OS Branding & Identity (Kian-OS v3 Noble Edition)
# ------------------------------------------------------------------------------
log_step "Applying Full Kian-OS v3 Operating System Branding & Identity"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/os-release"
NAME="Kian-OS"
VERSION="3.0 (Noble Edition)"
ID=kian-os
ID_LIKE="ubuntu debian"
PRETTY_NAME="Kian-OS v3 (Noble Edition)"
VERSION_ID="3.0"
HOME_URL="https://github.com/manmojt/kiyan-os"
SUPPORT_URL="https://github.com/manmojt/kiyan-os/issues"
BUG_REPORT_URL="https://github.com/manmojt/kiyan-os/issues"
PRIVACY_POLICY_URL="https://github.com/manmojt/kiyan-os"
UBUNTU_CODENAME=noble
LOGO=kian-logo
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/lsb-release"
DISTRIB_ID=Kian-OS
DISTRIB_RELEASE=3.0
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="Kian-OS v3 (Noble Edition)"
EOF

echo "Kian-OS v3 (Noble Edition) \n \l" > "${TARGET_ROOTFS}/etc/issue"
echo "Kian-OS v3 (Noble Edition) \n \l" > "${TARGET_ROOTFS}/etc/issue.net"
echo "kian-os" > "${TARGET_ROOTFS}/etc/hostname"

log_success "Phase 3: Desktop customization and installer assembly complete!"
