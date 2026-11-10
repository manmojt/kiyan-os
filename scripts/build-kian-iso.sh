#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Production ISO Master Entrypoint
# ==============================================================================
set -euo pipefail

# Ensure script runs with root privileges
if [[ ${EUID:-0} -ne 0 ]]; then
    echo "Elevating to root privileges via sudo..."
    exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Initializing Kian-OS v3 Clean-Slate Production ISO Pipeline ==="
mkdir -p "${PROJECT_ROOT}/output"
mkdir -p "${PROJECT_ROOT}/build/kernel_pkgs"

# Download verified superkernel v3 packages if missing
if ! ls "${PROJECT_ROOT}/build/kernel_pkgs"/linux-image*kian-v3*.deb &>/dev/null; then
    echo ":: Fetching verified linux-kian v3 superkernel deb packages from GitHub Release 14..."
    if command -v gh &>/dev/null; then
        gh release download linux-kian-v3-build-14 -R manmojt/kiyan-os -D "${PROJECT_ROOT}/build/kernel_pkgs/" -p '*.deb' || true
    fi
fi

# Execute master build orchestrator with pre-compiled kernel packages
"${PROJECT_ROOT}/build/build_all.sh" --skip-kernel "$@"

# Stage distribution artifacts into output directory
if [[ -d "${PROJECT_ROOT}/dist" ]]; then
    echo "Staging distribution artifacts into output directory..."
    cp -rf "${PROJECT_ROOT}/dist"/* "${PROJECT_ROOT}/output/"
fi

cd "${PROJECT_ROOT}/output"

# Strict Zero-Flaw Validation: ensure production ISO exists and is valid (> 1 GB)
ISO_FILE="kian-os-v3-noble-amd64.iso"
if [[ ! -s "${ISO_FILE}" ]]; then
    echo "ERROR: Production ISO ${ISO_FILE} was not generated or is empty!" >&2
    exit 1
fi

ISO_BYTES=$(stat -c%s "${ISO_FILE}")
if [[ ${ISO_BYTES} -lt 1073741824 ]]; then
    echo "ERROR: Production ISO ${ISO_FILE} size (${ISO_BYTES} bytes) is below minimum threshold (1 GiB)!" >&2
    exit 1
fi

echo ":: Generating cryptographic SHA-256 manifest..."
sha256sum "${ISO_FILE}" > "${ISO_FILE}.sha256"
sha256sum "${ISO_FILE}" > SHA256SUMS

echo "=== Kian-OS v3 Production ISO Pipeline Finished Successfully (${ISO_FILE}: ${ISO_BYTES} bytes) ==="
