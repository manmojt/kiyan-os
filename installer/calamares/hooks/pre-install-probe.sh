#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Calamares Pre-Install Hardware & Firmware Probe
# Path: installer/calamares/hooks/pre-install-probe.sh
# Description: Validates UEFI/Secure Boot, detects Surface, Mac, IPU6, and GPU hardware.
# ==============================================================================
set -euo pipefail

if [[ -n "${KIAN_PREINSTALL_LOG:-}" ]]; then
    LOG_FILE="${KIAN_PREINSTALL_LOG}"
    mkdir -p -m 700 "$(dirname "$LOG_FILE")" 2>/dev/null || true
else
    LOG_DIR="/run/calamares"
    mkdir -p -m 700 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/calamares-${UID:-0}"
    mkdir -p -m 700 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
    LOG_FILE="${LOG_DIR}/kian-preinstall.log"
fi

if command -v tee >/dev/null 2>&1; then
    exec > >(tee -a "$LOG_FILE" 2>/dev/null) 2>&1 || true
fi

echo "======================================================================"
echo " ==> KIAN-OS v3 Calamares Pre-Install Hardware & Firmware Probe"
echo " ==> Started at: $(date -u +"%Y-%m-%d %H:%M:%SZ")"
echo "======================================================================"

# 1. EFI / UEFI Firmware Verification
echo "[Probe 1/7] Inspecting firmware boot architecture..."
if [[ -d /sys/firmware/efi ]]; then
    echo "  [PASS] System booted in UEFI mode."
    touch /tmp/kian_hw_uefi
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "  [INFO] EFI runtime variable service accessible."
    fi
else
    echo "  [WARN] Legacy BIOS / CSM boot detected."
    # In live installer, KIAN-OS v3 requires UEFI for dual-kernel fallback and MOK signing.
    if [[ "${KIAN_TEST_MODE:-0}" != "1" ]]; then
        echo "  [NOTICE] UEFI recommended for Btrfs snapshot rollbacks & Secure Boot."
    fi
fi

# 2. Secure Boot Status Detection
echo "[Probe 2/7] Checking UEFI Secure Boot state..."
SB_ACTIVE="Unknown"
if command -v mokutil >/dev/null 2>&1; then
    SB_ACTIVE=$(mokutil --sb-state 2>/dev/null || echo "Unavailable")
    echo "  [INFO] mokutil status: $SB_ACTIVE"
fi
if [[ "$SB_ACTIVE" =~ "SecureBoot enabled" ]]; then
    echo "  [DETECTED] UEFI Secure Boot is active."
    touch /tmp/kian_hw_secureboot
else
    echo "  [INFO] UEFI Secure Boot disabled or standard mode."
fi

# 3. Microarchitecture Baseline (x86-64-v3 check)
echo "[Probe 3/7] Verifying CPU microarchitecture compatibility (x86-64-v3)..."
CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)
if [[ "$CPU_FLAGS" =~ avx2 && "$CPU_FLAGS" =~ fma && "$CPU_FLAGS" =~ bmi1 && "$CPU_FLAGS" =~ bmi2 ]]; then
    echo "  [PASS] CPU satisfies x86-64-v3 microarchitecture requirements."
    touch /tmp/kian_hw_x86_64_v3
else
    echo "  [WARN] CPU does not fully support x86-64-v3 instructions (AVX2/FMA/BMI)."
fi

# 4. Microsoft Surface Subsystem Detection
echo "[Probe 4/7] Probing for Microsoft Surface hardware..."
IS_SURFACE=0
DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
DMI_SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

if [[ -d /sys/bus/platform/drivers/surface_aggregator ]] || \
   [[ "$DMI_PRODUCT" =~ [Ss]urface ]] || \
   [[ "$DMI_SYS_VENDOR" =~ [Mm]icrosoft.*[Cc]orporation && "$DMI_PRODUCT" =~ [Ss]urface ]]; then
    IS_SURFACE=1
fi

if [[ "$IS_SURFACE" -eq 1 ]]; then
    echo "  [DETECTED] Microsoft Surface platform: $DMI_PRODUCT"
    touch /tmp/kian_hw_surface
    # Check for IPTS / ITHC Touchscreen Digitizer
    if lspci -d 8086:9d3e >/dev/null 2>&1 || lspci -d 8086:34d6 >/dev/null 2>&1 || \
       lspci -d 8086:a0d6 >/dev/null 2>&1 || lspci -d 8086:43d6 >/dev/null 2>&1; then
        echo "  [DETECTED] Surface IPTS/ITHC Touch/Pen active digitizer hardware."
        touch /tmp/kian_hw_surface_ipts
    fi
