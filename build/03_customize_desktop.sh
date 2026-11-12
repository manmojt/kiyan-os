#!/usr/bin/env bash
# ==============================================================================
# Kiyan OS v4 Build System: Zorin OS 18 + GNOME 46 + Unlocked Pro Layouts (Phase 3)
# Path: build/03_customize_desktop.sh
# Description: Installs genuine Zorin OS 18 (GNOME 46) desktop stack, unlocks
#              macOS Sequoia & Windows 11 Pro layouts for FREE, applies Blur-my-Shell
#              frosted top bar/dock (solid window bodies!), Full RGB AMD display fix,
#              Kiyan Plymouth boot logo (+ GUI Boot Logo Changer), Firefox, LocalSend,
#              Calamares Wayland installer, and Pro edition Dev/Creator/Gaming suite.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOTFS="${ROOTFS_DIR}"
EDITION="${KIYAN_EDITION:-core}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $(basename "$0") [--dry-run] [--rootfs-dir <DIR>] [--edition core|pro]"
            exit 0
            ;;
        --dry-run)
            export DRY_RUN=1
            shift
            ;;
        --rootfs-dir)
            TARGET_ROOTFS="$2"
            shift 2
            ;;
        --edition)
            EDITION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_step "Phase 3: Kiyan OS v4 (${EDITION^^} Edition) — Zorin OS 18 + GNOME 46 + Unlocked macOS/Win11 Pro"

require_root

if [[ ! -d "${TARGET_ROOTFS}" ]]; then
    log_error "Target rootfs does not exist: ${TARGET_ROOTFS}. Run 02_bootstrap_rootfs.sh first."
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
# 1. Install Genuine Zorin OS 18 (Noble GNOME 46) + Firefox + LocalSend (+ Pro Suite)
# ------------------------------------------------------------------------------
log_step "Installing Genuine Zorin OS 18 GNOME 46 Stack, Unlocked Pro Extensions & Apps (${EDITION^^})"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating Zorin OS 18 + GNOME 46 + ${EDITION} suite installation..."
else
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive KIYAN_EDITION="${EDITION}" bash -euo pipefail << 'CHROOT_EOF'
mkdir -p /etc/apt/apt.conf.d /etc/apt/keyrings
cat << 'APT_EOF' > /etc/apt/apt.conf.d/99-kiyan-resilient-net
Acquire::ForceIPv4 "true";
Acquire::Retries "5";
Acquire::http::Timeout "25";
Acquire::https::Timeout "25";
APT_EOF

# 1. Official Zorin OS 18 Stable PPA (Noble)
echo ":: Configuring Zorin OS 18 Stable Repository..."
curl -fsSL --retry 4 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xB2228B8CCA5C00A2C59D35E530FCF8F64F71B61C" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/zorinos-stable.gpg
chmod 0644 /etc/apt/keyrings/zorinos-stable.gpg
cat << 'ZORIN_EOF' > /etc/apt/sources.list.d/zorinos-stable.list
deb [signed-by=/etc/apt/keyrings/zorinos-stable.gpg] https://ppa.launchpadcontent.net/zorinos/stable/ubuntu noble main
ZORIN_EOF

# 2. Official Mozilla Native Firefox Repository (No Snap!)
echo ":: Configuring Official Mozilla APT Repository..."
curl -fsSL --retry 4 "https://packages.mozilla.org/apt/repo-signing-key.gpg" -o /etc/apt/keyrings/packages.mozilla.org.asc
chmod 0644 /etc/apt/keyrings/packages.mozilla.org.asc
cat << 'MOZ_EOF' > /etc/apt/sources.list.d/mozilla.list
deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main
MOZ_EOF
cat << 'PIN_EOF' > /etc/apt/preferences.d/mozilla
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1001
PIN_EOF

apt-get update

# 3. Install Complete Zorin OS 18 GNOME 46 Desktop, Settings, Power/Battery, Color, Store & Extensions
apt-get install -y --no-install-recommends \
    gdm3 gnome-shell gnome-session gnome-control-center gnome-settings-daemon \
    gnome-tweaks gnome-shell-extension-manager dconf-cli libglib2.0-bin \
    zorin-desktop-session zorin-os-default-settings \
    zorin-desktop-themes zorin-icon-themes zorin-auto-theme zorin-sound-theme \
    zorin-appearance zorin-appearance-layouts-support zorin-appearance-layouts-shell-core \
    gnome-shell-extensions-zorin-desktop \
    gnome-shell-extension-zorin-dash \
    gnome-shell-extension-zorin-hide-activities-move-clock \
    gnome-shell-extension-zorin-magic-lamp-effect \
    gnome-shell-extension-zorin-desktop-cube \
    gnome-shell-extension-zorin-spatial-window-switcher \
    gnome-shell-extension-zorin-window-move-effect \
    gnome-shell-extension-zorin-tiling-shell \
    gnome-shell-extension-zorin-taskbar \
    gnome-shell-extension-zorin-menu \
    gnome-shell-extension-zorin-desktop-icons \
    gnome-shell-extension-zorin-appindicator \
    gnome-shell-extension-zorin-printers \
    zorin-connect zorin-exec-guard zorin-exec-guard-app-db \
    zorin-windows-app-support-desktop-files \
    fonts-zorin-os-core fonts-inter fonts-vazirmatn fonts-firacode fonts-jetbrains-mono fonts-noto-color-emoji \
    nautilus gnome-terminal gnome-text-editor gnome-calculator gnome-system-monitor \
    gnome-disk-utility baobab eog evince file-roller gnome-screenshot \
    gnome-power-manager power-profiles-daemon upower brightnessctl colord \
    packagekit flatpak gnome-software gnome-software-plugin-flatpak \
    xwayland x11-xserver-utils desktop-file-utils xdg-user-dirs xdg-user-dirs-gtk \
    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
    pkexec polkitd policykit-desktop-privileges zenity unzip zip p7zip-full \
    bluez gnome-bluetooth-sendto network-manager-gnome pulseaudio-utils alsa-utils \
    firefox vlc \
    plymouth plymouth-label plymouth-theme-spinner \
    calamares calamares-settings-ubuntu-common \
    rsync efibootmgr dosfstools btrfs-progs ntfs-3g exfatprogs

