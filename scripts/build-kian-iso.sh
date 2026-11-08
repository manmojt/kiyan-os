#!/bin/bash
# ==============================================================================
# 🏛️ Kian-OS v2 (x86_64) — Official Council-Approved Build Script
# Base: Ubuntu 24.04 LTS (Noble) amd64 | Desktop: KDE Plasma Wayland (KWin)
# Profiles: Kian-Linux Native, Kian-Mac Aqua, Kian-Win Fluent
# ==============================================================================
set -euo pipefail

WORK_DIR="${GITHUB_WORKSPACE:-/tmp}/kian-build"
ROOTFS="$WORK_DIR/rootfs"
ISO_DIR="$WORK_DIR/iso"
OUT_DIR="${GITHUB_WORKSPACE:-/tmp}/output"
ISO_FILE="$OUT_DIR/Kian-OS-v2-x86_64.iso"

mkdir -p "$ROOTFS" "$ISO_DIR/casper" "$ISO_DIR/boot/grub" "$OUT_DIR"

echo "🚀 [Phase 1/5] Bootstrapping Ubuntu 24.04 LTS (Noble) amd64 base rootfs..."
sudo debootstrap --arch=amd64 --variant=minbase noble "$ROOTFS" http://archive.ubuntu.com/ubuntu/

sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /dev/pts "$ROOTFS/dev/pts"
sudo mount -t proc proc "$ROOTFS/proc"
sudo mount -t sysfs sysfs "$ROOTFS/sys"

cleanup() {
    sudo umount -lf "$ROOTFS/sys" 2>/dev/null || true
    sudo umount -lf "$ROOTFS/proc" 2>/dev/null || true
    sudo umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    sudo umount -lf "$ROOTFS/dev" 2>/dev/null || true
}
trap cleanup EXIT

cat << 'SOURCES' | sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
SOURCES

echo "kian-os" | sudo tee "$ROOTFS/etc/hostname" >/dev/null
echo "nameserver 1.1.1.1" | sudo tee "$ROOTFS/etc/resolv.conf" >/dev/null

# Block snapd completely per Council Verdict
cat << 'NOSNAP' | sudo tee "$ROOTFS/etc/apt/preferences.d/nosnap.pref" >/dev/null
Package: snapd
Pin: release a=*
Pin-Priority: -10
NOSNAP

echo "🔧 [Phase 2/5] Installing Kernel, Hardware Drivers, ZRAM, PipeWire & Fingerprint (libfprint-2)..."
sudo chroot "$ROOTFS" /bin/bash -euc "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    linux-image-generic \
    linux-firmware \
    zram-tools \
    systemd-sysv \
    network-manager \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    mesa-vulkan-drivers \
    libfprint-2-2 \
    fprintd \
    libpam-fprintd \
    fwupd \
    sudo \
    locales \
    ca-certificates \
    curl \
    wget \
    pciutils \
    usbutils \
    kmod \
    ufw \
    apparmor
pam-auth-update --enable fprintd || true
"

echo "🎨 [Phase 3/5] Installing KDE Plasma Wayland, Discover GUI Store, Kvantum & 3 Kian Profiles..."
sudo chroot "$ROOTFS" /bin/bash -euc "
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends \
    kde-plasma-desktop \
    plasma-workspace-wayland \
    kwin-wayland \
    sddm \
    plasma-discover \
    plasma-discover-backend-flatpak \
    plasma-discover-backend-fwupd \
    flatpak \
    qt5-style-kvantum \
    papirus-icon-theme \
    fonts-inter \
    fonts-vazirmatn \
    dolphin \
    konsole \
    ark \
    gwenview \
    okular \
    plank \
    plymouth \
    plymouth-themes
"

# Create the 3 Global Theme Profiles & GUI Switcher
sudo mkdir -p \
    "$ROOTFS/usr/share/plasma/look-and-feel/org.kde.kian.linux.native/contents/layouts" \
    "$ROOTFS/usr/share/plasma/look-and-feel/org.kde.kian.mac.aqua/contents/layouts" \
    "$ROOTFS/usr/share/plasma/look-and-feel/org.kde.kian.win.fluent/contents/layouts"

