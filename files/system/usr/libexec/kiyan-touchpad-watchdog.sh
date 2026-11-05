#!/usr/bin/env bash
set -euo pipefail

modules=(
  i2c_designware_platform
  i2c_designware_pci
  i2c_hid_acpi
  elan_i2c
  hid_multitouch
)

for module in "${modules[@]}"; do
  /usr/bin/modprobe --quiet "$module" 2>/dev/null || true
done
