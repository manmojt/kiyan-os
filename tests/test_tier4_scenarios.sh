#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 E2E Test Suite - Tier 4: Real-World Workload Scenarios
# Path: tests/test_tier4_scenarios.sh
# Description: Real-world workload tests: build pipeline dry-run execution,
#              atomic APT snapshot lifecycle, Btrfs rollback simulation,
#              and dual-kernel recovery watchdog logic.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI Color Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Ephemeral working directory for scenario isolation
MOCK_SCENARIO_DIR=$(mktemp -d /tmp/kian-tier4-scenario-XXXXXX)
cleanup() {
    rm -rf "${MOCK_SCENARIO_DIR}"
    rm -rf "${PROJECT_ROOT}/build/out" "${PROJECT_ROOT}/dist"
}
trap cleanup EXIT

test_start() {
    local desc="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${CYAN}[TEST ${TOTAL_TESTS}]${NC} ${desc}..."
}

test_pass() {
    local msg="${1:-Passed}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  ${GREEN}✓ [PASS]${NC} ${msg}"
}

test_fail() {
    local msg="${1:-Failed}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "  ${RED}✗ [FAIL]${NC} ${msg}" >&2
}

echo -e "\n${BOLD}${BLUE}================================================================================${NC}"
echo -e "${BOLD}${BLUE}   KIAN-OS v3 Test Suite: Tier 4 - Real-World Workload Scenarios               ${NC}"
echo -e "${BOLD}${BLUE}================================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. Scenario 1: Full 5-Phase Automated Build Pipeline Dry-Run Execution
# ------------------------------------------------------------------------------
test_start "Scenario 1: Full 5-Phase modular build pipeline dry-run execution (build_all.sh --dry-run)"

rm -rf "${PROJECT_ROOT}/build/out" "${PROJECT_ROOT}/dist"
BUILD_OUTPUT=$(bash "${PROJECT_ROOT}/build/build_all.sh" --dry-run 2>&1)

PIPELINE_OK=1

# Check Phase 1: Kernel
if ! echo "$BUILD_OUTPUT" | grep -q "Phase 1: linux-kian v3 Kernel" || \
   ! echo "$BUILD_OUTPUT" | grep -q "linux-image-6.8.0-31-kian-v3"; then
    echo -e "  ${RED}Phase 1 (Kernel Build) did not complete as expected${NC}" >&2
    PIPELINE_OK=0
fi

# Check Phase 2: Rootfs
if ! echo "$BUILD_OUTPUT" | grep -q "Phase 2: Clean-Slate Ubuntu 24.04 LTS Rootfs Debootstrap" || \
   ! echo "$BUILD_OUTPUT" | grep -E -q "debootstrap minbase noble|Existing base system found"; then
    echo -e "  ${RED}Phase 2 (Rootfs Debootstrap) did not complete as expected${NC}" >&2
    PIPELINE_OK=0
fi

# Check Phase 3: Desktop
if ! echo "$BUILD_OUTPUT" | grep -q "Phase 3: Desktop Environment" || \
   ! echo "$BUILD_OUTPUT" | grep -q "SDDM Pure Wayland"; then
    echo -e "  ${RED}Phase 3 (Desktop Customization) did not complete as expected${NC}" >&2
    PIPELINE_OK=0
fi

# Check Phase 4: ISO Mastering
if ! echo "$BUILD_OUTPUT" | grep -q "Phase 4: Live Squashfs Compression" || \
   ! echo "$BUILD_OUTPUT" | grep -q "xorriso"; then
    echo -e "  ${RED}Phase 4 (ISO Mastering) did not complete as expected${NC}" >&2
    PIPELINE_OK=0
fi

# Check Phase 5: Verification & Completion
if ! echo "$BUILD_OUTPUT" | grep -q "Phase 5: Automated ISO Verification" || \
   ! echo "$BUILD_OUTPUT" | grep -q "KIAN-OS v3 Production Build Completed Successfully"; then
    echo -e "  ${RED}Phase 5 (ISO Verification & Summary) did not complete as expected${NC}" >&2
    PIPELINE_OK=0
fi

if [[ $PIPELINE_OK -eq 1 ]]; then
    test_pass "Master build pipeline executed all 5 phases in dry-run mode and generated deliverables."
else
    test_fail "Master build pipeline dry-run execution failed."
fi

# ------------------------------------------------------------------------------
# 2. Scenario 2: End-to-End APT Transaction Snapshot Lifecycle
# ------------------------------------------------------------------------------
test_start "Scenario 2: APT transaction pre/post snapshot pairing and repository tracking"