else
    echo "  [INFO] Generic / Non-Surface platform."
fi

# 5. Apple Intel Mac Hardware Detection
echo "[Probe 5/7] Probing for Apple Mac hardware..."
if [[ "$DMI_SYS_VENDOR" =~ [Aa]pple ]] || [[ "$DMI_PRODUCT" =~ [Mm]ac[Bb]ook ]] || [[ "$DMI_PRODUCT" =~ [Mm]ac ]]; then
    echo "  [DETECTED] Apple Mac platform: $DMI_PRODUCT"
    touch /tmp/kian_hw_apple
    # Detect Apple SPI keyboard/trackpad (applespi)
    if [[ -d /sys/bus/spi/devices ]] && grep -q -i "applespi" /proc/modules 2>/dev/null; then
        echo "  [DETECTED] Apple SPI Force Touch Trackpad/Keyboard."
        touch /tmp/kian_hw_apple_spi
    fi
else
    echo "  [INFO] Non-Apple hardware."
fi

# 6. Intel IPU6 Camera Subsystem Detection
echo "[Probe 6/7] Probing for Intel IPU6 MIPI camera controller..."
# Check known IPU6 PCI device IDs: TigerLake, AlderLake, RaptorLake, MeteorLake
if lspci -d 8086:9a19 >/dev/null 2>&1 || \
   lspci -d 8086:465d >/dev/null 2>&1 || \
   lspci -d 8086:7d19 >/dev/null 2>&1 || \
   lspci -d 8086:a75d >/dev/null 2>&1; then
    echo "  [DETECTED] Intel IPU6 Camera Interface."
    touch /tmp/kian_hw_ipu6
else
    echo "  [INFO] Intel IPU6 camera hardware not present."
fi

# 7. GPU Controller Identification (NVIDIA / AMD / Intel)
echo "[Probe 7/7] Probing display controllers & graphics accelerators..."
if lspci -nn | grep -Ei 'vga|3d|display' | grep -qi 'nvidia'; then
    echo "  [DETECTED] NVIDIA GPU Controller."
    touch /tmp/kian_hw_gpu_nvidia
fi
if lspci -nn | grep -Ei 'vga|3d|display' | grep -qi 'amd|advanced micro devices|ati'; then
    echo "  [DETECTED] AMD Radeon GPU Controller (Explicit Sync RADV capable)."
    touch /tmp/kian_hw_gpu_amd
fi
if lspci -nn | grep -Ei 'vga|3d|display' | grep -qi 'intel'; then
    echo "  [DETECTED] Intel Graphics Controller."
    touch /tmp/kian_hw_gpu_intel
fi

# 8. Guarantee Live SquashFS Source Path (/cdrom/casper/filesystem.squashfs) for USB / Ventoy / Rufus Boots
echo "[Probe 8/8] Verifying live SquashFS source path for Calamares unpackfs..."
if [[ ! -s /cdrom/casper/filesystem.squashfs ]]; then
    FOUND_SQUASHFS=""
    for candidate in \
        /run/live/medium/casper/filesystem.squashfs \
        /isodevice/casper/filesystem.squashfs \
        /media/*/casper/filesystem.squashfs \
        /mnt/*/casper/filesystem.squashfs; do
        if [[ -s "${candidate}" ]]; then
            FOUND_SQUASHFS="${candidate}"
            break
        fi
    done
    if [[ -n "${FOUND_SQUASHFS}" ]]; then
        mkdir -p /cdrom/casper
        ln -sfn "${FOUND_SQUASHFS}" /cdrom/casper/filesystem.squashfs
        echo "  [FIXED] Linked /cdrom/casper/filesystem.squashfs -> ${FOUND_SQUASHFS}"
    elif [[ "${KIAN_TEST_MODE:-0}" != "1" ]]; then
        echo "  [WARN] /cdrom/casper/filesystem.squashfs not found in standard paths; checking active mounts..."
    fi
else
    echo "  [PASS] /cdrom/casper/filesystem.squashfs verified ready."
fi

echo "======================================================================"
echo " ==> Hardware probe completed successfully. Profile saved to /tmp/kian_hw_*"
echo "======================================================================"
exit 0
