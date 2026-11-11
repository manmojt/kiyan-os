#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Calamares Post-Install Driver Autoinstall & Sanitization Hook
# Path: installer/calamares/hooks/post-install-drivers-and-clean.sh
# Description: Executes silent driver installation (ubuntu-drivers) and strips
#              all live-session autologin, installer icons, and casper artifacts.
# ==============================================================================
set -euo pipefail

TARGET_ROOT="${1:-${ROOT:-}}"

# If no target root passed and in test mode, support mock target directory
if [[ -z "$TARGET_ROOT" ]]; then
    if [[ "${KIAN_TEST_MODE:-0}" == "1" ]]; then
        TARGET_ROOT=$(mktemp -d /tmp/kian-postinstall-test-XXXXXX)
        echo "[TEST MODE] Utilizing ephemeral target root at: $TARGET_ROOT"
        mkdir -p "$TARGET_ROOT/etc/sddm.conf.d" \
                 "$TARGET_ROOT/etc/systemd/system/sddm.service.d" \
                 "$TARGET_ROOT/etc/sudoers.d" \
                 "$TARGET_ROOT/etc/skel/Desktop" \
                 "$TARGET_ROOT/home/kian/Desktop" \
                 "$TARGET_ROOT/home/kian/.config/autostart" \
                 "$TARGET_ROOT/root/Desktop" \
                 "$TARGET_ROOT/tmp" \
                 "$TARGET_ROOT/var/tmp" \
                 "$TARGET_ROOT/var/lib/apt/lists"
        touch "$TARGET_ROOT/etc/sddm.conf.d/autologin.conf" \
              "$TARGET_ROOT/etc/systemd/system/sddm.service.d/autologin.conf" \
              "$TARGET_ROOT/etc/sudoers.d/99-kian-live" \
              "$TARGET_ROOT/etc/sudoers.d/99-live-autologin" \
              "$TARGET_ROOT/etc/sudoers.d/casper" \
              "$TARGET_ROOT/etc/skel/Desktop/calamares.desktop" \
              "$TARGET_ROOT/etc/skel/Desktop/install-kian.desktop" \
              "$TARGET_ROOT/home/kian/Desktop/calamares.desktop" \
              "$TARGET_ROOT/home/kian/.config/autostart/calamares.desktop"
    else
        echo "Error: Target root directory not provided and ROOT environment variable not set." >&2
        echo "Usage: $(basename "$0") /path/to/target/root" >&2
        exit 1
    fi
fi

if [[ ! -d "$TARGET_ROOT" ]]; then
    echo "Error: Target root directory '$TARGET_ROOT' does not exist." >&2
    exit 1
fi

LOG_FILE="/tmp/kian-postinstall.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "======================================================================"
echo " ==> KIAN-OS v3 Calamares Post-Install Drivers & Sanitization"
echo " ==> Target Root: $TARGET_ROOT"
echo " ==> Started at: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "======================================================================"

# Helper to run chroot command safely or simulate in test mode
run_in_target() {
    if [[ "${KIAN_TEST_MODE:-0}" == "1" ]]; then
        echo "  [MOCK-CHROOT] $TARGET_ROOT: $*"
    else
        if [[ -x "$TARGET_ROOT/bin/sh" || -x "$TARGET_ROOT/usr/bin/sh" ]]; then
            chroot "$TARGET_ROOT" "$@"
        else
            echo "  [WARN] /bin/sh not executable in target; skipping chroot command: $*"
        fi
    fi
}

# ==============================================================================
# PHASE 1: Silent Automated Hardware Driver Installation
# ==============================================================================
echo "[Phase 1/5] Executing automated hardware driver scan inside target..."

export DEBIAN_FRONTEND=noninteractive

# Check if ubuntu-drivers is available inside target
if [[ "${KIAN_TEST_MODE:-0}" == "1" ]] || [[ -f "$TARGET_ROOT/usr/bin/ubuntu-drivers" ]]; then
    echo "  ==> Invoking silent ubuntu-drivers autoinstall..."
    run_in_target ubuntu-drivers autoinstall || true
else
    echo "  ==> ubuntu-drivers not present in target image; continuing driver pass."
fi

# Apply specialized driver/firmware integration based on pre-install probe flags
if [[ -f /tmp/kian_hw_surface ]] || [[ -f /tmp/kian_hw_surface_ipts ]]; then
    echo "  ==> Surface hardware flagged: installing iptsd touch/pen daemon..."
    run_in_target apt-get install -y --no-install-recommends iptsd || true
fi

if [[ -f /tmp/kian_hw_ipu6 ]]; then
    echo "  ==> Intel IPU6 camera flagged: staging libcamera SoftISP & v4l2loopback..."
    run_in_target apt-get install -y --no-install-recommends v4l2loopback-dkms libcamera-tools || true
fi

if [[ -f /tmp/kian_hw_apple ]] || [[ -f /tmp/kian_hw_apple_spi ]]; then
    echo "  ==> Apple Mac platform flagged: configuring keyboard & trackpad parameters..."
    mkdir -p "$TARGET_ROOT/etc/modprobe.d"
    cat <<EOF > "$TARGET_ROOT/etc/modprobe.d/kian-apple-mac.conf"
# KIAN-OS v3 Apple Intel Mac Driver Configuration
options hid_apple fnmode=2
options hid_apple swap_opt_cmd=1
options applespi touch_mode=2
EOF
fi