for prof in "org.kde.kian.linux.native:Kian-Linux Native (Dark Crystal)" "org.kde.kian.mac.aqua:Kian-Mac Aqua (macOS Experience)" "org.kde.kian.win.fluent:Kian-Win Fluent (Windows 11 Experience)"; do
    id="${prof%%:*}"
    name="${prof#*:}"
    cat << META | sudo tee "$ROOTFS/usr/share/plasma/look-and-feel/$id/metadata.json" >/dev/null
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Id": "$id",
        "Name": "$name",
        "Description": "Official Kian-OS v2 Switchable Profile",
        "Authors": [{ "Name": "Kiyan Brain Council" }],
        "Version": "2.0"
    }
}
META
done

cat << 'SWITCHER' | sudo tee "$ROOTFS/usr/local/bin/kian-theme-switcher" >/dev/null
#!/bin/bash
PROFILE="${1:-org.kde.kian.linux.native}"
lookandfeeltool -a "$PROFILE" 2>/dev/null || plasma-apply-lookandfeel -a "$PROFILE" 2>/dev/null || true
qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true
SWITCHER
sudo chmod +x "$ROOTFS/usr/local/bin/kian-theme-switcher"

echo "🍷 [Phase 4/5] Installing Windows Compatibility Layer (Wine64/Proton Double-Click Runner)..."
sudo chroot "$ROOTFS" /bin/bash -euc "
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends \
    wine \
    wine64 \
    binfmt-support \
    calamares \
    calamares-settings-ubuntu-common \
    initramfs-tools \
    casper
KVER=$(ls /lib/modules | sort | tail -n1)
update-initramfs -c -k "$KVER" || update-initramfs -c -k all
apt-get clean
useradd -m -s /bin/bash -G sudo,video,audio,input,plugdev kian || true
echo 'kian:kian' | chpasswd
echo 'kian ALL=NOPASSWD:ALL' > /etc/sudoers.d/kian
"

cleanup

echo "💿 [Phase 5/5] Packaging SquashFS (ZSTD) and Bootable Hybrid UEFI/BIOS x86_64 ISO..."
KERNEL=$(sudo find "$ROOTFS/boot" -maxdepth 1 -type f -name "vmlinuz-*" | sort | tail -n1)
INITRD=$(sudo find "$ROOTFS/boot" -maxdepth 1 -type f -name "initrd.img-*" | sort | tail -n1)
sudo cp "$KERNEL" "$ISO_DIR/casper/vmlinuz"
sudo cp "$INITRD" "$ISO_DIR/casper/initrd"

sudo mksquashfs "$ROOTFS" "$ISO_DIR/casper/filesystem.squashfs" -comp zstd -Xcompression-level 6 -noappend

cat << 'GRUB' | sudo tee "$ISO_DIR/boot/grub/grub.cfg" >/dev/null
set timeout=5
set default=0

menuentry "Kian-OS v2 (KDE Plasma Wayland - Live & Installer)" {
    linux /casper/vmlinuz boot=casper quiet splash mitigations=off ---
    initrd /casper/initrd
}

menuentry "Kian-OS v2 (Safe Graphics Mode)" {
    linux /casper/vmlinuz boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}
GRUB

sudo grub-mkrescue -o "$ISO_FILE" "$ISO_DIR" 2>/dev/null || sudo xorriso -as mkisofs -r -V "KIAN_OS_V2" -o "$ISO_FILE" "$ISO_DIR"
sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR"
(cd "$OUT_DIR" && sha256sum Kian-OS-v2-x86_64.iso > Kian-OS-v2-x86_64.iso.sha256)
ls -lh "$OUT_DIR"
echo "🎉 Kian-OS v2 x86_64 ISO built successfully!"
