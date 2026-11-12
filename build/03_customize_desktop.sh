#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Desktop, Installer & Recovery Staging (Phase 3)
# Path: build/03_customize_desktop.sh
# Description: Installs KWin Wayland, Plasma 5.27 minimal, SDDM, Kvantum,
#              pkexec/Polkit KDE agent, KDE Connect, LocalSend, Papirus icons;
#              enforces Casper + SDDM Wayland autologin; configures Calamares
#              3.3.x & post-install security cleanup; deploys Triple-Shell,
#              Btrfs rollback engine, Dual-Kernel GRUB Watchdog (01 + 09),
#              and rebuilds initramfs for all installed kernels at completion.
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

unmount_virtual_fs() {
    local root="$1"
    if [[ -d "${root}" ]]; then
        umount -l "${root}/dev/pts" 2>/dev/null || true
        umount -l "${root}/dev" 2>/dev/null || true
        umount -l "${root}/proc" 2>/dev/null || true
        umount -l "${root}/sys" 2>/dev/null || true
        umount -l "${root}/run" 2>/dev/null || true
    fi
}

trap 'unmount_virtual_fs "${TARGET_ROOTFS}"' EXIT ERR

if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Mounting virtual pseudo-filesystems (/dev, /proc, /sys, /run) for Phase 3 chroot..."
    mountpoint -q "${TARGET_ROOTFS}/dev" || mount --bind /dev "${TARGET_ROOTFS}/dev"
    mountpoint -q "${TARGET_ROOTFS}/dev/pts" || mount --bind /dev/pts "${TARGET_ROOTFS}/dev/pts"
    mountpoint -q "${TARGET_ROOTFS}/proc" || mount -t proc proc "${TARGET_ROOTFS}/proc"
    mountpoint -q "${TARGET_ROOTFS}/sys" || mount -t sysfs sys "${TARGET_ROOTFS}/sys"
    mountpoint -q "${TARGET_ROOTFS}/run" || mount --bind /run "${TARGET_ROOTFS}/run"
fi

# ------------------------------------------------------------------------------
# 1. In-Chroot Desktop, Polkit, P2P Apps & Calamares Installation
# ------------------------------------------------------------------------------
log_step "Installing KWin Wayland, Plasma, SDDM, pkexec, KDE Connect, LocalSend & Calamares"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating chroot package installation of desktop stack..."
    log_info "[DRY-RUN] Packages: plasma-workspace-wayland kwin-wayland sddm pkexec kdeconnect calamares"
else
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -euo pipefail << 'CHROOT_EOF'
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    plasma-workspace \
    plasma-workspace-wayland \
    kwin-wayland \
    xwayland x11-xserver-utils \
    kscreen kde-cli-tools \
    plasma-desktop \
    konsole dolphin plasma-discover plasma-discover-backend-flatpak flatpak \
    plasma-nm plasma-pa systemsettings falkon ark vlc kate gwenview \
    plymouth plymouth-theme-spinner \
    sddm sddm-theme-breeze \
    pkexec polkitd polkit-kde-agent-1 \
    kdeconnect \
    libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 libayatana-ido3-0.4-0 xdg-user-dirs \
    qt5-style-kvantum qt5-style-kvantum-themes \
    breeze-icon-theme breeze-gtk-theme kde-config-gtk-style papirus-icon-theme \
    fontconfig fonts-inter fonts-vazirmatn fonts-firacode \
    calamares calamares-settings-ubuntu-common \
    rsync efibootmgr dosfstools btrfs-progs

# Install Official LocalSend v1.18.2 x86_64 .deb so localsend_app.desktop & /usr/bin/localsend_app are genuine
echo ":: Installing LocalSend v1.18.2 x86_64 package..."
curl -fsSL --retry 3 -o /tmp/localsend.deb \
    "https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-x86-64.deb"
dpkg -i /tmp/localsend.deb
rm -f /tmp/localsend.deb
ln -sfn /opt/localsend_app/localsend_app /usr/bin/localsend
test -x /usr/bin/localsend_app
test -f /usr/share/applications/localsend_app.desktop

# Verify mandatory desktop, display EDID/Wayland, and installer binaries exist right now (ZERO silent omissions!)
test -x /usr/bin/pkexec
test -x /usr/bin/calamares
test -x /usr/bin/kwin_wayland
test -x /usr/bin/Xwayland
test -x /usr/bin/xhost
test -x /usr/bin/kioclient5
test -x /usr/bin/kscreen-doctor
test -x /usr/bin/startplasma-wayland
test -x /usr/lib/x86_64-linux-gnu/libexec/kdeconnectd
test -f /usr/share/wayland-sessions/plasmawayland.desktop