# Never include Zorin telemetry census!
apt-get purge -y zorin-os-census zorin-os-census-live zorin-os-upgrader 2>/dev/null || true

# 4. Install WhiteSur macOS Glossy Icon & GTK/Shell Theme Option alongside Zorin Themes
apt-get install -y --no-install-recommends git sassc gtk2-engines-murrine
rm -rf /tmp/whitesur && mkdir -p /tmp/whitesur
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/whitesur/icons
/tmp/whitesur/icons/install.sh -d /usr/share/icons -n WhiteSur
rm -rf /tmp/whitesur

# 5. Install Blur-my-Shell v78 (GNOME 46) + Fullscreen-to-Empty-Workspace (macOS Fullscreen Spaces!)
mkdir -p /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
curl -fsSL --retry 4 -o /tmp/bms.zip \
    "https://github.com/aunetx/blur-my-shell/releases/download/v78/blur-my-shell%40aunetx.shell-extension.zip"
unzip -oq /tmp/bms.zip -d /usr/share/gnome-shell/extensions/blur-my-shell@aunetx
cp -f /usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
rm -f /tmp/bms.zip

mkdir -p /usr/share/gnome-shell/extensions/fullscreen-to-empty-workspace@aiono.dev
curl -fsSL --retry 4 -o /tmp/fsws.zip \
    "https://extensions.gnome.org/download-extension/fullscreen-to-empty-workspace@aiono.dev.shell-extension.zip?version_tag=54748"
