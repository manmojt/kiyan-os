#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Clean-Slate Rootfs Debootstrap (Phase 2)
# Path: build/02_bootstrap_rootfs.sh
# Description: Debootstraps Ubuntu 24.04 LTS (Noble Numbat) minbase rootfs,
#              configures apt repositories, locales, timezone, core packages,
#              Casper live identity ('kian'), early LUKS keyboard modules,
#              NTSync udev/autoload rules, sysctl performance tuning,
#              dual kernels (kian-v3 + stock generic), and GRUB watchdog block.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOTFS="${ROOTFS_DIR}"
MIRROR_URL="https://mirrors.edge.kernel.org/ubuntu/"
CLEAN_FIRST=0

show_usage() {
    local exit_code="${1:-0}"
    cat <<EOF
KIAN-OS v3 Rootfs Debootstrap Recipe (Phase 2)
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h          Display this help message
  --dry-run           Simulate steps without debootstrap or chroot execution
  --rootfs-dir <DIR>  Target rootfs directory (default: ${ROOTFS_DIR})
  --mirror <URL>      Ubuntu archive mirror URL (default: https://mirrors.edge.kernel.org/ubuntu/)
  --clean             Wipe target rootfs before bootstrapping

Examples:
  sudo ./02_bootstrap_rootfs.sh
  ./02_bootstrap_rootfs.sh --dry-run
  sudo ./02_bootstrap_rootfs.sh --clean --mirror https://mirrors.edge.kernel.org/ubuntu/
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
        --mirror)
            MIRROR_URL="$2"
            shift 2
            ;;
        --clean)
            CLEAN_FIRST=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage 1
            ;;
    esac
done

log_step "Phase 2: Clean-Slate Ubuntu 24.04 LTS Rootfs Debootstrap"

require_root
check_dependencies debootstrap

# ------------------------------------------------------------------------------
# 1. Clean and Prepare Rootfs Workspace
# ------------------------------------------------------------------------------
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

if [[ $CLEAN_FIRST -eq 1 && -d "${TARGET_ROOTFS}" ]]; then
    log_warn "Purging existing target rootfs directory: ${TARGET_ROOTFS}..."
    unmount_virtual_fs "${TARGET_ROOTFS}"
    run_cmd rm -rf "${TARGET_ROOTFS}"
fi

mkdir -p "${TARGET_ROOTFS}"

# ------------------------------------------------------------------------------
# 2. Debootstrap Ubuntu 24.04 LTS (Noble Numbat)
# ------------------------------------------------------------------------------
if [[ ! -f "${TARGET_ROOTFS}/bin/bash" ]]; then
    log_info "Bootstrapping Ubuntu 24.04 LTS (${DISTRO_CODENAME}) minbase into ${TARGET_ROOTFS}..."
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[DRY-RUN] Simulating debootstrap minbase noble..."
        mkdir -p "${TARGET_ROOTFS}"/{bin,dev,proc,sys,run,etc/apt,boot/grub,var/lib/dpkg,home/kian,usr/bin,tmp/kian_pkgs}
        touch "${TARGET_ROOTFS}/bin/bash" "${TARGET_ROOTFS}/bin/sh"
    else
        debootstrap --include=ca-certificates --arch="${DISTRO_ARCH}" --variant=minbase "${DISTRO_CODENAME}" "${TARGET_ROOTFS}" "${MIRROR_URL}"
    fi
else
    log_info "Existing base system found in ${TARGET_ROOTFS}; skipping debootstrap."
fi

# ------------------------------------------------------------------------------
# 3. Mount Virtual Filesystems
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Mounting virtual pseudo-filesystems (/dev, /proc, /sys, /run)..."
    mount --bind /dev "${TARGET_ROOTFS}/dev"
    mount --bind /dev/pts "${TARGET_ROOTFS}/dev/pts"
    mount -t proc proc "${TARGET_ROOTFS}/proc"
    mount -t sysfs sys "${TARGET_ROOTFS}/sys"
    mount --bind /run "${TARGET_ROOTFS}/run"
fi

# ------------------------------------------------------------------------------
# 4. Configure Networking, Repositories, Locale & Base Identity
# ------------------------------------------------------------------------------
log_step "Configuring Base Operating System Environment"

# Configure Hostname and Hosts
log_info "Setting hostname 'kian-os' and hosts mapping..."
echo "kian-os" > "${TARGET_ROOTFS}/etc/hostname"
cat << 'EOF' > "${TARGET_ROOTFS}/etc/hosts"
127.0.0.1   localhost
127.0.1.1   kian-os
::1         localhost ip6-localhost ip6-loopback
EOF