# Mask legacy X11 session desktop files so SDDM exclusively offers Pure Wayland
if [[ -f /usr/share/xsessions/plasma.desktop ]]; then
    mv /usr/share/xsessions/plasma.desktop /usr/share/xsessions/plasma.desktop.disabled
fi

# Set animated boot splash theme without rebuilding initramfs prematurely
plymouth-set-default-theme spinner || true

apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF
fi

# ------------------------------------------------------------------------------
# 2. Pure Wayland Environment, SDDM Greeter & Casper Autologin Protection
# ------------------------------------------------------------------------------
log_step "Configuring Pure Wayland Environment, SDDM Greeter & Casper Live Autologin"

mkdir -p "${TARGET_ROOTFS}/etc/profile.d" \
         "${TARGET_ROOTFS}/etc/sddm.conf.d" \
         "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom"

# NOTE: Never set QT_AUTO_SCREEN_SCALE_FACTOR=1 under KWin Wayland — KWin handles
# native Wayland HiDPI fractional/integer scaling directly without bitmap blur!
cat << 'EOF' > "${TARGET_ROOTFS}/etc/profile.d/kian-wayland.sh"
# KIAN-OS v3 Pure Wayland Session Defaults
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM="wayland;xcb"
EOF
chmod 0644 "${TARGET_ROOTFS}/etc/profile.d/kian-wayland.sh"

if [[ -f "${DESKTOP_DIR}/sddm/wayland.conf" ]]; then
    log_info "Deploying ${DESKTOP_DIR}/sddm/wayland.conf..."
    run_cmd cp "${DESKTOP_DIR}/sddm/wayland.conf" "${TARGET_ROOTFS}/etc/sddm.conf.d/wayland.conf"
else
    cat << 'EOF' > "${TARGET_ROOTFS}/etc/sddm.conf.d/wayland.conf"
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QT_QPA_PLATFORM=wayland;xcb

[Wayland]
CompositorCommand=kwin_wayland --no-global-shortcuts --no-lockscreen --locale1
SessionDir=/usr/share/wayland-sessions

[Autologin]
User=kian
Session=plasmawayland.desktop
Relogin=false
EOF
fi

# Authoritative Casper-Bottom Hook (runs AFTER casper's 15autologin & 25adduser!)
# Fixes Casper's Ubuntu bug where disabling /usr/share/xsessions/plasma.desktop wrote empty Session= into /etc/sddm.conf
cat << 'EOF' > "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom/99kian_autologin"
#!/bin/sh
PREREQ=""
DESCRIPTION="Enforcing KIAN-OS v3 Pure Wayland Live Autologin..."

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /scripts/casper-functions
log_begin_msg "$DESCRIPTION"

cat > /root/etc/sddm.conf << 'SDDM_EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QT_QPA_PLATFORM=wayland;xcb

[Wayland]
CompositorCommand=kwin_wayland --no-lockscreen --no-global-shortcuts --locale1
SessionDir=/usr/share/wayland-sessions

[X11]
ServerPath=/bin/false
XauthPath=/bin/false
SessionDir=

[Autologin]
User=kian
Session=plasmawayland.desktop
Relogin=false
SDDM_EOF

mkdir -p /root/etc/sudoers.d
echo "kian ALL=(ALL) NOPASSWD:ALL" > /root/etc/sudoers.d/99-kian-live
chmod 0440 /root/etc/sudoers.d/99-kian-live

if [ -d /root/home/kian ]; then
    chroot /root chown -R kian:kian /home/kian 2>/dev/null || true
fi

log_end_msg
exit 0
EOF
chmod +x "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom/99kian_autologin"

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
# 4. Triple-Shell Interface Engine & Complete Kvantum Theme Suite
# ------------------------------------------------------------------------------
log_step "Deploying Triple-Shell Engine, Layouts, and All 3 Kvantum Glass Themes"

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

