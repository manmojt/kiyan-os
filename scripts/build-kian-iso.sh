#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 Production ISO Master Entrypoint
# Invoked by GitHub Actions runner or local builder fleet
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Initializing Kian-OS v3 Production ISO Pipeline ==="
mkdir -p "${PROJECT_ROOT}/output"

# Execute master 5-phase build orchestrator
if [[ -x "${PROJECT_ROOT}/build/build_all.sh" ]]; then
    "${PROJECT_ROOT}/build/build_all.sh" "$@"
else
    bash "${PROJECT_ROOT}/build/build_all.sh" "$@"
fi

# Ensure build artifacts are staged into output/ for GitHub Releases upload
if [[ -d "${PROJECT_ROOT}/dist" ]]; then
    echo "Staging distribution artifacts into output directory..."
    cp -r "${PROJECT_ROOT}/dist"/* "${PROJECT_ROOT}/output/" 2>/dev/null || true
fi

# Compatibility symlink for legacy runner filenames if needed
cd "${PROJECT_ROOT}/output"
if [[ -f "kian-os-v3-noble-amd64.iso" && ! -f "Kian-OS-v2-x86_64.iso" ]]; then
    ln -sf "kian-os-v3-noble-amd64.iso" "Kian-OS-v2-x86_64.iso"
    ln -sf "kian-os-v3-noble-amd64.iso.sha256" "Kian-OS-v2-x86_64.iso.sha256" 2>/dev/null || true
fi
sha256sum *.iso > SHA256SUMS 2>/dev/null || true

echo "=== Kian-OS v3 Production ISO Pipeline Finished ==="
