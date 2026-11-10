#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Build System: Clean-Slate Rootfs Debootstrap (Phase 2)
# Path: build/02_bootstrap_rootfs.sh
# Description: Debootstraps Ubuntu 24.04 LTS (Noble Numbat) minbase rootfs,
#              configures apt repositories, locales, timezone, core packages,
#              default 'kian' user, dual kernels (kian-v3 + stock generic), and
#              GRUB bootcounter watchdog initialization.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_ROOTFS="${ROOTFS_DIR}"
MIRROR_URL="http://archive.ubuntu.com/ubuntu/"
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
  --mirror <URL>      Ubuntu archive mirror URL (default: http://archive.ubuntu.com/ubuntu/)
  --clean             Wipe target rootfs before bootstrapping

Examples:
  sudo ./02_bootstrap_rootfs.sh
  ./02_bootstrap_rootfs.sh --dry-run
  sudo ./02_bootstrap_rootfs.sh --clean --mirror http://mirrors.kernel.org/ubuntu/
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
        debootstrap --arch="${DISTRO_ARCH}" --variant=minbase "${DISTRO_CODENAME}" "${TARGET_ROOTFS}" "${MIRROR_URL}"
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

# Copy resolv.conf for chroot network connectivity
if [[ -f /etc/resolv.conf ]]; then
    cp /etc/resolv.conf "${TARGET_ROOTFS}/etc/resolv.conf"
else
    cat << 'EOF' > "${TARGET_ROOTFS}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# Configure APT Repositories (Noble LTS)
log_info "Writing Noble APT repositories (main, restricted, universe, multiverse)..."
cat << EOF > "${TARGET_ROOTFS}/etc/apt/sources.list"
deb ${MIRROR_URL} ${DISTRO_CODENAME} main restricted universe multiverse
deb ${MIRROR_URL} ${DISTRO_CODENAME}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${DISTRO_CODENAME}-security main restricted universe multiverse
deb ${MIRROR_URL} ${DISTRO_CODENAME}-backports main restricted universe multiverse
EOF

# Stage Kian MOK Certificate for Secure Boot Trust Chain
mkdir -p "${TARGET_ROOTFS}/etc/ssl/certs"
if [[ -f "${KEYS_DIR}/kian_mok.der" ]]; then
    cp "${KEYS_DIR}/kian_mok.der" "${TARGET_ROOTFS}/etc/ssl/certs/kian_mok.der"
    log_info "Copied Kian MOK certificate to /etc/ssl/certs/kian_mok.der."
fi

# Stage Kernel Packages into Chroot
mkdir -p "${TARGET_ROOTFS}/tmp/kian_pkgs"
FOUND_PKGS=0
for pkg_dir in "${KERNEL_PKGS_DIR}" "${PROJECT_ROOT}/build/kernel_pkgs" "${PROJECT_ROOT}/build/out/kernel_pkgs"; do
    if compgen -G "${pkg_dir}/*.deb" > /dev/null; then
        cp -u "${pkg_dir}"/*.deb "${TARGET_ROOTFS}/tmp/kian_pkgs/"
        log_success "Staged linux-kian v3 packages from ${pkg_dir} into chroot /tmp/kian_pkgs/."
        FOUND_PKGS=1
        break
    fi
done
if [[ $FOUND_PKGS -eq 0 ]]; then
    log_warn "No pre-compiled kernel deb packages found in ${KERNEL_PKGS_DIR}!"
fi

# ------------------------------------------------------------------------------
# 5. Execute In-Chroot Provisioning & Package Installation
# ------------------------------------------------------------------------------
log_step "Installing Core Packages, Dual Kernels, and Live User Configuration"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[DRY-RUN] Simulating chroot package provisioning..."
    log_info "[DRY-RUN] Would install: systemd, udev, btrfs-progs, snapper, casper, dual-kernels, etc."
    log_info "[DRY-RUN] Would create default user 'kian' with sudo privileges."
    log_info "[DRY-RUN] Would initialize GRUB watchdog bootcounter block."
else
    chroot "${TARGET_ROOTFS}" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -euo pipefail << 'CHROOT_EOF'
# Update package indices
apt-get update

# Core Base System & Utilities
apt-get install -y --no-install-recommends \
    systemd systemd-sysv udev dbus sudo locales tzdata \
    network-manager wpasupplicant btrfs-progs snapper \
    casper grub-efi-amd64-signed shim-signed \
    pipewire wireplumber \
    mesa-vulkan-drivers mesa-va-drivers vulkan-tools \
    ubuntu-drivers-common \
    curl wget nano iproute2 kmod ca-certificates \
    linux-image-generic linux-headers-generic

# Install Kian v3 Kernel Debs if staged
if compgen -G "/tmp/kian_pkgs/linux-image*.deb" > /dev/null; then
    echo ":: Installing linux-kian v3 superkernel packages inside chroot..."
    dpkg -i /tmp/kian_pkgs/*.deb || apt-get install -f -y
    KVER=$(ls /lib/modules/ 2>/dev/null | grep "kian-v3" | head -n 1 || true)
    if [[ -n "${KVER}" ]]; then
        echo ":: Generating dedicated initramfs for superkernel ${KVER}..."
        update-initramfs -c -k "${KVER}" || update-initramfs -u -k "${KVER}" || true
    fi
else
    echo ":: [WARN] No linux-image deb packages found in /tmp/kian_pkgs/"
fi
rm -rf /tmp/kian_pkgs

# Generate Locales & Set Timezone
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ln -fs /usr/share/zoneinfo/UTC /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

# Create Default 'kian' User with Essential Hardware Groups
if ! id -u kian &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,adm,dialout,cdrom,audio,video,plugdev kian
    echo "kian:kian" | chpasswd
fi

# Configure Live Session Sudoers Privileges
mkdir -p /etc/sudoers.d
echo "kian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-kian-live
chmod 0440 /etc/sudoers.d/99-kian-live

# Initialize GRUB Environment Block for Watchdog
mkdir -p /boot/grub
grub-editenv /boot/grub/grubenv create 2>/dev/null || true
grub-editenv /boot/grub/grubenv set bootcount=0 2>/dev/null || true
grub-editenv /boot/grub/grubenv set boot_counter=0 2>/dev/null || true
grub-editenv /boot/grub/grubenv set bootlimit=3 2>/dev/null || true

# Clean APT caches to minimize footprint
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_EOF
fi

# ------------------------------------------------------------------------------
# 6. Unmount Virtual Filesystems
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" != "1" ]]; then
    log_info "Unmounting virtual pseudo-filesystems..."
    unmount_virtual_fs "${TARGET_ROOTFS}"
fi

log_success "Phase 2: Ubuntu 24.04 LTS Rootfs bootstrapping complete!"