# Deploy All 3 Kvantum Themes (KianGlass, FluentDark, KianAquaGlass) with SVG + kvconfig
for kv_theme in KianGlass FluentDark KianAquaGlass; do
    if [[ -d "${DESKTOP_DIR}/triple-shell/kvantum/${kv_theme}" ]]; then
        log_info "Deploying ${kv_theme} Kvantum theme..."
        mkdir -p "${TARGET_ROOTFS}/usr/share/Kvantum/${kv_theme}" "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/${kv_theme}"
        run_cmd cp -r "${DESKTOP_DIR}/triple-shell/kvantum/${kv_theme}"/* "${TARGET_ROOTFS}/usr/share/Kvantum/${kv_theme}/"
        run_cmd cp -r "${DESKTOP_DIR}/triple-shell/kvantum/${kv_theme}"/* "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/${kv_theme}/"
    fi
done

cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/Kvantum/kvantum.kvconfig"
[General]
theme=KianGlass
EOF

mkdir -p "${TARGET_ROOTFS}/etc/skel/.config/kian"
echo "kian-native" > "${TARGET_ROOTFS}/etc/skel/.config/kian/current-shell"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/kdeglobals"
[General]
ColorScheme=BreezeDark
widgetStyle=kvantum-dark

[Icons]
Theme=Papirus-Dark

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
EOF

# ------------------------------------------------------------------------------
# 5. Calamares Graphical Installer Configuration & Hooks
# ------------------------------------------------------------------------------
log_step "Configuring Calamares 3.3.x Installer, Modules, and Hooks"

mkdir -p "${TARGET_ROOTFS}/etc/calamares/modules" \
         "${TARGET_ROOTFS}/usr/share/calamares/hooks" \
         "${TARGET_ROOTFS}/usr/lib/calamares/hooks" \
         "${TARGET_ROOTFS}/usr/sbin"

if [[ -f "${INSTALLER_DIR}/calamares/settings.conf" ]]; then
    log_info "Deploying Calamares settings.conf..."
    run_cmd cp "${INSTALLER_DIR}/calamares/settings.conf" "${TARGET_ROOTFS}/etc/calamares/settings.conf"
fi

if [[ -d "${INSTALLER_DIR}/calamares/modules" ]]; then
    log_info "Deploying Calamares module descriptors (including displaymanager.conf & mount.conf)..."
    run_cmd cp -r "${INSTALLER_DIR}/calamares/modules"/* "${TARGET_ROOTFS}/etc/calamares/modules/"
fi

if [[ -d "${INSTALLER_DIR}/calamares/branding" ]]; then
    log_info "Deploying Calamares branding descriptors..."
    mkdir -p "${TARGET_ROOTFS}/etc/calamares/branding" "${TARGET_ROOTFS}/usr/share/calamares/branding"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/branding"/* "${TARGET_ROOTFS}/etc/calamares/branding/"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/branding"/* "${TARGET_ROOTFS}/usr/share/calamares/branding/"
fi

if [[ -d "${INSTALLER_DIR}/calamares/hooks" ]]; then
    log_info "Deploying Calamares pre/post-install hooks..."
    run_cmd cp -r "${INSTALLER_DIR}/calamares/hooks"/* "${TARGET_ROOTFS}/usr/share/calamares/hooks/"
    run_cmd cp -r "${INSTALLER_DIR}/calamares/hooks"/* "${TARGET_ROOTFS}/usr/lib/calamares/hooks/"
    if [[ -f "${INSTALLER_DIR}/calamares/hooks/post-install-drivers-and-clean.sh" ]]; then
        run_cmd cp "${INSTALLER_DIR}/calamares/hooks/post-install-drivers-and-clean.sh" "${TARGET_ROOTFS}/usr/sbin/post-install-drivers-and-clean.sh"
        run_cmd chmod +x "${TARGET_ROOTFS}/usr/sbin/post-install-drivers-and-clean.sh"
    fi
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/share/calamares/hooks"/*.sh
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/lib/calamares/hooks"/*.sh
fi

# Deploy Pure-Wayland + Xwayland Root Wrapper for Calamares Double-Click Launch
mkdir -p "${TARGET_ROOTFS}/usr/bin" \
         "${TARGET_ROOTFS}/usr/share/applications" \
         "${TARGET_ROOTFS}/usr/share/polkit-1/actions" \
         "${TARGET_ROOTFS}/etc/skel/.config" \
         "${TARGET_ROOTFS}/etc/skel/Desktop" \
         "${TARGET_ROOTFS}/home/kian/Desktop"

cat << 'EOF' > "${TARGET_ROOTFS}/usr/bin/kian-install-os"
#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mkdir -p -m 0700 /tmp/calamares-runtime-root
    chown 0:0 /tmp/calamares-runtime-root
    export XDG_RUNTIME_DIR="/tmp/calamares-runtime-root"
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        for wsock in /run/user/*/wayland-*; do
            if [[ -S "${wsock}" && "${wsock}" != *.lock ]]; then
                export WAYLAND_DISPLAY="${wsock}"
                break
            fi
        done
    fi
    if [[ -z "${DISPLAY:-}" ]]; then
        for xsock in /tmp/.X11-unix/X*; do
            if [[ -S "${xsock}" ]]; then
                export DISPLAY=":${xsock##*/X}"
                break
            fi
        done
    fi
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
    exec /usr/bin/calamares -D6 "$@" >>/tmp/calamares-launch.log 2>&1
