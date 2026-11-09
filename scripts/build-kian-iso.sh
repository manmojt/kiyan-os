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

echo "=== Initializing Kian-OS v3 Production ISO Pipeline ==="
mkdir -p "${PROJECT_ROOT}/output"

# Execute master 5-phase build orchestrator
"${PROJECT_ROOT}/build/build_all.sh" "$@"

# Stage distribution artifacts into output directory
if [[ -d "${PROJECT_ROOT}/dist" ]]; then
    echo "Staging distribution artifacts into output directory..."
    cp -r "${PROJECT_ROOT}/dist"/* "${PROJECT_ROOT}/output/" 2>/dev/null || true
fi

cd "${PROJECT_ROOT}/output"
# Ensure artifacts match workflow publish expectations
if [[ -f "kian-os-v3-noble-amd64.iso" && ! -f "Kian-OS-v2-x86_64.iso" ]]; then
    ln -sf "kian-os-v3-noble-amd64.iso" "Kian-OS-v2-x86_64.iso"
    ln -sf "kian-os-v3-noble-amd64.iso.sha256" "Kian-OS-v2-x86_64.iso.sha256" 2>/dev/null || true
fi
sha256sum *.iso > SHA256SUMS 2>/dev/null || true

echo "=== Kian-OS v3 Production ISO Pipeline Finished ==="