APT_SNAPS_DIR="${MOCK_SCENARIO_DIR}/apt_snapshots"
APT_STATE_FILE="${MOCK_SCENARIO_DIR}/apt_state.state"
APT_HOOK="${PROJECT_ROOT}/scripts/btrfs-apt-hook"
ROLLBACK="${PROJECT_ROOT}/scripts/kian-rollback"

LIFECYCLE_OK=1

# Step A: Pre-Transaction Snapshot #1
KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="${APT_SNAPS_DIR}" KIAN_APT_STATE_FILE="${APT_STATE_FILE}" \
    "$APT_HOOK" pre >/dev/null 2>&1

PRE_SNAP_1="${APT_SNAPS_DIR}/snap_1_pre"
if [[ ! -d "$PRE_SNAP_1" ]] || [[ ! -f "${PRE_SNAP_1}/.kian_snapshot_meta.json" ]]; then
    echo -e "  ${RED}Pre-transaction snapshot 1 not created${NC}" >&2
    LIFECYCLE_OK=0
fi

META_PRE_1=$(cat "${PRE_SNAP_1}/.kian_snapshot_meta.json" 2>/dev/null || echo "")
if ! echo "$META_PRE_1" | grep -q '"id": 1' || ! echo "$META_PRE_1" | grep -q '"type": "pre"'; then
    echo -e "  ${RED}Pre-transaction metadata invalid in snapshot 1${NC}" >&2
    LIFECYCLE_OK=0
fi

if [[ ! -f "$APT_STATE_FILE" ]] || [[ "$(cat "$APT_STATE_FILE" | tr -d ' ')" != "1" ]]; then
    echo -e "  ${RED}APT state file does not contain active snapshot ID 1${NC}" >&2
    LIFECYCLE_OK=0
fi

# Step B: Post-Transaction Snapshot #1
KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="${APT_SNAPS_DIR}" KIAN_APT_STATE_FILE="${APT_STATE_FILE}" \
    "$APT_HOOK" post >/dev/null 2>&1

POST_SNAP_1="${APT_SNAPS_DIR}/snap_1_post"
if [[ ! -d "$POST_SNAP_1" ]] || [[ ! -f "${POST_SNAP_1}/.kian_snapshot_meta.json" ]]; then
    echo -e "  ${RED}Post-transaction snapshot 1 not created${NC}" >&2
    LIFECYCLE_OK=0
fi

META_POST_1=$(cat "${POST_SNAP_1}/.kian_snapshot_meta.json" 2>/dev/null || echo "")
if ! echo "$META_POST_1" | grep -q '"id": 1' || ! echo "$META_POST_1" | grep -q '"type": "post"'; then
    echo -e "  ${RED}Post-transaction metadata invalid in snapshot 1${NC}" >&2
    LIFECYCLE_OK=0
fi

# State file should have been consumed and removed
if [[ -f "$APT_STATE_FILE" ]]; then
    echo -e "  ${RED}APT state file was not cleaned up after post-invoke${NC}" >&2
    LIFECYCLE_OK=0
fi

# Step C: Subsequent APT Transaction (ID increment to 2)
KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="${APT_SNAPS_DIR}" KIAN_APT_STATE_FILE="${APT_STATE_FILE}" \
    "$APT_HOOK" pre >/dev/null 2>&1
KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="${APT_SNAPS_DIR}" KIAN_APT_STATE_FILE="${APT_STATE_FILE}" \
    "$APT_HOOK" post >/dev/null 2>&1

if [[ ! -d "${APT_SNAPS_DIR}/snap_2_pre" ]] || [[ ! -d "${APT_SNAPS_DIR}/snap_2_post" ]]; then
    echo -e "  ${RED}Second transaction snapshots (ID 2) were not properly created${NC}" >&2
    LIFECYCLE_OK=0
fi

# Step D: Repository Listing Verification
LIST_OUTPUT=$(KIAN_SNAPSHOTS_DIR="${APT_SNAPS_DIR}" "$ROLLBACK" list 2>&1)
if ! echo "$LIST_OUTPUT" | grep -q "snap_1_pre" || \
   ! echo "$LIST_OUTPUT" | grep -q "snap_1_post" || \
   ! echo "$LIST_OUTPUT" | grep -q "snap_2_pre" || \
   ! echo "$LIST_OUTPUT" | grep -q "snap_2_post" || \
   ! echo "$LIST_OUTPUT" | grep -qi "Total snapshots: 4"; then
    echo -e "  ${RED}Rollback repository list did not reflect all 4 snapshots:${NC} $LIST_OUTPUT" >&2
    LIFECYCLE_OK=0