# Write clean deterministic DNS resolvers (never leak cloud runner search domains)
rm -f "${TARGET_ROOTFS}/etc/resolv.conf"
cat << 'EOF' > "${TARGET_ROOTFS}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
chmod 0644 "${TARGET_ROOTFS}/etc/resolv.conf"

# Configure APT Repositories (Noble LTS over HTTPS)
log_info "Writing Noble APT repositories (main, restricted, universe, multiverse)..."
cat << EOF > "${TARGET_ROOTFS}/etc/apt/sources.list"
deb ${MIRROR_URL} ${DISTRO_CODENAME} main restricted universe multiverse
deb ${MIRROR_URL} ${DISTRO_CODENAME}-updates main restricted universe multiverse
deb https://security.ubuntu.com/ubuntu/ ${DISTRO_CODENAME}-security main restricted universe multiverse
deb ${MIRROR_URL} ${DISTRO_CODENAME}-backports main restricted universe multiverse
EOF

# Stage Kian MOK Certificate for Secure Boot Trust Chain
mkdir -p "${TARGET_ROOTFS}/etc/ssl/certs" "${TARGET_ROOTFS}/usr/share/kian/keys"
if [[ -f "${KEYS_DIR}/kian_mok.der" ]]; then
    cp "${KEYS_DIR}/kian_mok.der" "${TARGET_ROOTFS}/etc/ssl/certs/kian_mok.der"
    cp "${KEYS_DIR}/kian_mok.der" "${TARGET_ROOTFS}/usr/share/kian/keys/kian_mok.der"
    log_info "Copied Kian MOK certificate to /etc/ssl/certs/kian_mok.der."
fi
if [[ -f "${KEYS_DIR}/kian_mok.pem" ]]; then
    cp "${KEYS_DIR}/kian_mok.pem" "${TARGET_ROOTFS}/usr/share/kian/keys/kian_mok.pem"
fi