unzip -oq /tmp/fsws.zip -d /usr/share/gnome-shell/extensions/fullscreen-to-empty-workspace@aiono.dev
cp -f /usr/share/gnome-shell/extensions/fullscreen-to-empty-workspace@aiono.dev/schemas/*.gschema.xml /usr/share/glib-2.0/schemas/
rm -f /tmp/fsws.zip

chmod -R a+rX /usr/share/gnome-shell/extensions/blur-my-shell@aunetx \
              /usr/share/gnome-shell/extensions/fullscreen-to-empty-workspace@aiono.dev

# 6. Install LocalSend v1.18.2 Native .deb
curl -fsSL --retry 4 -o /tmp/localsend.deb \
    "https://github.com/localsend/localsend/releases/download/v1.18.2/LocalSend-1.18.2-linux-x86-64.deb"
dpkg -i /tmp/localsend.deb
rm -f /tmp/localsend.deb
ln -sfn /opt/localsend_app/localsend_app /usr/bin/localsend

# 7. If Building PRO Edition: Preload Full Developer, Creative Design, Office & Gaming Suite (100% Free!)
if [[ "${KIYAN_EDITION}" == "pro" ]]; then
    echo ":: [PRO EDITION] Installing Complete Developer, Designer, Office & Gaming Suite..."
    apt-get install -y --no-install-recommends \
        build-essential gcc g++ gdb make cmake ninja-build pkg-config \
        python3 python3-pip python3-venv nodejs npm \
        jq ripgrep fd-find btop htop tmux openssh-client sqlite3 \
        gimp inkscape krita kdenlive audacity \
        libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
        gamemode mangohud wine64 winetricks lutris

    # Install VSCodium (100% Open-Source VS Code IDE) in Pro Edition
    CODIUM_URL=$(python3 - << 'PY'
import json, urllib.request
rel = json.loads(urllib.request.urlopen(urllib.request.Request(
    "https://api.github.com/repos/VSCodium/vscodium/releases/latest",
    headers={"User-Agent": "kiyan-ci"}
), timeout=15).read().decode())
for a in rel.get("assets", []):
    if a["name"].endswith("_amd64.deb") and a["name"].startswith("codium_"):
        print(a["browser_download_url"])
        break
PY
)
    if [[ -n "${CODIUM_URL}" ]]; then
        curl -fsSL --retry 4 -o /tmp/codium.deb "${CODIUM_URL}"
        apt-get install -y --no-install-recommends /tmp/codium.deb
        rm -f /tmp/codium.deb
    fi
fi

# Verify mandatory binaries exist
test -x /usr/bin/gnome-shell
test -x /usr/bin/gnome-control-center
test -x /usr/bin/zorin-appearance
test -x /usr/bin/firefox
test -x /usr/bin/calamares
test -x /usr/bin/localsend_app

# Clean temporary build-only ForceIPv4 rule & restore clean /etc/hosts
rm -f /etc/apt/apt.conf.d/99-kiyan-resilient-net
if [[ -f /etc/hosts.kiyan_clean ]]; then
    mv -f /etc/hosts.kiyan_clean /etc/hosts
fi
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF
fi

# ------------------------------------------------------------------------------
# 2. Unlock Zorin Appearance Pro Layouts + Rebrand to "Kiyan Appearance" + Boot Logo Tool
# ------------------------------------------------------------------------------
log_step "Unlocking Free macOS Sequoia & Windows 11 Layouts + Kiyan Branding & Wallpaper"

mkdir -p "${TARGET_ROOTFS}/usr/share/backgrounds/kiyan" \
         "${TARGET_ROOTFS}/usr/share/pixmaps" \
         "${TARGET_ROOTFS}/usr/share/applications" \
         "${TARGET_ROOTFS}/usr/share/glib-2.0/schemas" \
         "${TARGET_ROOTFS}/usr/share/plymouth/themes/kiyan" \
         "${TARGET_ROOTFS}/usr/share/doc/zorin-appearance-layouts-shell-premium"

if [[ -f "${DESKTOP_DIR}/branding/kiyan-icon.png" ]]; then
    run_cmd cp -f "${DESKTOP_DIR}/branding/kiyan-icon.png" "${TARGET_ROOTFS}/usr/share/pixmaps/kiyan-icon.png"
    run_cmd cp -f "${DESKTOP_DIR}/branding/kiyan-icon.png" "${TARGET_ROOTFS}/usr/share/plymouth/kiyan-logo.png"
fi

if [[ -f "${DESKTOP_DIR}/wallpapers/KiyanCrystal4K/contents/images/3840x2160.jpg" ]]; then
    run_cmd cp -f "${DESKTOP_DIR}/wallpapers/KiyanCrystal4K/contents/images/3840x2160.jpg" \
        "${TARGET_ROOTFS}/usr/share/backgrounds/kiyan/KiyanCrystal4K.jpg"
    # Also replace Zorin's fallback wallpaper symlinks so 4K Kiyan Crystal is always shown
    run_cmd cp -f "${DESKTOP_DIR}/wallpapers/KiyanCrystal4K/contents/images/3840x2160.jpg" \
        "${TARGET_ROOTFS}/usr/share/backgrounds/Zorin.jpg"
    run_cmd cp -f "${DESKTOP_DIR}/wallpapers/KiyanCrystal4K/contents/images/3840x2160.jpg" \
        "${TARGET_ROOTFS}/usr/share/backgrounds/Zorin-Dark.jpg"
fi

if [[ -d "${DESKTOP_DIR}/plymouth/kiyan" ]]; then
    run_cmd cp -r "${DESKTOP_DIR}/plymouth/kiyan"/* "${TARGET_ROOTFS}/usr/share/plymouth/themes/kiyan/"
fi

# Set Zorin GNOME Shell mode base resource to ZorinBlue-Dark and include Kiyan extensions natively
if [[ -f "${TARGET_ROOTFS}/usr/share/gnome-shell/modes/zorin.json" ]]; then
    cat << 'ZJSON_EOF' > "${TARGET_ROOTFS}/usr/share/gnome-shell/modes/zorin.json"
{
    "parentMode": "user",
    "stylesheetName": "gnome-shell.css",
    "themeResourceName": "theme/ZorinBlue-Dark/gnome-shell-theme.gresource",
    "enabledExtensions": [
        "drive-menu@gnome-shell-extensions.gcampax.github.com",
        "user-theme@gnome-shell-extensions.gcampax.github.com",
        "zorin-appindicator@zorinos.com",
        "zorin-printers@zorinos.com",
        "blur-my-shell@aunetx",
        "fullscreen-to-empty-workspace@aiono.dev"
    ]
}
ZJSON_EOF
fi

# Inject Unlocked macOS Sequoia & Windows 11 Centered Layouts directly into Zorin Appearance!
if [[ -d "${DESKTOP_DIR}/zorin-pro-layouts" && -d "${TARGET_ROOTFS}/usr/lib/python3/dist-packages/zorin_appearance/Layouts" ]]; then
    run_cmd cp -f "${DESKTOP_DIR}/zorin-pro-layouts"/*.py \
        "${TARGET_ROOTFS}/usr/lib/python3/dist-packages/zorin_appearance/Layouts/"
fi

# Marker directory suppresses the "Upgrade to Zorin OS Pro" paid nag banner in Zorin Appearance!
echo "Unlocked free in Kiyan OS v4" > "${TARGET_ROOTFS}/usr/share/doc/zorin-appearance-layouts-shell-premium/README"

# Rebrand Window Title of Zorin Appearance -> "Kiyan Appearance"
if [[ -f "${TARGET_ROOTFS}/usr/lib/python3/dist-packages/zorin_appearance/__main__.py" ]]; then
    sed -i "s/_('Zorin Appearance')/'Kiyan Appearance'/g" \
        "${TARGET_ROOTFS}/usr/lib/python3/dist-packages/zorin_appearance/__main__.py"
fi
if [[ -f "${TARGET_ROOTFS}/usr/share/applications/zorin-appearance.desktop" ]]; then
    sed -i -e 's/^Name=.*/Name=Kiyan Appearance/' \
           -e 's/^Name\[.*\]=/#&/' \
           "${TARGET_ROOTFS}/usr/share/applications/zorin-appearance.desktop"
fi