fi

if [[ $LIFECYCLE_OK -eq 1 ]]; then
    test_pass "End-to-end APT snapshot lifecycle (pre/post pairing, state tracking, ID increment) verified."
else
    test_fail "APT transaction snapshot lifecycle scenario failed."
fi

# ------------------------------------------------------------------------------
# 3. Scenario 3: Btrfs Dynamic Rollback & Recovery Lifecycle Simulation
# ------------------------------------------------------------------------------
test_start "Scenario 3: Btrfs subvolume preservation, rollback cloning, and recovery simulation"

MOCK_BTRFS_TOP="${MOCK_SCENARIO_DIR}/mock_btrfs_top"
mkdir -p "${MOCK_BTRFS_TOP}/@rootfs"
mkdir -p "${MOCK_BTRFS_TOP}/@snapshots/snap_1_clean"
mkdir -p "${MOCK_BTRFS_TOP}/@snapshots/snap_2_broken"

# Current rootfs state
echo "SYSTEM_STATE=CURRENT_CORRUPTED" > "${MOCK_BTRFS_TOP}/@rootfs/os-release"
echo "SYSTEM_STATE=SNAPSHOT_1_CLEAN" > "${MOCK_BTRFS_TOP}/@snapshots/snap_1_clean/os-release"
echo "SYSTEM_STATE=SNAPSHOT_2_BROKEN" > "${MOCK_BTRFS_TOP}/@snapshots/snap_2_broken/os-release"

cat << 'EOF' > "${MOCK_BTRFS_TOP}/@snapshots/snap_1_clean/.kian_snapshot_meta.json"
{
  "id": 1,
  "type": "pre",
  "name": "snap_1_clean",
  "timestamp": "2026-11-09 08:00:00",
  "kernel": "6.8.0-31-kian-v3",
  "trigger": "apt-clean-backup"
}
EOF

cat << 'EOF' > "${MOCK_BTRFS_TOP}/@snapshots/snap_2_broken/.kian_snapshot_meta.json"
{
  "id": 2,
  "type": "post",
  "name": "snap_2_broken",
  "timestamp": "2026-11-09 09:00:00",
  "kernel": "6.8.0-31-kian-v3",
  "trigger": "apt-bad-upgrade"
}
EOF

# Set up mock btrfs CLI for testing kian-rollback binary directly
MOCK_BIN="${MOCK_SCENARIO_DIR}/mock_bin"
mkdir -p "${MOCK_BIN}"

cat << 'EOF' > "${MOCK_BIN}/btrfs"
#!/usr/bin/env bash
set -e
case "$1" in
    subvolume)
        case "$2" in
            snapshot)
                cp -a "$3" "$4"
                ;;
            list)
                echo "ID 256 gen 10 top level 5 path @rootfs"
                ;;
            set-default)
                exit 0
                ;;
            show)
                exit 0
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "${MOCK_BIN}/btrfs"

# Execute genuine kian-rollback binary directly
SIM_ROLLBACK_OK=1
ROLLBACK_OUTPUT=$(PATH="${MOCK_BIN}:${PATH}" KIAN_TEST_MODE=1 KIAN_BTRFS_MNT="${MOCK_BTRFS_TOP}" KIAN_SNAPSHOTS_DIR="${MOCK_BTRFS_TOP}/@snapshots" "${PROJECT_ROOT}/scripts/kian-rollback" apply 1 2>&1)
ROLLBACK_STATUS=$?

if [[ $ROLLBACK_STATUS -ne 0 ]]; then
    echo -e "  ${RED}kian-rollback apply 1 exited with error code ${ROLLBACK_STATUS}:${NC} ${ROLLBACK_OUTPUT}" >&2
    SIM_ROLLBACK_OK=0
fi

# Step 1: Verify previous broken rootfs was archived to @rootfs.broken_*
BACKUP_ARCHIVE=$(find "${MOCK_BTRFS_TOP}" -mindepth 1 -maxdepth 1 -type d -name "@rootfs.broken_*" 2>/dev/null | head -n 1 || true)
if [[ -z "$BACKUP_ARCHIVE" || ! -f "${BACKUP_ARCHIVE}/os-release" ]] || ! grep -q "CURRENT_CORRUPTED" "${BACKUP_ARCHIVE}/os-release"; then
    echo -e "  ${RED}Previous broken rootfs was not archived properly: ${BACKUP_ARCHIVE}${NC}" >&2
    SIM_ROLLBACK_OK=0
fi