# Stage Kernel Packages into Chroot (Mandatory in real builds!)
mkdir -p "${TARGET_ROOTFS}/tmp/kian_pkgs"
FOUND_PKGS=0
for pkg_dir in "${KERNEL_PKGS_DIR}" "${PROJECT_ROOT}/build/kernel_pkgs" "${PROJECT_ROOT}/build/out/kernel_pkgs"; do
    if compgen -G "${pkg_dir}/linux-image*kian-v3*.deb" > /dev/null; then
        cp -u "${pkg_dir}"/*.deb "${TARGET_ROOTFS}/tmp/kian_pkgs/"
        log_success "Staged linux-kian v3 packages from ${pkg_dir} into chroot /tmp/kian_pkgs/."
        FOUND_PKGS=1
        break
    fi
done
if [[ $FOUND_PKGS -eq 0 ]]; then
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_warn "[DRY-RUN] No pre-compiled kernel deb packages found in ${KERNEL_PKGS_DIR}."
    else
        log_error "FATAL: Mandatory linux-kian v3 .deb packages missing from ${KERNEL_PKGS_DIR}!"
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 5. Configure Hardware Modules, NTSync Udev & Sysctl Performance Tuning
# ------------------------------------------------------------------------------
log_step "Configuring Early Boot Input Modules, NTSync & Kernel Performance Sysctls"

mkdir -p "${TARGET_ROOTFS}/etc/initramfs-tools" \
         "${TARGET_ROOTFS}/etc/modules-load.d" \
         "${TARGET_ROOTFS}/etc/udev/rules.d" \
         "${TARGET_ROOTFS}/etc/sysctl.d"

# Early-boot keyboard/SPI/HID drivers so LUKS2 passphrases work on MacBooks, Surface, and USB keyboards
cat << 'EOF' > "${TARGET_ROOTFS}/etc/initramfs-tools/modules"
# KIAN-OS v3 Early-Boot Input & Storage Modules (LUKS2 Passphrase Entry)
usbhid
hid_generic
hid_apple
spi_pxa2xx_platform
intel_lpss_pci
applespi
surface_aggregator
surface_aggregator_registry
surface_aggregator_hub
surface_hid_core
surface_hid
surface_kbd
nvme
btrfs
overlay
EOF

# Auto-load NTSync synchronization primitive driver & expose /dev/ntsync (0666) for Wine/Proton
cat << 'EOF' > "${TARGET_ROOTFS}/etc/modules-load.d/kian-ntsync.conf"
# KIAN-OS v3 Windows NT Synchronization Primitive Driver
ntsync
EOF

cat << 'EOF' > "${TARGET_ROOTFS}/etc/udev/rules.d/99-ntsync.rules"
KERNEL=="ntsync", MODE="0666", TAG+="uaccess"
EOF

# KIAN-OS v3 Kernel & Network Performance Profile (BORE + BBRv3 + Split-Lock Gaming Mitigation Off)
cat << 'EOF' > "${TARGET_ROOTFS}/etc/sysctl.d/99-kian-performance.conf"
# KIAN-OS v3 Superkernel Tuning
kernel.split_lock_mitigate = 0
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.swappiness = 10
vm.max_map_count = 2147483642
EOF

# ------------------------------------------------------------------------------
# 6. Execute In-Chroot Provisioning & Package Installation
# ------------------------------------------------------------------------------
log_step "Installing Core Packages, Dual Kernels, Casper Identity, and Live User"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating chroot package provisioning..."
    log_info "[DRY-RUN] Would install: systemd, udev, btrfs-progs, snapper, casper, dual-kernels, etc."
    log_info "[DRY-RUN] Would configure /etc/casper.conf for user 'kian' and FLAVOUR='kian'."
else
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -euo pipefail << 'CHROOT_EOF'
# Exclude non-PC ARM phone SoCs & datacenter rack-switch ASIC blobs so 100% of
# Intel/AMD/NVIDIA GPU, Wi-Fi, Bluetooth, and Audio firmware fits cleanly on ISO
mkdir -p /etc/dpkg/dpkg.cfg.d
cat << 'DPKG_EOF' > /etc/dpkg/dpkg.cfg.d/99-kian-firmware-filter
path-exclude=/lib/firmware/netronome/*
path-exclude=/usr/lib/firmware/netronome/*
path-exclude=/lib/firmware/mellanox/*
path-exclude=/usr/lib/firmware/mellanox/*
path-exclude=/lib/firmware/liquidio/*
path-exclude=/usr/lib/firmware/liquidio/*
path-exclude=/lib/firmware/qcom/*
path-exclude=/usr/lib/firmware/qcom/*
path-exclude=/lib/firmware/mrvl/prestera/*
path-exclude=/usr/lib/firmware/mrvl/prestera/*
path-exclude=/lib/firmware/dpaa2/*
path-exclude=/usr/lib/firmware/dpaa2/*
path-exclude=/lib/firmware/qed/*
path-exclude=/usr/lib/firmware/qed/*
path-exclude=/lib/firmware/cxgb4/*
path-exclude=/usr/lib/firmware/cxgb4/*
path-exclude=/lib/firmware/bnx2x/*
path-exclude=/usr/lib/firmware/bnx2x/*
path-exclude=/lib/firmware/cnm/*
path-exclude=/usr/lib/firmware/cnm/*
DPKG_EOF

apt-get -o Acquire::Retries=3 update

# Core Base System, Bootloaders (UEFI + BIOS), GPU/Wi-Fi Firmware + RegDB, Mesa DRI & Dual Kernels
apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates apt-transport-https gnupg \
    systemd systemd-sysv udev dbus dbus-user-session sudo locales tzdata \
    network-manager wpasupplicant wireless-regdb iw dnsmasq-base \
    btrfs-progs snapper cryptsetup cryptsetup-initramfs \
    casper user-setup \
    grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed shim-signed mokutil sbsigntool \
    linux-firmware intel-microcode amd64-microcode \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    libgl1-mesa-dri libegl-mesa0 libgbm1 mesa-vulkan-drivers mesa-va-drivers vulkan-tools \
    ubuntu-drivers-common pciutils usbutils dmidecode \
    curl wget nano iproute2 iputils-ping kmod zstd xz-utils \
    linux-image-generic linux-headers-generic

# Verify mandatory hardware GPU/Wi-Fi firmware, regulatory.db & BIOS/UEFI GRUB modules exist right now
test -d /usr/lib/firmware/amdgpu
test -d /usr/lib/firmware/i915
test -d /usr/lib/firmware/nvidia
test -f /lib/firmware/regulatory.db
test -f /usr/lib/grub/i386-pc/modinfo.sh
test -f /usr/lib/grub/x86_64-efi/modinfo.sh

# Disable Wi-Fi Power-Save TX throttling & enforce clean dynamic DNS + Cloudflare/Google fallback
mkdir -p /etc/NetworkManager/conf.d /etc/modprobe.d
cat << 'NM_EOF' > /etc/NetworkManager/conf.d/90-kiyan-wifi-dns.conf
[connection]
# 2 = disable Wi-Fi power saving (prevents weak signal, high latency & packet drops on Realtek/Intel/MediaTek)
wifi.powersave = 2

[main]
dns = default
rc-manager = file

[global-dns-domain-*]
servers = 1.1.1.1,8.8.8.8
NM_EOF

cat << 'WIFI_EOF' > /etc/modprobe.d/99-kiyan-wifi-stability.conf
options iwlwifi power_save=0
options rtw88_core disable_lps_deep=y
options rtw88_pci disable_aspm=y
options rtw89_core disable_ps_mode=y
options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y
WIFI_EOF

# Official Kiyan OS Identity (replaces Ubuntu branding across GRUB, Settings, Plymouth & Welcome)
cat << 'OSREL_EOF' > /etc/os-release
PRETTY_NAME="Kiyan OS v3"
NAME="Kiyan OS"
VERSION_ID="3.0"
VERSION="3.0 (Liquid Crystal Edition)"
VERSION_CODENAME=noble
ID=kiyan
ID_LIKE="ubuntu debian"
HOME_URL="https://github.com/manmojt/kiyan-os"
SUPPORT_URL="https://github.com/manmojt/kiyan-os/issues"
BUG_REPORT_URL="https://github.com/manmojt/kiyan-os/issues"
UBUNTU_CODENAME=noble
LOGO=kiyan-icon
OSREL_EOF

cat << 'LSB_EOF' > /etc/lsb-release
DISTRIB_ID=KiyanOS
DISTRIB_RELEASE=3.0
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="Kiyan OS v3"
LSB_EOF

# Authoritative Casper Live Configuration (prevents 'ubuntu' UID 1000 collision & .disk/info override)
cat << 'EOF' > /etc/casper.conf
export USERNAME="kian"
export USERFULLNAME="Kian Live User"
export HOST="kian-os"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="kian"
EOF

# Install Verified Kian v3 Superkernel Debs (ZERO swallowed errors!)
echo ":: Installing verified linux-kian v3 superkernel packages inside chroot..."
dpkg -i /tmp/kian_pkgs/*.deb
rm -rf /tmp/kian_pkgs

KVER=$(ls /lib/modules/ 2>/dev/null | grep -E "^6\.8\..*-kian-v3$" | sort -V | tail -n 1)
if [[ -z "${KVER}" ]]; then
    echo "FATAL: linux-kian v3 modules directory not found in /lib/modules!" >&2
    exit 1
fi
test -f "/boot/vmlinuz-${KVER}"
echo ":: Verified superkernel installed in rootfs: /boot/vmlinuz-${KVER}"

# Point unversioned /boot/vmlinuz & /boot/initrd.img symlinks to linux-kian v3 (not generic!)
ln -sfn "vmlinuz-${KVER}" /boot/vmlinuz
ln -sfn "initrd.img-${KVER}" /boot/initrd.img

# Generate Locales & Set Timezone
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ln -fs /usr/share/zoneinfo/UTC /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

# Create Default 'kian' User with Essential Hardware Groups (guarantee UID/GID 1000)
if ! id -u kian &>/dev/null; then
    EXISTING_1000=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd || true)
    if [[ -n "${EXISTING_1000}" && "${EXISTING_1000}" != "kian" ]]; then
        userdel -rf "${EXISTING_1000}" 2>/dev/null || true
    fi
    EXISTING_GRP_1000=$(awk -F: '$3 == 1000 {print $1}' /etc/group || true)
    if [[ -n "${EXISTING_GRP_1000}" && "${EXISTING_GRP_1000}" != "kian" ]]; then
        groupdel "${EXISTING_GRP_1000}" 2>/dev/null || true
    fi
    groupadd -g 1000 kian 2>/dev/null || true
    useradd -m -u 1000 -g 1000 -s /bin/bash -G sudo,adm,dialout,cdrom,audio,video,render,plugdev,netdev kian
    echo "kian:kian" | chpasswd
fi

# Configure Live Session Sudoers Privileges (explicitly purged by post-install-drivers-and-clean.sh!)
mkdir -p /etc/sudoers.d
echo "kian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-kian-live
chmod 0440 /etc/sudoers.d/99-kian-live

# Initialize GRUB Environment Block for Watchdog
mkdir -p /boot/grub
grub-editenv /boot/grub/grubenv create
grub-editenv /boot/grub/grubenv set bootcount=0
grub-editenv /boot/grub/grubenv set boot_counter=0
grub-editenv /boot/grub/grubenv set bootlimit=3

# Clean APT caches to minimize footprint
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF
fi

# ------------------------------------------------------------------------------
# 7. Unmount Virtual Filesystems
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Unmounting virtual pseudo-filesystems..."
    unmount_virtual_fs "${TARGET_ROOTFS}"
fi

log_success "Phase 2: Ubuntu 24.04 LTS Rootfs bootstrapping complete!"