fi

USER_UID="$(id -u)"
USER_RUNTIME="${XDG_RUNTIME_DIR:-/run/user/${USER_UID}}"
WL_SOCK="${WAYLAND_DISPLAY:-wayland-0}"
if [[ "${WL_SOCK}" != /* ]]; then
    WL_ABS="${USER_RUNTIME}/${WL_SOCK}"
else
    WL_ABS="${WL_SOCK}"
fi

X_DISP="${DISPLAY:-}"
if [[ -z "${X_DISP}" ]]; then
    for xsock in /tmp/.X11-unix/X*; do
        if [[ -S "${xsock}" ]]; then
            X_DISP=":${xsock##*/X}"
            break
        fi
    done
fi

if command -v xhost >/dev/null 2>&1 && [[ -n "${X_DISP}" ]]; then
    DISPLAY="${X_DISP}" xhost +SI:localuser:root >/dev/null 2>&1 || true
fi

if sudo -n true 2>/dev/null; then
    exec sudo env \
        WAYLAND_DISPLAY="${WL_ABS}" \
        DISPLAY="${X_DISP:-:0}" \
        QT_QPA_PLATFORM="wayland;xcb" \
        XDG_CURRENT_DESKTOP="KDE" \
        KDE_FULL_SESSION="true" \
        LANG="${LANG:-en_US.UTF-8}" \
        /usr/bin/kian-install-os "$@"
else
    exec pkexec env \
        WAYLAND_DISPLAY="${WL_ABS}" \
        DISPLAY="${X_DISP:-:0}" \
        QT_QPA_PLATFORM="wayland;xcb" \
        XDG_CURRENT_DESKTOP="KDE" \
        KDE_FULL_SESSION="true" \
        LANG="${LANG:-en_US.UTF-8}" \
        /usr/bin/kian-install-os "$@"
fi
EOF
chmod 0755 "${TARGET_ROOTFS}/usr/bin/kian-install-os"

cat << 'EOF' > "${TARGET_ROOTFS}/usr/share/polkit-1/actions/org.kian.install.policy"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Kian-OS</vendor>
  <action id="org.kian.install.pkexec.run">
    <description>Install Kian-OS v3</description>
    <message>Authentication is required to install Kian-OS v3</message>
    <icon_name>calamares</icon_name>
    <defaults>
      <allow_any>yes</allow_any>
      <allow_inactive>yes</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/kian-install-os</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
EOF

# Configure KDE KIO so double-clicking Desktop launchers executes immediately (never opens text editor / prompt)
cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/kiorc"
[Executable scripts]
behaviourOnLaunch=execute
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Install Kian-OS v3
GenericName=Live Operating System Installer
Comment=Install KIAN-OS v3 cleanly to disk with automated Btrfs layout
Exec=/usr/bin/kian-install-os
TryExec=/usr/bin/kian-install-os
Icon=calamares
Terminal=false
Categories=Qt;System;
StartupNotify=true
X-KDE-SubstituteUID=false
EOF
chmod 0755 "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
cp -f "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop" "${TARGET_ROOTFS}/usr/share/applications/calamares.desktop"
chmod 0755 "${TARGET_ROOTFS}/usr/share/applications/calamares.desktop"

if [[ "${DRY_RUN}" != "1" ]]; then
    cp -a "${TARGET_ROOTFS}/etc/skel/." "${TARGET_ROOTFS}/home/kian/"
    chmod 0755 "${TARGET_ROOTFS}/home/kian/Desktop/"*.desktop
    chown -R 1000:1000 "${TARGET_ROOTFS}/home/kian"
fi

# ------------------------------------------------------------------------------
# 6. Local Offline P2P Synchronization Services
# ------------------------------------------------------------------------------
log_step "Deploying Offline P2P Sync Units (LocalSend & KDE Connect Clipboard)"

mkdir -p "${TARGET_ROOTFS}/usr/lib/systemd/user" \
         "${TARGET_ROOTFS}/etc/systemd/user/graphical-session.target.wants"

if [[ -f "${DESKTOP_DIR}/sync/localsend.service" ]]; then
    log_info "Deploying localsend.service (user graphical-session unit)..."
    run_cmd cp "${DESKTOP_DIR}/sync/localsend.service" "${TARGET_ROOTFS}/usr/lib/systemd/user/localsend.service"
    ln -sf "/usr/lib/systemd/user/localsend.service" "${TARGET_ROOTFS}/etc/systemd/user/graphical-session.target.wants/localsend.service"
fi

if [[ -f "${DESKTOP_DIR}/sync/kdeconnect-clipboard.service" ]]; then
    log_info "Deploying kdeconnect-clipboard.service (user graphical-session unit)..."
    run_cmd cp "${DESKTOP_DIR}/sync/kdeconnect-clipboard.service" "${TARGET_ROOTFS}/usr/lib/systemd/user/kdeconnect-clipboard.service"
    ln -sf "/usr/lib/systemd/user/kdeconnect-clipboard.service" "${TARGET_ROOTFS}/etc/systemd/user/graphical-session.target.wants/kdeconnect-clipboard.service"
fi

# ------------------------------------------------------------------------------
# 7. Btrfs Snapshot Engine, Rollback CLI & Dual-Kernel GRUB Watchdog
# ------------------------------------------------------------------------------
log_step "Deploying Btrfs Rollback Engine, APT Snapshot Hooks & Dual-Kernel GRUB Watchdog"

mkdir -p "${TARGET_ROOTFS}/usr/lib/kian" "${TARGET_ROOTFS}/etc/apt/apt.conf.d" \
         "${TARGET_ROOTFS}/etc/grub.d" "${TARGET_ROOTFS}/etc/default" \
         "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom"

if [[ -f "${SCRIPTS_DIR}/kian-rollback" ]]; then
    log_info "Deploying kian-rollback utility..."
    run_cmd cp "${SCRIPTS_DIR}/kian-rollback" "${TARGET_ROOTFS}/usr/local/bin/kian-rollback"
    run_cmd cp "${SCRIPTS_DIR}/kian-rollback" "${TARGET_ROOTFS}/usr/bin/kian-rollback"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/local/bin/kian-rollback" "${TARGET_ROOTFS}/usr/bin/kian-rollback"
fi

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

if [[ -f "${SCRIPTS_DIR}/41_kian_snapshots" ]]; then
    log_info "Deploying 41_kian_snapshots GRUB menu generator..."
    run_cmd cp "${SCRIPTS_DIR}/41_kian_snapshots" "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
    run_cmd chmod +x "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
fi

# Authoritative /etc/default/grub with Kian-OS v3 kernel command line, NVIDIA GSP KMS & panic=10 watchdog trigger
cat << 'EOF' > "${TARGET_ROOTFS}/etc/default/grub"
GRUB_DEFAULT="kian_primary"
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="Kian-OS v3"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash preempt=full split_lock_mitigate=0 nouveau.config=NvGspRm=1 panic=10"
GRUB_CMDLINE_LINUX=""
EOF

# Deploy Dual-Kernel GRUB Bootcounter Watchdog (01_kian_watchdog runs AFTER 00_header!)
cat << 'EOF' > "${TARGET_ROOTFS}/etc/grub.d/01_kian_watchdog"
#!/bin/sh
set -e
cat << 'GRUB_WATCHDOG'
# KIAN-OS v3 Dual-Kernel Bootcounter Watchdog
if [ -s $prefix/grubenv ]; then
    load_env
fi

if [ -z "${bootcount}" ]; then
    set bootcount=0
fi
if [ -z "${bootlimit}" ]; then
    set bootlimit=3
fi

if [ "${bootcount}" -ge "${bootlimit}" ]; then
    echo ":: [WARNING] KIAN-OS Watchdog: Boot limit reached (${bootcount}/${bootlimit})."
    echo ":: Primary kernel (linux-kian v3) failed; failing over to Generic LTS Fallback..."
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

# Deploy Dedicated Dual-Kernel Menu Generator (09_kian_kernels)
# Guarantees menuentries with exact --id 'kian_primary' and --id 'kian_fallback_generic' ALWAYS exist in grub.cfg!
cat << 'EOF' > "${TARGET_ROOTFS}/etc/grub.d/09_kian_kernels"
#!/bin/sh
set -e

prefix="/usr"
exec_prefix="/usr"
datarootdir="/usr/share"
. "$pkgdatadir/grub-mkconfig_lib"

PRIMARY_KVER=$(ls -1 /boot/vmlinuz-*kian-v3* 2>/dev/null | sed 's|^/boot/vmlinuz-||' | sort -V | tail -n 1 || true)
FALLBACK_KVER=$(ls -1 /boot/vmlinuz-*-generic 2>/dev/null | sed 's|^/boot/vmlinuz-||' | sort -V | tail -n 1 || true)

if [ -z "${PRIMARY_KVER}" ] && [ -z "${FALLBACK_KVER}" ]; then
    exit 0
fi

if [ "x${GRUB_DEVICE_UUID}" = "x" ] || [ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ]; then
    LINUX_ROOT_DEVICE=${GRUB_DEVICE}
else
    LINUX_ROOT_DEVICE=UUID=${GRUB_DEVICE_UUID}
fi

ROOT_SUBVOL_FLAG=""
if [ "x${GRUB_FS}" = "xbtrfs" ]; then
    rootsubvol="$(make_system_path_relative_to_its_root /)"
    rootsubvol="${rootsubvol#/}"
    if [ -n "${rootsubvol}" ]; then
        ROOT_SUBVOL_FLAG="rootflags=subvol=${rootsubvol}"
    fi
fi

BOOT_PREP="$(prepare_grub_to_access_device "${GRUB_DEVICE_BOOT}" | grub_add_tab)"
REL_BOOT="$(make_system_path_relative_to_its_root /boot)"

emit_kian_entry() {
    entry_title="$1"
    entry_id="$2"
    kver="$3"
    extra_args="$4"
    vmlinuz_rel="${REL_BOOT}/vmlinuz-${kver}"
    initrd_rel="${REL_BOOT}/initrd.img-${kver}"
    [ -f "/boot/vmlinuz-${kver}" ] || return 0
    [ -f "/boot/initrd.img-${kver}" ] || return 0

    cat << ENTRY_EOF
menuentry '${entry_title}' --class kian-os --class gnu-linux --class gnu --class os --id '${entry_id}' {
	load_video
	gfxmode \$linux_gfx_mode
	insmod gzio
${BOOT_PREP}
	echo 'Loading ${entry_title} (${kver}) ...'
	linux ${vmlinuz_rel} root=${LINUX_ROOT_DEVICE} ro ${ROOT_SUBVOL_FLAG} ${GRUB_CMDLINE_LINUX} ${extra_args}
	initrd ${initrd_rel}
}
ENTRY_EOF
}

if [ -n "${PRIMARY_KVER}" ]; then
    emit_kian_entry "Kian-OS v3 (Superkernel ${PRIMARY_KVER} - BORE 1000Hz Wayland)" "kian_primary" "${PRIMARY_KVER}" "${GRUB_CMDLINE_LINUX_DEFAULT}"
fi

if [ -n "${FALLBACK_KVER}" ]; then
    emit_kian_entry "Kian-OS v3 (Safe LTS Fallback ${FALLBACK_KVER})" "kian_fallback_generic" "${FALLBACK_KVER}" "quiet splash"
fi
EOF
chmod +x "${TARGET_ROOTFS}/etc/grub.d/09_kian_kernels"

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
# 8. Full OS Branding & Final Initramfs Regeneration for All Installed Kernels
# ------------------------------------------------------------------------------
log_step "Applying Full Kian-OS v3 Branding & Regenerating Initramfs (With All Hooks)"

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

if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Regenerating initramfs for ALL installed kernels so casper.conf, 99kian_autologin, kian_overlayfs & early SPI modules are embedded..."
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive CASPER_GENERATE_UUID=1 bash -euo pipefail << 'CHROOT_INITRD_EOF'
for kver in $(ls -1 /lib/modules | sort -V); do
    echo ":: Building initramfs for kernel ${kver}..."
    update-initramfs -c -k "${kver}" || update-initramfs -u -k "${kver}"
    test -s "/boot/initrd.img-${kver}"
done
KVER_KIAN=$(ls -1 /lib/modules | grep -E "^6\.8\..*-kian-v3$" | sort -V | tail -n 1)
test -n "${KVER_KIAN}"
ln -sfn "vmlinuz-${KVER_KIAN}" /boot/vmlinuz
ln -sfn "initrd.img-${KVER_KIAN}" /boot/initrd.img
CHROOT_INITRD_EOF
    unmount_virtual_fs "${TARGET_ROOTFS}"
fi

log_success "Phase 3: Desktop customization, security hardening, and initramfs regeneration complete!"