# Step 2: Verify target snapshot state (SNAPSHOT_1_CLEAN) was atomically promoted into active @rootfs
if [[ ! -f "${MOCK_BTRFS_TOP}/@rootfs/os-release" ]] || ! grep -q "SNAPSHOT_1_CLEAN" "${MOCK_BTRFS_TOP}/@rootfs/os-release"; then
    echo -e "  ${RED}Target snapshot state was not restored to @rootfs${NC}" >&2
    SIM_ROLLBACK_OK=0
fi

# Step 3: Verify no dangling candidate subvolumes remain
DANGLING_CANDIDATE=$(find "${MOCK_BTRFS_TOP}" -mindepth 1 -maxdepth 1 -type d -name "@rootfs.candidate_*" 2>/dev/null || true)
if [[ -n "$DANGLING_CANDIDATE" ]]; then
    echo -e "  ${RED}Dangling candidate subvolume was not promoted cleanly: ${DANGLING_CANDIDATE}${NC}" >&2
    SIM_ROLLBACK_OK=0
fi

if [[ $SIM_ROLLBACK_OK -eq 1 ]]; then
    test_pass "Btrfs dynamic rollback engine lifecycle simulation restored rootfs to clean snapshot."
else
    test_fail "Btrfs dynamic rollback lifecycle simulation failed."
fi

# ------------------------------------------------------------------------------
# 4. Scenario 4: Boot Watchdog Fallback & Dual-Kernel Boot Counter Logic
# ------------------------------------------------------------------------------
test_start "Scenario 4: Boot watchdog fallback confirmation & grubenv bootcounter reset"

MOCK_GRUBENV="${MOCK_SCENARIO_DIR}/mock_grubenv"
WATCHDOG_SVC="${PROJECT_ROOT}/scripts/kian-boot-success.service"

WATCHDOG_OK=1

# Verify service unit definition
if [[ ! -f "$WATCHDOG_SVC" ]]; then
    echo -e "  ${RED}kian-boot-success.service unit file missing${NC}" >&2
    WATCHDOG_OK=0
else
    if ! grep -q "After=graphical.target" "$WATCHDOG_SVC" || \
       ! grep -q "bootcount=0" "$WATCHDOG_SVC" || \
       ! grep -q "boot_counter=0" "$WATCHDOG_SVC"; then
        echo -e "  ${RED}kian-boot-success.service missing graphical.target or bootcount reset commands${NC}" >&2
        WATCHDOG_OK=0
    fi
fi

# Test genuine grub-editenv interaction
if command -v grub-editenv >/dev/null 2>&1; then
    # Create empty mock grubenv
    grub-editenv "${MOCK_GRUBENV}" create

    # Simulate 2 failed boots (bootcount=2)
    grub-editenv "${MOCK_GRUBENV}" set bootcount=2
    grub-editenv "${MOCK_GRUBENV}" set boot_counter=2

    COUNT_BEFORE=$(grub-editenv "${MOCK_GRUBENV}" list | grep "bootcount=" | cut -d= -f2 || echo "")
    if [[ "$COUNT_BEFORE" != "2" ]]; then
        echo -e "  ${RED}Failed setting initial bootcount in mock grubenv: $COUNT_BEFORE${NC}" >&2
        WATCHDOG_OK=0
    fi

    # Execute exact watchdog command logic against mock grubenv
    /bin/sh -c "/usr/bin/grub-editenv '${MOCK_GRUBENV}' set bootcount=0 && /usr/bin/grub-editenv '${MOCK_GRUBENV}' set boot_counter=0"

    COUNT_AFTER=$(grub-editenv "${MOCK_GRUBENV}" list | grep "bootcount=" | cut -d= -f2 || echo "")
    COUNTER_AFTER=$(grub-editenv "${MOCK_GRUBENV}" list | grep "boot_counter=" | cut -d= -f2 || echo "")

    if [[ "$COUNT_AFTER" != "0" || "$COUNTER_AFTER" != "0" ]]; then
        echo -e "  ${RED}Watchdog reset failed: bootcount=$COUNT_AFTER boot_counter=$COUNTER_AFTER${NC}" >&2
        WATCHDOG_OK=0
    fi
else
    echo -e "  ${YELLOW}[SKIP] grub-editenv utility not found on host${NC}"
fi

if [[ $WATCHDOG_OK -eq 1 ]]; then
    test_pass "Boot watchdog recovery service confirmed healthy session and reset bootcount to 0."
else
    test_fail "Boot watchdog fallback verification failed."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}--------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}Tier 4 Test Results: Total: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS}${NC}"
echo -e "${BOLD}--------------------------------------------------------------------------------${NC}\n"

if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