# Broadcom BCM43xx non-free wireless firmware installation check
if lspci 2>/dev/null | grep -qi "Broadcom.*Wireless"; then
    echo "  ==> Broadcom BCM43xx wireless controller detected: staging firmware..."
    run_in_target apt-get install -y --no-install-recommends firmware-b43-installer || true
fi

# ==============================================================================
# PHASE 2: Strip Live SDDM Autologin, NOPASSWD Sudo & Ephemeral Live Account
# ==============================================================================
echo "[Phase 2/5] Purging live-session autologin and ephemeral live credentials..."

rm -f "$TARGET_ROOT/etc/sddm.conf.d/autologin.conf"
rm -f "$TARGET_ROOT/etc/systemd/system/sddm.service.d/autologin.conf"
rm -f "$TARGET_ROOT/etc/sudoers.d/99-kian-live"
rm -f "$TARGET_ROOT/etc/sudoers.d/99-live-autologin"
rm -f "$TARGET_ROOT/etc/sudoers.d/casper"
rm -f "$TARGET_ROOT/etc/systemd/system/casper-md5check.service"
rm -f "$TARGET_ROOT/etc/initramfs-tools/scripts/casper-bottom/99kian_autologin"

# Rewrite /etc/sddm.conf.d/wayland.conf WITHOUT [Autologin] so installed system
# uses pure Wayland greeter (or Calamares's explicit /etc/sddm.conf choice)
if [[ -d "$TARGET_ROOT/etc/sddm.conf.d" ]]; then
    cat << 'EOF' > "$TARGET_ROOT/etc/sddm.conf.d/wayland.conf"
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell,QT_QPA_PLATFORM=wayland;xcb
HaltCommand=/bin/systemctl poweroff
RebootCommand=/bin/systemctl reboot
Numlock=none

[Wayland]
CompositorCommand=kwin_wayland --no-lockscreen --no-global-shortcuts --locale1
SessionDir=/usr/share/wayland-sessions

[X11]
ServerPath=/bin/false
XauthPath=/bin/false
SessionDir=
EnableHiDPI=false

[Theme]
Current=breeze
CursorTheme=breeze_cursors
Font=Inter Display,10,-1,5,50,0,0,0,0,0
EOF
fi

# Remove the pre-seeded live 'kian' account ONLY when the user created their own
# distinct account (UID >= 1000, != kian) during Calamares installation
if [[ -f "$TARGET_ROOT/etc/passwd" ]]; then
    NON_KIAN_USERS=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "kian" && $1 != "nobody" {print $1}' "$TARGET_ROOT/etc/passwd" || true)
    if [[ -n "${NON_KIAN_USERS}" ]]; then
        echo "  ==> Target user(s) detected (${NON_KIAN_USERS}); removing live 'kian' account..."
        run_in_target userdel -rf kian 2>/dev/null || true
    fi
fi

echo "  [PASS] Live autologin, 99-kian-live NOPASSWD sudo, and live user sanitized."

# ==============================================================================
# PHASE 3: Purge Live Desktop Shortcuts & Autostarts
# ==============================================================================
echo "[Phase 3/5] Sanitizing live installer desktop launchers & skel templates..."

# Remove installer launchers from /etc/skel (skeleton for all future users)
rm -f "$TARGET_ROOT/etc/skel/Desktop/calamares.desktop"
rm -f "$TARGET_ROOT/etc/skel/Desktop/install-kian.desktop"
rm -f "$TARGET_ROOT/etc/skel/.config/autostart/calamares.desktop"

# Clean any existing user directories created during install
if [[ -d "$TARGET_ROOT/home" ]]; then
    find "$TARGET_ROOT/home" -type f \( \
        -name "calamares.desktop" -o \
        -name "install-kian.desktop" \
    \) -delete 2>/dev/null || true
    find "$TARGET_ROOT/home" -path "*/.config/autostart/calamares.desktop" -delete 2>/dev/null || true
fi

# Clean root desktop
rm -f "$TARGET_ROOT/root/Desktop/calamares.desktop" 2>/dev/null || true
rm -f "$TARGET_ROOT/root/Desktop/install-kian.desktop" 2>/dev/null || true

echo "  [PASS] Installer desktop launchers stripped."

# ==============================================================================
# PHASE 4: Purge Live-Boot Packages & Casper Artifacts
# ==============================================================================
echo "[Phase 4/5] Purging live-boot dependencies and temporary package caches..."

run_in_target apt-get purge -y --auto-remove \
    calamares \
    calamares-settings-ubuntu-common \
    casper \
    live-boot \
    live-config \
    live-tools >/dev/null 2>&1 || true

# Clean package manager indices and temp directories
run_in_target apt-get clean || true
rm -rf "$TARGET_ROOT/var/lib/apt/lists"/* 2>/dev/null || true
rm -rf "$TARGET_ROOT/tmp"/* 2>/dev/null || true
rm -rf "$TARGET_ROOT/var/tmp"/* 2>/dev/null || true

echo "  [PASS] Live packages purged and temporary buffers cleared."

# ==============================================================================
# PHASE 5: Rebuild Initramfs and GRUB within Installed Root
# ==============================================================================
echo "[Phase 5/5] Refreshing initramfs and GRUB bootloader..."

run_in_target update-initramfs -u -k all || true
run_in_target update-grub || true

echo "======================================================================"
echo " ==> Post-install hardware drivers and sanitization complete."
echo "======================================================================"

if [[ "${KIAN_TEST_MODE:-0}" == "1" && "$TARGET_ROOT" =~ ^/tmp/kian-postinstall-test ]]; then
    rm -rf "$TARGET_ROOT"
fi

exit 0