# Replace Zorin Start Menu Icon with Kiyan Logo inside Zorin Menu / Taskbar if SVG exists
for svg_logo in \
    "${TARGET_ROOTFS}/usr/share/gnome-shell/extensions/zorin-menu@zorinos.com/zorin-icon-symbolic.svg" \
    "${TARGET_ROOTFS}/usr/share/icons/hicolor/scalable/apps/zorin-os-logo.svg"; do
    if [[ -f "${svg_logo}" ]]; then
        cp -f "${svg_logo}" "${svg_logo}.bak"
    fi
done

# Create One-Click GUI Boot Logo Changer ("Kiyan Boot Logo Changer") so user can swap boot logo anytime!
cat << 'EOF' > "${TARGET_ROOTFS}/usr/bin/kiyan-boot-logo"
#!/usr/bin/env bash
set -euo pipefail
NEW_LOGO=$(zenity --file-selection --title="Select New Boot Logo Image (PNG/JPG)" \
    --file-filter="Images | *.png *.jpg *.jpeg" || true)
if [[ -z "${NEW_LOGO}" ]]; then
    exit 0
fi
pkexec bash -c "
    python3 -c '
from PIL import Image
im = Image.open(\"${NEW_LOGO}\").convert(\"RGBA\")
im.thumbnail((360, 360))
im.save(\"/usr/share/plymouth/themes/kiyan/logo.png\", \"PNG\")
' 2>/dev/null || cp -f \"${NEW_LOGO}\" /usr/share/plymouth/themes/kiyan/logo.png
    update-initramfs -u
" && zenity --info --title="Kiyan Boot Logo" --text="Boot logo updated successfully! Your new logo will appear on the next reboot."
EOF
chmod 0755 "${TARGET_ROOTFS}/usr/bin/kiyan-boot-logo"

cat << 'EOF' > "${TARGET_ROOTFS}/usr/share/applications/kiyan-boot-logo.desktop"
[Desktop Entry]
Type=Application
Name=Kiyan Boot Logo Changer
Comment=Change the Kiyan OS startup boot logo with one click
Exec=/usr/bin/kiyan-boot-logo
Icon=/usr/share/pixmaps/kiyan-icon.png
Terminal=false
Categories=Settings;System;
EOF

# ------------------------------------------------------------------------------
# 3. Compile Authoritative GSettings Override (macOS Sequoia Default + Frosted Bar/Dock Only!)
# ------------------------------------------------------------------------------
log_step "Configuring Authoritative GSettings Defaults (macOS Sequoia + Frosted Bar/Dock + 1:1 Trackpad)"

cat << 'EOF' > "${TARGET_ROOTFS}/usr/share/glib-2.0/schemas/95_kiyan-os-defaults.gschema.override"
[org.gnome.shell]
enabled-extensions = ['drive-menu@gnome-shell-extensions.gcampax.github.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'zorin-appindicator@zorinos.com', 'zorin-printers@zorinos.com', 'zorin-desktop-icons@zorinos.com', 'zorin-tiling-shell@zorinos.com', 'zorin-dash@zorinos.com', 'zorin-hide-activities-move-clock@zorinos.com', 'zorin-magic-lamp-effect@zorinos.com', 'blur-my-shell@aunetx', 'fullscreen-to-empty-workspace@aiono.dev']
favorite-apps = ['org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.Terminal.desktop', 'zorin-appearance.desktop', 'localsend_app.desktop', 'org.gnome.Settings.desktop']
welcome-dialog-last-shown-version = '99.0'
disable-user-extensions = false

[org.gnome.shell:zorin]
enabled-extensions = ['drive-menu@gnome-shell-extensions.gcampax.github.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'zorin-appindicator@zorinos.com', 'zorin-printers@zorinos.com', 'zorin-desktop-icons@zorinos.com', 'zorin-tiling-shell@zorinos.com', 'zorin-dash@zorinos.com', 'zorin-hide-activities-move-clock@zorinos.com', 'zorin-magic-lamp-effect@zorinos.com', 'blur-my-shell@aunetx', 'fullscreen-to-empty-workspace@aiono.dev']
favorite-apps = ['org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.Terminal.desktop', 'zorin-appearance.desktop', 'localsend_app.desktop', 'org.gnome.Settings.desktop']

[org.gnome.desktop.interface]
color-scheme = 'prefer-dark'
gtk-theme = 'ZorinBlue-Dark'
icon-theme = 'WhiteSur-dark'
cursor-theme = 'Adwaita'
font-name = 'Inter 10'
monospace-font-name = 'JetBrains Mono 10'
enable-hot-corners = true
show-battery-percentage = true

[org.gnome.desktop.interface:zorin]
color-scheme = 'prefer-dark'
gtk-theme = 'ZorinBlue-Dark'
icon-theme = 'WhiteSur-dark'
font-name = 'Inter 10'
monospace-font-name = 'JetBrains Mono 10'
enable-hot-corners = true
show-battery-percentage = true
zorin-display-overview-on-startup = false

[org.gnome.shell.extensions.user-theme]
name = 'ZorinBlue-Dark'

[org.gnome.shell.extensions.user-theme:zorin]
name = 'ZorinBlue-Dark'

[org.gnome.desktop.wm.preferences]
button-layout = 'close,minimize,maximize:appmenu'
titlebar-font = 'Inter Bold 10'

[org.gnome.desktop.wm.preferences:zorin]
button-layout = 'close,minimize,maximize:appmenu'
titlebar-font = 'Inter Bold 10'

[org.gnome.desktop.background]
show-desktop-icons = true
picture-uri = 'file:///usr/share/backgrounds/kiyan/KiyanCrystal4K.jpg'
picture-uri-dark = 'file:///usr/share/backgrounds/kiyan/KiyanCrystal4K.jpg'
picture-options = 'zoom'

[org.gnome.desktop.screensaver]
picture-uri = 'file:///usr/share/backgrounds/kiyan/KiyanCrystal4K.jpg'

[org.gnome.login-screen]
logo = '/usr/share/pixmaps/kiyan-icon.png'

[org.gnome.desktop.peripherals.touchpad]
tap-to-click = true
natural-scroll = true
two-finger-scrolling-enabled = true
click-method = 'fingers'
speed = 0.15

[org.gnome.desktop.peripherals.touchpad:zorin]
tap-to-click = true
natural-scroll = true
two-finger-scrolling-enabled = true
click-method = 'fingers'
speed = 0.15

[org.gnome.desktop.input-sources]
sources = [('xkb', 'us'), ('xkb', 'ir')]
xkb-options = ['grp:alt_shift_toggle']

[org.gnome.mutter]
dynamic-workspaces = true
edge-tiling = true
center-new-windows = true

[org.gnome.shell.extensions.zorin-dash]
dock-position = 'BOTTOM'
extend-height = false
always-center-icons = true
dock-fixed = true
intellihide = true
autohide-in-fullscreen = true
dash-max-icon-size = 48
show-show-apps-button = true
show-apps-at-top = true
show-trash = true
transparency-mode = 'FIXED'
background-opacity = 0.45
click-action = 'minimize-or-previews'

[org.gnome.shell.extensions.blur-my-shell.panel]
blur = true
static-blur = true
override-background = true

[org.gnome.shell.extensions.blur-my-shell.dash-to-dock]
blur = true
static-blur = true
override-background = true
style-dash-to-dock = 0

[org.gnome.shell.extensions.blur-my-shell.applications]
blur = false

[com.zorin.desktop.appearance]
show-more-layouts-message = false
EOF

if [[ "${DRY_RUN}" != "1" ]]; then
    chroot "${TARGET_ROOTFS}" glib-compile-schemas /usr/share/glib-2.0/schemas
fi

# First-Login Display Color Range Fix (Forces Full RGB 0-255 on AMD/Intel Laptop Panels so screen is NEVER matte!)
mkdir -p "${TARGET_ROOTFS}/etc/skel/.config/autostart" "${TARGET_ROOTFS}/etc/skel/.config"
cat << 'EOF' > "${TARGET_ROOTFS}/usr/bin/kiyan-session-init"
#!/usr/bin/env bash
set -euo pipefail
# 1. Disable AMD Vari-Bright panel power savings (prevents washed-out contrast)
for f in /sys/class/drm/card*-eDP-*/amdgpu/panel_power_savings; do
    if [[ -w "$f" ]]; then echo 0 > "$f" 2>/dev/null || true; fi
done
# 2. Allow Desktop .desktop icons (like Install Kiyan OS) to launch cleanly without untrusted block
for df in "$HOME"/Desktop/*.desktop; do
    if [[ -f "$df" ]]; then
        chmod +x "$df" 2>/dev/null || true
        gio set "$df" metadata::trusted true 2>/dev/null || true
    fi
done
mkdir -p "$HOME/.config/kiyan"
touch "$HOME/.config/kiyan/.initialized_v4"
EOF
chmod 0755 "${TARGET_ROOTFS}/usr/bin/kiyan-session-init"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/autostart/kiyan-session-init.desktop"
[Desktop Entry]
Type=Application
Name=Kiyan Session Hardware Optimizer
Exec=/usr/bin/kiyan-session-init
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Set Native Mozilla Firefox as Default Browser Across All MIME Types
cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/.config/mimeapps.list"
[Default Applications]
text/html=firefox.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
x-scheme-handler/about=firefox.desktop
x-scheme-handler/unknown=firefox.desktop
application/xhtml+xml=firefox.desktop
EOF

# System-wide udev rule to force Broadcast RGB = Full (0-255) & AMD ABM=0 on boot!
mkdir -p "${TARGET_ROOTFS}/etc/udev/rules.d" "${TARGET_ROOTFS}/etc/profile.d"
cat << 'EOF' > "${TARGET_ROOTFS}/etc/udev/rules.d/99-kiyan-display-crisp.rules"
SUBSYSTEM=="drm", KERNEL=="card*", ATTR{amdgpu/panel_power_savings}="0"
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/profile.d/kiyan-wayland.sh"
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM="wayland;xcb"
EOF
chmod 0644 "${TARGET_ROOTFS}/etc/profile.d/kiyan-wayland.sh"

# ------------------------------------------------------------------------------
# 4. GDM3 Wayland Live Autologin & Casper Protection
# ------------------------------------------------------------------------------
log_step "Configuring GDM3 Wayland Live Autologin & Casper Hook"

mkdir -p "${TARGET_ROOTFS}/etc/gdm3" \
         "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/gdm3/custom.conf"
[daemon]
WaylandEnable=true
AutomaticLoginEnable=true
AutomaticLogin=kian
DefaultSession=zorin-wayland.desktop

[security]

[xdmcp]

[chooser]

[debug]
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom/99kian_autologin"
#!/bin/sh
PREREQ=""
DESCRIPTION="Enforcing Kiyan OS v4 GDM3 Zorin Wayland Live Autologin..."
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
. /scripts/casper-functions
log_begin_msg "$DESCRIPTION"

mkdir -p /root/etc/gdm3
cat > /root/etc/gdm3/custom.conf << 'GDM_EOF'
[daemon]
WaylandEnable=true
AutomaticLoginEnable=true
AutomaticLogin=kian
DefaultSession=zorin-wayland.desktop

[security]

[xdmcp]

[chooser]

[debug]
GDM_EOF

mkdir -p /root/var/lib/AccountsService/users
cat > /root/var/lib/AccountsService/users/kian << 'ACC_EOF'
[User]
Session=zorin-wayland
SystemAccount=false
ACC_EOF

if [ -d /root/home/kian ]; then
    cp -rn /root/etc/skel/. /root/home/kian/ 2>/dev/null || true
    chroot /root chown -R kian:kian /home/kian 2>/dev/null || true
fi

log_end_msg
exit 0
EOF
chmod 0755 "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/casper-bottom/99kian_autologin"

# ------------------------------------------------------------------------------
# 5. Calamares Graphical Installer Configuration & Wayland Root Wrapper
# ------------------------------------------------------------------------------
log_step "Deploying Calamares Graphical Installer & Desktop Double-Click Wrapper"

mkdir -p "${TARGET_ROOTFS}/etc/calamares/modules" \
         "${TARGET_ROOTFS}/etc/calamares/branding/kian" \
         "${TARGET_ROOTFS}/usr/share/calamares/hooks" \
         "${TARGET_ROOTFS}/usr/lib/calamares/hooks" \
         "${TARGET_ROOTFS}/usr/share/polkit-1/actions" \
         "${TARGET_ROOTFS}/etc/skel/Desktop" \
         "${TARGET_ROOTFS}/home/kian/Desktop"

if [[ -f "${INSTALLER_DIR}/calamares/settings.conf" ]]; then
    run_cmd cp "${INSTALLER_DIR}/calamares/settings.conf" "${TARGET_ROOTFS}/etc/calamares/settings.conf"
fi
if [[ -d "${INSTALLER_DIR}/calamares/modules" ]]; then
    run_cmd cp -r "${INSTALLER_DIR}/calamares/modules"/* "${TARGET_ROOTFS}/etc/calamares/modules/"
fi
if [[ -d "${INSTALLER_DIR}/calamares/branding/kian" ]]; then
    run_cmd cp -r "${INSTALLER_DIR}/calamares/branding/kian"/* "${TARGET_ROOTFS}/etc/calamares/branding/kian/"
fi
if [[ -f "${DESKTOP_DIR}/branding/kiyan-icon.png" ]]; then
    run_cmd cp -f "${DESKTOP_DIR}/branding/kiyan-icon.png" "${TARGET_ROOTFS}/etc/calamares/branding/kian/kian-logo.png"
fi
if [[ -f "${DESKTOP_DIR}/branding/kiyan-welcome.png" ]]; then
    run_cmd cp -f "${DESKTOP_DIR}/branding/kiyan-welcome.png" "${TARGET_ROOTFS}/etc/calamares/branding/kian/welcome.png"
fi
if [[ -d "${INSTALLER_DIR}/calamares/hooks" ]]; then
    run_cmd cp "${INSTALLER_DIR}/calamares/hooks"/*.sh "${TARGET_ROOTFS}/usr/share/calamares/hooks/"
    run_cmd cp "${INSTALLER_DIR}/calamares/hooks"/*.sh "${TARGET_ROOTFS}/usr/lib/calamares/hooks/"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/share/calamares/hooks"/*.sh "${TARGET_ROOTFS}/usr/lib/calamares/hooks"/*.sh
fi

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
        XDG_CURRENT_DESKTOP="GNOME" \
        LANG="${LANG:-en_US.UTF-8}" \
        /usr/bin/kian-install-os "$@"
else
    exec pkexec env \
        WAYLAND_DISPLAY="${WL_ABS}" \
        DISPLAY="${X_DISP:-:0}" \
        QT_QPA_PLATFORM="wayland;xcb" \
        XDG_CURRENT_DESKTOP="GNOME" \
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
  <vendor>Kiyan OS</vendor>
  <action id="org.kian.install.pkexec.run">
    <description>Install Kiyan OS v4</description>
    <message>Authentication is required to install Kiyan OS v4</message>
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

cat << EOF > "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Install Kiyan OS v4 (${EDITION^^})
GenericName=System Installer
Comment=Install Kiyan OS v4 permanently to disk
Exec=/usr/bin/kian-install-os
Icon=/usr/share/pixmaps/kiyan-icon.png
Terminal=false
StartupNotify=true
Categories=Qt;System;
EOF
chmod 0755 "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop"
cp -f "${TARGET_ROOTFS}/etc/skel/Desktop/calamares.desktop" "${TARGET_ROOTFS}/usr/share/applications/calamares.desktop"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/skel/Desktop/zorin-appearance.desktop"
[Desktop Entry]
Type=Application
Version=1.0
Name=Kiyan Appearance (macOS & Win11)
Comment=Switch between macOS Sequoia, Windows 11, and Zorin Desktop layouts
Exec=/usr/bin/zorin-appearance
Icon=zorin-appearance
Terminal=false
StartupNotify=true
Categories=Settings;
EOF
chmod 0755 "${TARGET_ROOTFS}/etc/skel/Desktop/zorin-appearance.desktop"

if [[ -d "${TARGET_ROOTFS}/home/kian" ]]; then
    cp -rf "${TARGET_ROOTFS}/etc/skel/." "${TARGET_ROOTFS}/home/kian/"
    if [[ "${DRY_RUN}" != "1" ]]; then
        chroot "${TARGET_ROOTFS}" chown -R kian:kian /home/kian
    fi
fi

# ------------------------------------------------------------------------------
# 6. Atomic Btrfs Rollback, Dual-Kernel Watchdog (7.3 Liquorix + 7.0 HWE) & Branding
# ------------------------------------------------------------------------------
log_step "Installing Atomic Btrfs Hooks, Dual-Kernel Watchdog & Kiyan OS v4 Branding"

mkdir -p "${TARGET_ROOTFS}/usr/lib/kian" \
         "${TARGET_ROOTFS}/etc/apt/apt.conf.d" \
         "${TARGET_ROOTFS}/etc/grub.d" \
         "${TARGET_ROOTFS}/etc/default" \
         "${TARGET_ROOTFS}/etc/systemd/system" \
         "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom"

if [[ -f "${SCRIPTS_DIR}/btrfs-apt-hook" ]]; then
    run_cmd cp "${SCRIPTS_DIR}/btrfs-apt-hook" "${TARGET_ROOTFS}/usr/lib/kian/btrfs-apt-hook"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/lib/kian/btrfs-apt-hook"
    cat << 'EOF' > "${TARGET_ROOTFS}/etc/apt/apt.conf.d/80-kian-btrfs-snapshot"
DPkg::Pre-Invoke  { "/usr/lib/kian/btrfs-apt-hook pre"; };
DPkg::Post-Invoke { "/usr/lib/kian/btrfs-apt-hook post"; };
EOF
fi

if [[ -f "${SCRIPTS_DIR}/kian-rollback" ]]; then
    run_cmd cp "${SCRIPTS_DIR}/kian-rollback" "${TARGET_ROOTFS}/usr/bin/kian-rollback"
    run_cmd chmod +x "${TARGET_ROOTFS}/usr/bin/kian-rollback"
fi

if [[ -f "${SCRIPTS_DIR}/41_kian_snapshots" ]]; then
    run_cmd cp "${SCRIPTS_DIR}/41_kian_snapshots" "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
    run_cmd chmod +x "${TARGET_ROOTFS}/etc/grub.d/41_kian_snapshots"
fi

cat << 'EOF' > "${TARGET_ROOTFS}/etc/default/grub"
GRUB_DEFAULT="kian_primary"
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=2
GRUB_DISTRIBUTOR="Kiyan OS v4"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 udev.log_priority=0 vt.global_cursor_default=0 amdgpu.abmlevel=0 preempt=full split_lock_mitigate=0 nouveau.config=NvGspRm=1 panic=10"
GRUB_CMDLINE_LINUX=""
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/grub.d/01_kian_watchdog"
#!/bin/sh
set -e
cat << 'GRUB_WATCHDOG'
if [ -s $prefix/grubenv ]; then
    load_env
fi
if [ -z "${bootlimit}" ]; then
    set bootlimit=3
fi
if [ "${boot_once_snapshot}" = "1" ]; then
    set boot_once_snapshot=0
    save_env boot_once_snapshot
elif [ -n "${bootcount}" ] && [ "${bootcount}" -ge "${bootlimit}" ]; then
    set default="kian_fallback_generic"
else
    if [ "${bootcount}" = "0" ] || [ -z "${bootcount}" ]; then
        set bootcount=1
    elif [ "${bootcount}" = "1" ]; then
        set bootcount=2
    elif [ "${bootcount}" = "2" ]; then
        set bootcount=3
    else
        set bootcount=1
    fi
    save_env bootcount
    set default="kian_primary"
fi
GRUB_WATCHDOG
EOF
chmod +x "${TARGET_ROOTFS}/etc/grub.d/01_kian_watchdog"

cat << 'EOF' > "${TARGET_ROOTFS}/etc/grub.d/09_kian_kernels"
#!/bin/sh
set -e
prefix="/usr"
exec_prefix="/usr"
datarootdir="/usr/share"
. "$pkgdatadir/grub-mkconfig_lib"

PRIMARY_KVER=$(ls -1 /boot/vmlinuz-*liquorix* 2>/dev/null | sed 's|^/boot/vmlinuz-||' | sort -V | tail -n 1 || true)
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
menuentry '${entry_title}' --class kiyan-os --class gnu-linux --class gnu --class os --id '${entry_id}' {
	load_video
	gfxmode \$linux_gfx_mode
	insmod gzio
${BOOT_PREP}
	linux ${vmlinuz_rel} root=${LINUX_ROOT_DEVICE} ro ${ROOT_SUBVOL_FLAG} ${GRUB_CMDLINE_LINUX} ${extra_args}
	initrd ${initrd_rel}
}
ENTRY_EOF
}

if [ -n "${PRIMARY_KVER}" ]; then
    emit_kian_entry "Kiyan OS v4 (Superkernel ${PRIMARY_KVER})" "kian_primary" "${PRIMARY_KVER}" "${GRUB_CMDLINE_LINUX_DEFAULT}"
fi
if [ -n "${FALLBACK_KVER}" ]; then
    emit_kian_entry "Kiyan OS v4 (Safe HWE Recovery ${FALLBACK_KVER})" "kian_fallback_generic" "${FALLBACK_KVER}" "quiet splash loglevel=0 vt.global_cursor_default=0"
fi
EOF
chmod +x "${TARGET_ROOTFS}/etc/grub.d/09_kian_kernels"

if [[ -f "${SCRIPTS_DIR}/kian-boot-success.service" ]]; then
    run_cmd cp "${SCRIPTS_DIR}/kian-boot-success.service" "${TARGET_ROOTFS}/etc/systemd/system/kian-boot-success.service"
    mkdir -p "${TARGET_ROOTFS}/etc/systemd/system/graphical.target.wants"
    ln -sf "/etc/systemd/system/kian-boot-success.service" "${TARGET_ROOTFS}/etc/systemd/system/graphical.target.wants/kian-boot-success.service"
fi

cat << 'EOF' > "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom/kian_overlayfs"
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0;; esac
ENABLE_OVERLAY=0
for x in $(cat /proc/cmdline); do
    case $x in
        kian_snapshot_ro=1) ENABLE_OVERLAY=1 ;;
    esac
done
[ "$ENABLE_OVERLAY" -eq 1 ] || exit 0
. /scripts/functions
log_begin_msg "Mounting Kiyan OS Ephemeral Snapshot OverlayFS..."
mkdir -p /run/overlay_tmpfs /run/overlay_newroot
mount -t tmpfs -o mode=0755,size=50% tmpfs_root /run/overlay_tmpfs
mkdir -p /run/overlay_tmpfs/upper /run/overlay_tmpfs/work
mount -t overlay overlay -o lowerdir=${rootmnt},upperdir=/run/overlay_tmpfs/upper,workdir=/run/overlay_tmpfs/work /run/overlay_newroot
mkdir -p /run/overlay_newroot/mnt/.ro_snapshot
mount --move ${rootmnt} /run/overlay_newroot/mnt/.ro_snapshot
mount --move /run/overlay_newroot ${rootmnt}
log_end_msg
exit 0
EOF
chmod +x "${TARGET_ROOTFS}/etc/initramfs-tools/scripts/init-bottom/kian_overlayfs"

# Overwrite /etc/os-release AFTER Zorin packages so Settings -> About displays Kiyan OS v4!
cat << EOF > "${TARGET_ROOTFS}/etc/os-release"
NAME="Kiyan OS"
VERSION="4.0 (${EDITION^^} Edition)"
ID=kiyan-os
ID_LIKE="ubuntu debian"
PRETTY_NAME="Kiyan OS v4 ${EDITION^^}"
VERSION_ID="4.0"
HOME_URL="https://github.com/manmojt/kiyan-os"
SUPPORT_URL="https://github.com/manmojt/kiyan-os/issues"
BUG_REPORT_URL="https://github.com/manmojt/kiyan-os/issues"
UBUNTU_CODENAME=noble
LOGO=kiyan-icon
EOF

cat << EOF > "${TARGET_ROOTFS}/etc/lsb-release"
DISTRIB_ID=KiyanOS
DISTRIB_RELEASE=4.0
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="Kiyan OS v4 ${EDITION^^}"
EOF

echo "Kiyan OS v4 ${EDITION^^} \n \l" > "${TARGET_ROOTFS}/etc/issue"
echo "Kiyan OS v4 ${EDITION^^} \n \l" > "${TARGET_ROOTFS}/etc/issue.net"
echo "kian-os" > "${TARGET_ROOTFS}/etc/hostname"

if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Activating Kiyan Plymouth Boot Splash & Regenerating Initramfs (All Kernels)..."
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive CASPER_GENERATE_UUID=1 bash -euo pipefail << 'CHROOT_INITRD_EOF'
if [[ -f /usr/share/plymouth/themes/kiyan/kiyan.plymouth ]]; then
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
        /usr/share/plymouth/themes/kiyan/kiyan.plymouth 600
    update-alternatives --set default.plymouth /usr/share/plymouth/themes/kiyan/kiyan.plymouth
    mkdir -p /etc/plymouth
    printf "[Daemon]\nTheme=kiyan\nShowDelay=0\nDeviceTimeout=8\n" > /etc/plymouth/plymouthd.conf
fi
update-alternatives --set x-www-browser /usr/bin/firefox || true
update-alternatives --set gnome-www-browser /usr/bin/firefox || true
for kver in $(ls -1 /lib/modules | sort -V); do
    echo ":: Building initramfs for kernel ${kver}..."
    update-initramfs -c -k "${kver}" || update-initramfs -u -k "${kver}"
    test -s "/boot/initrd.img-${kver}"
done
KVER_PRI=$(ls -1 /lib/modules | grep -E "liquorix-amd64$" | sort -V | tail -n 1)
test -n "${KVER_PRI}"
ln -sfn "vmlinuz-${KVER_PRI}" /boot/vmlinuz
ln -sfn "initrd.img-${KVER_PRI}" /boot/initrd.img
CHROOT_INITRD_EOF
    unmount_virtual_fs "${TARGET_ROOTFS}"
fi

log_success "Phase 3: Kiyan OS v4 (${EDITION^^}) Zorin 18 + GNOME 46 Desktop customization complete!"
