#!/usr/bin/env bash
set -euo pipefail

# Load ntsync for Wine/Proton and make Huawei I2C touchpad drivers available
# early enough for the initramfs on affected MateBook models.
install -d -m 0755 /etc/modules-load.d /etc/dracut.conf.d
cat > /etc/modules-load.d/ntsync.conf <<'EOF'
ntsync
EOF

cat > /etc/dracut.conf.d/kiyan-huawei.conf <<'EOF'
add_drivers+=" i2c_designware_platform i2c_designware_pci i2c_hid_acpi elan_i2c hid_multitouch "
EOF

# The image-builder generic ISO boots a live squashfs root.
cat > /etc/dracut.conf.d/40-kiyan-live.conf <<'EOF'
compress="xz"
add_dracutmodules+=" qemu qemu-net livenet dmsquash-live "
early_microcode="no"
EOF

# image-builder expects the signed shim/GRUB EFI vendor tree under /boot/efi.
shopt -s nullglob
vendor_dirs=()
for candidate in /usr/lib/efi/shim/*/EFI/*; do
  if [[ -d "$candidate" && "${candidate##*/}" != BOOT ]]; then
    vendor_dirs+=("$candidate")
  fi
done
if (( ${#vendor_dirs[@]} != 1 )) || [[ ! -d "${vendor_dirs[0]}" ]]; then
  printf 'Expected exactly one signed shim vendor directory, found %s\n' "${#vendor_dirs[@]}" >&2
  exit 1
fi
vendor="${vendor_dirs[0]##*/}"
install -d -m 0755 "/boot/efi/EFI/${vendor}"
cp -a "${vendor_dirs[0]}"/. "/boot/efi/EFI/${vendor}/"

# The generic-ISO boot path uses Fedora's signed CD GRUB binary (gcdx64.efi).
gcd_candidates=(/usr/lib/efi/grub2/*/EFI/"${vendor}"/gcdx64.efi)
if (( ${#gcd_candidates[@]} != 1 )) || [[ ! -f "${gcd_candidates[0]}" ]]; then
  printf 'Expected exactly one gcdx64.efi for vendor %s, found %s\n' \
    "$vendor" "${#gcd_candidates[@]}" >&2
  exit 1
fi
install -m 0644 "${gcd_candidates[0]}" "/boot/efi/EFI/${vendor}/gcdx64.efi"

# Define the generic ISO's label and GRUB menu without a serial console entry.
install -d -m 0755 /usr/lib/image-builder/bootc
cat > /usr/lib/image-builder/bootc/iso.yaml <<'EOF'
label: "Kiyan OS LB1"
kernel_args:
  - quiet
  - splash
  - loglevel=3
grub2:
  timeout: 5
  entries:
    - name: "Kiyan OS (Live)"
      linux: "${kernelpath} ${root}"
      initrd: "${initrdpath}"
EOF

# Render the vector logo once during the image build, then select the theme.
theme_dir=/usr/share/plymouth/themes/kiyan-lb1
install -d -m 0755 "${theme_dir}"
rsvg-convert --width 900 --height 320 \
  --output "${theme_dir}/kiyan-lb1.png" \
  "${theme_dir}/kiyan-lb1.svg"
plymouth-set-default-theme kiyan-lb1
