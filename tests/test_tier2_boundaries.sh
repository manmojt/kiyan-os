#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 E2E Test Suite - Tier 2: Boundary & Error-Handling Tests
# Path: tests/test_tier2_boundaries.sh
# Description: Verifies robustness against invalid arguments, missing resources,
#              corrupted snapshot metadata, non-btrfs environments, and edge cases.
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

# Ephemeral working directory for isolated boundary testing
TEST_TMP_DIR=$(mktemp -d /tmp/kian-tier2-test-XXXXXX)
cleanup() {
    rm -rf "${TEST_TMP_DIR}"
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
echo -e "${BOLD}${BLUE}   KIAN-OS v3 Test Suite: Tier 2 - Boundary & Error-Handling Tests              ${NC}"
echo -e "${BOLD}${BLUE}================================================================================${NC}\n"

SWITCHER="${PROJECT_ROOT}/desktop/triple-shell/kian-shell-switcher"
ROLLBACK="${PROJECT_ROOT}/scripts/kian-rollback"
APT_HOOK="${PROJECT_ROOT}/scripts/btrfs-apt-hook"
SNAPSHOTS_GRUB="${PROJECT_ROOT}/scripts/41_kian_snapshots"
POST_INSTALL="${PROJECT_ROOT}/installer/calamares/hooks/post-install-drivers-and-clean.sh"
BUILD_ALL="${PROJECT_ROOT}/build/build_all.sh"
VERIFY_ISO="${PROJECT_ROOT}/build/05_verify_iso.sh"

# ------------------------------------------------------------------------------
# 1. kian-shell-switcher: Informational Flags
# ------------------------------------------------------------------------------
test_start "kian-shell-switcher informational options (--help, -h, --version, -v, --list, -l)"

INFO_SUCCESS=1
for flag in "--help" "-h" "--version" "-v" "--list" "-l"; do
    if ! "$SWITCHER" "$flag" >/dev/null 2>&1; then
        echo -e "  ${RED}Flag failed:${NC} $flag" >&2
        INFO_SUCCESS=0
    fi
done

if [[ $INFO_SUCCESS -eq 1 ]]; then
    test_pass "kian-shell-switcher handles all informational flags with exit code 0."
else
    test_fail "One or more informational flags failed in kian-shell-switcher."
fi

# ------------------------------------------------------------------------------
# 2. kian-shell-switcher: Boundary & Invalid Argument Handling
# ------------------------------------------------------------------------------
test_start "kian-shell-switcher rejection of invalid and malformed parameters"

SWITCHER_INVALID_SUCCESS=1

# Subtest 2a: No arguments specified
if "$SWITCHER" >/dev/null 2>&1; then
    echo -e "  ${RED}Expected failure on no arguments, but got exit 0${NC}" >&2
    SWITCHER_INVALID_SUCCESS=0
fi

# Subtest 2b: Unknown flag
OUTPUT_UNKNOWN=$("$SWITCHER" --bogus-flag 2>&1 || true)
if ! echo "$OUTPUT_UNKNOWN" | grep -qi "Unknown option"; then
    echo -e "  ${RED}Unknown flag did not report expected error message:${NC} $OUTPUT_UNKNOWN" >&2
    SWITCHER_INVALID_SUCCESS=0
fi

# Subtest 2c: --theme flag without argument
OUTPUT_MISSING_THEME=$("$SWITCHER" --theme 2>&1 || true)
if ! echo "$OUTPUT_MISSING_THEME" | grep -qi "requires a shell name"; then
    echo -e "  ${RED}--theme missing arg did not report expected error:${NC} $OUTPUT_MISSING_THEME" >&2
    SWITCHER_INVALID_SUCCESS=0
fi

# Subtest 2d: Unknown shell name
OUTPUT_UNKNOWN_SHELL=$("$SWITCHER" --theme non_existent_shell_99 2>&1 || true)
if ! echo "$OUTPUT_UNKNOWN_SHELL" | grep -qi "Unknown shell target"; then
    echo -e "  ${RED}Unknown shell target did not report expected error:${NC} $OUTPUT_UNKNOWN_SHELL" >&2
    SWITCHER_INVALID_SUCCESS=0
fi

# Subtest 2e: Extra unexpected positional argument
OUTPUT_EXTRA=$("$SWITCHER" native unexpected_arg 2>&1 || true)
if ! echo "$OUTPUT_EXTRA" | grep -qi "Unexpected argument"; then
    echo -e "  ${RED}Unexpected extra argument did not report expected error:${NC} $OUTPUT_EXTRA" >&2
    SWITCHER_INVALID_SUCCESS=0
fi

if [[ $SWITCHER_INVALID_SUCCESS -eq 1 ]]; then
    test_pass "kian-shell-switcher strictly rejects all 5 invalid invocation patterns."
else
    test_fail "kian-shell-switcher failed one or more invalid argument boundary tests."
fi

# ------------------------------------------------------------------------------
# 3. kian-rollback: Command Dispatch & Unknown Command Handling
# ------------------------------------------------------------------------------
test_start "kian-rollback command dispatcher and unknown command rejection"

ROLLBACK_DISPATCH_OK=1

# Help commands
for hflag in "help" "--help" "-h"; do
    if ! "$ROLLBACK" "$hflag" >/dev/null 2>&1; then
        echo -e "  ${RED}kian-rollback help failed:${NC} $hflag" >&2
        ROLLBACK_DISPATCH_OK=0
    fi
done

# Unknown command
OUTPUT_RB_UNKNOWN=$("$ROLLBACK" invalid_action 2>&1 || true)
if ! echo "$OUTPUT_RB_UNKNOWN" | grep -qi "Unknown command: invalid_action"; then
    echo -e "  ${RED}kian-rollback invalid action did not report error:${NC} $OUTPUT_RB_UNKNOWN" >&2
    ROLLBACK_DISPATCH_OK=0
fi

if [[ $ROLLBACK_DISPATCH_OK -eq 1 ]]; then
    test_pass "kian-rollback correctly handles help and rejects unknown commands."
else
    test_fail "kian-rollback command dispatcher failed boundary validation."
fi

# ------------------------------------------------------------------------------
# 4. kian-rollback: Missing Arguments on apply and delete
# ------------------------------------------------------------------------------
test_start "kian-rollback missing target arguments for 'apply' and 'delete'"

ROLLBACK_ARGS_OK=1

# Non-root check
OUTPUT_APPLY_NONROOT=$("$ROLLBACK" apply 2>&1 || true)
if ! echo "$OUTPUT_APPLY_NONROOT" | grep -qi "requires root privileges"; then
    echo -e "  ${RED}kian-rollback non-root did not report root requirement${NC}" >&2
    ROLLBACK_ARGS_OK=0
fi

# With root privileges (sudo), verify missing target input checks
if sudo -n true 2>/dev/null; then
    OUTPUT_APPLY_NOARG=$(sudo "$ROLLBACK" apply 2>&1 || true)
    if ! echo "$OUTPUT_APPLY_NOARG" | grep -qi "Snapshot ID or snapshot directory name must be provided"; then
        echo -e "  ${RED}sudo kian-rollback apply without argument did not output expected error:${NC} $OUTPUT_APPLY_NOARG" >&2
        ROLLBACK_ARGS_OK=0
    fi

    OUTPUT_DEL_NOARG=$(sudo "$ROLLBACK" delete 2>&1 || true)
    if ! echo "$OUTPUT_DEL_NOARG" | grep -qi "Snapshot ID or snapshot directory name must be provided"; then
        echo -e "  ${RED}sudo kian-rollback delete without argument did not output expected error:${NC} $OUTPUT_DEL_NOARG" >&2
        ROLLBACK_ARGS_OK=0
    fi
fi

if [[ $ROLLBACK_ARGS_OK -eq 1 ]]; then
    test_pass "kian-rollback cleanly aborts with privilege enforcement and usage guidance."
else
    test_fail "kian-rollback failed missing argument checks."
fi

# ------------------------------------------------------------------------------
# 5. kian-rollback: Empty and Non-Existent Snapshots Directory Handling
# ------------------------------------------------------------------------------
test_start "kian-rollback list against non-existent and empty snapshot directories"

EMPTY_SNAPS_DIR="${TEST_TMP_DIR}/empty_snapshots"
mkdir -p "${EMPTY_SNAPS_DIR}"

ROLLBACK_EMPTY_OK=1

# Non-existent directory
OUTPUT_NONEXISTENT=$(KIAN_SNAPSHOTS_DIR="${TEST_TMP_DIR}/nonexistent_snaps" "$ROLLBACK" list 2>&1)
if ! echo "$OUTPUT_NONEXISTENT" | grep -qi "No snapshots directory found"; then
    echo -e "  ${RED}Expected 'No snapshots directory found', got:${NC} $OUTPUT_NONEXISTENT" >&2
    ROLLBACK_EMPTY_OK=0
fi

# Empty directory
OUTPUT_EMPTY=$(KIAN_SNAPSHOTS_DIR="${EMPTY_SNAPS_DIR}" "$ROLLBACK" list 2>&1)
if ! echo "$OUTPUT_EMPTY" | grep -qi "No registered Kian snapshots found" || \
   ! echo "$OUTPUT_EMPTY" | grep -qi "Total snapshots: 0"; then
    echo -e "  ${RED}Empty snapshots list did not report 0 snapshots:${NC} $OUTPUT_EMPTY" >&2
    ROLLBACK_EMPTY_OK=0
fi

if [[ $ROLLBACK_EMPTY_OK -eq 1 ]]; then
    test_pass "kian-rollback gracefully handles non-existent and empty snapshots directories."
else
    test_fail "kian-rollback list failed on empty/non-existent directory boundary tests."
fi

# ------------------------------------------------------------------------------
# 6. kian-rollback: Corrupted Snapshot Metadata Resilience
# ------------------------------------------------------------------------------
test_start "kian-rollback resilience against malformed and corrupted JSON metadata"

CORRUPT_SNAPS_DIR="${TEST_TMP_DIR}/corrupt_snapshots"
mkdir -p "${CORRUPT_SNAPS_DIR}/snap_99_corrupt"

# Case 1: Corrupted / Partial JSON file
cat << 'EOF' > "${CORRUPT_SNAPS_DIR}/snap_99_corrupt/.kian_snapshot_meta.json"
{
  "id": 99,
  "type": "corrupted_incomplete",
  "broken_syntax: [ missing bracket
EOF

CORRUPT_LIST_OUTPUT=$(KIAN_SNAPSHOTS_DIR="${CORRUPT_SNAPS_DIR}" "$ROLLBACK" list 2>&1)

if echo "$CORRUPT_LIST_OUTPUT" | grep -q "99" && \
   echo "$CORRUPT_LIST_OUTPUT" | grep -q "corrupted_incomplete" && \
   echo "$CORRUPT_LIST_OUTPUT" | grep -qi "Total snapshots: 1"; then
    test_pass "kian-rollback list extracted available attributes without crash on malformed JSON."
else
    test_fail "kian-rollback list failed or crashed on malformed snapshot metadata: $CORRUPT_LIST_OUTPUT"
fi

# ------------------------------------------------------------------------------
# 7. btrfs-apt-hook: Non-Btrfs Root and State File Boundaries
# ------------------------------------------------------------------------------
test_start "btrfs-apt-hook non-Btrfs environment and state file edge conditions"

APT_HOOK_OK=1

# Non-Btrfs root execution must exit 0 cleanly without error
if ! KIAN_MOCK_BTRFS=0 "$APT_HOOK" pre >/dev/null 2>&1; then
    echo -e "  ${RED}btrfs-apt-hook pre failed on non-btrfs root${NC}" >&2
    APT_HOOK_OK=0
fi
if ! KIAN_MOCK_BTRFS=0 "$APT_HOOK" post >/dev/null 2>&1; then
    echo -e "  ${RED}btrfs-apt-hook post failed on non-btrfs root${NC}" >&2
    APT_HOOK_OK=0
fi

# Post invoke with missing state file must exit 0 silently
MOCK_SNAPS_APT="${TEST_TMP_DIR}/apt_snaps"
mkdir -p "$MOCK_SNAPS_APT"
if ! KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="$MOCK_SNAPS_APT" KIAN_APT_STATE_FILE="${TEST_TMP_DIR}/no_such_state" "$APT_HOOK" post >/dev/null 2>&1; then
    echo -e "  ${RED}btrfs-apt-hook post failed when state file is missing${NC}" >&2
    APT_HOOK_OK=0
fi

# Post invoke with corrupted (non-numeric) state file must exit 0 silently
CORRUPT_STATE_FILE="${TEST_TMP_DIR}/corrupt_state.state"
echo "NOT_A_VALID_NUMBER" > "$CORRUPT_STATE_FILE"
if ! KIAN_MOCK_BTRFS=1 KIAN_SNAPSHOTS_DIR="$MOCK_SNAPS_APT" KIAN_APT_STATE_FILE="$CORRUPT_STATE_FILE" "$APT_HOOK" post >/dev/null 2>&1; then
    echo -e "  ${RED}btrfs-apt-hook post failed on non-numeric state file${NC}" >&2
    APT_HOOK_OK=0
fi

if [[ $APT_HOOK_OK -eq 1 ]]; then
    test_pass "btrfs-apt-hook safely handles non-Btrfs root, missing state, and corrupted state."
else
    test_fail "btrfs-apt-hook failed edge condition boundary checks."
fi

# ------------------------------------------------------------------------------
# 8. 41_kian_snapshots: Missing UUID and Empty Snapshots Directory
# ------------------------------------------------------------------------------
test_start "41_kian_snapshots boundary handling for missing UUID and empty snapshot pools"

GRUB_GEN_OK=1

# When no UUID detectable, must exit 0 with empty output
OUTPUT_NO_UUID=$(KIAN_TEST_FS_UUID="" KIAN_SNAPSHOTS_DIR="${TEST_TMP_DIR}/no_dir" "$SNAPSHOTS_GRUB" 2>&1 || true)
if [[ -n "$OUTPUT_NO_UUID" ]]; then
    echo -e "  ${RED}Expected empty output on missing UUID, got:${NC} $OUTPUT_NO_UUID" >&2
    GRUB_GEN_OK=0
fi

# When snapshots directory does not exist, must exit 0 with empty output
OUTPUT_NO_DIR=$(KIAN_TEST_FS_UUID="TEST-UUID-1234" KIAN_SNAPSHOTS_DIR="${TEST_TMP_DIR}/no_dir" "$SNAPSHOTS_GRUB" 2>&1 || true)
if [[ -n "$OUTPUT_NO_DIR" ]]; then
    echo -e "  ${RED}Expected empty output on missing snapshots dir, got:${NC} $OUTPUT_NO_DIR" >&2
    GRUB_GEN_OK=0
fi

# When snapshots directory is empty, must exit 0 with empty output
OUTPUT_EMPTY_SNAPS=$(KIAN_TEST_FS_UUID="TEST-UUID-1234" KIAN_SNAPSHOTS_DIR="${EMPTY_SNAPS_DIR}" "$SNAPSHOTS_GRUB" 2>&1 || true)
if [[ -n "$OUTPUT_EMPTY_SNAPS" ]]; then
    echo -e "  ${RED}Expected empty output on empty snapshots dir, got:${NC} $OUTPUT_EMPTY_SNAPS" >&2
    GRUB_GEN_OK=0
fi

if [[ $GRUB_GEN_OK -eq 1 ]]; then
    test_pass "41_kian_snapshots silently produces clean empty output on missing UUID or empty pool."
else
    test_fail "41_kian_snapshots failed boundary conditions."
fi

# ------------------------------------------------------------------------------
# 9. Calamares Post-Install Hook: Missing and Non-Existent Target Root
# ------------------------------------------------------------------------------
test_start "Calamares post-install hook rejection of missing or non-existent target root"

CALAMARES_HOOK_OK=1

# Missing target root with KIAN_TEST_MODE=0
OUTPUT_NO_ROOT=$(KIAN_TEST_MODE=0 ROOT="" "$POST_INSTALL" 2>&1 || true)
if ! echo "$OUTPUT_NO_ROOT" | grep -qi "Target root directory not provided"; then
    echo -e "  ${RED}Expected 'Target root directory not provided', got:${NC} $OUTPUT_NO_ROOT" >&2
    CALAMARES_HOOK_OK=0
fi

# Non-existent target root directory
OUTPUT_BAD_ROOT=$(KIAN_TEST_MODE=0 "$POST_INSTALL" "${TEST_TMP_DIR}/nonexistent_root_dir" 2>&1 || true)
if ! echo "$OUTPUT_BAD_ROOT" | grep -qi "does not exist"; then
    echo -e "  ${RED}Expected 'does not exist' on non-existent directory, got:${NC} $OUTPUT_BAD_ROOT" >&2
    CALAMARES_HOOK_OK=0
fi

if [[ $CALAMARES_HOOK_OK -eq 1 ]]; then
    test_pass "Calamares post-install hook validates target root existence before modifying files."
else
    test_fail "Calamares post-install hook failed root validation."
fi

# ------------------------------------------------------------------------------
# 10. Build System Scripts: CLI Help and Unknown Arguments
# ------------------------------------------------------------------------------
test_start "Build scripts standard options (--help validation and unknown flag rejection)"

BUILD_OPTS_OK=1

BUILD_SCRIPTS=(
    "${PROJECT_ROOT}/build/01_build_kernel.sh"
    "${PROJECT_ROOT}/build/02_bootstrap_rootfs.sh"
    "${PROJECT_ROOT}/build/03_customize_desktop.sh"
    "${PROJECT_ROOT}/build/04_build_iso.sh"
    "${PROJECT_ROOT}/build/05_verify_iso.sh"
    "${PROJECT_ROOT}/build/build_all.sh"
)

# Test --help and invalid option rejection across all build scripts
for bscript in "${BUILD_SCRIPTS[@]}"; do
    # Assert --help exits with 0
    if ! "$bscript" --help >/dev/null 2>&1; then
        echo -e "  ${RED}Build script failed --help (expected exit 0):${NC} $bscript" >&2
        BUILD_OPTS_OK=0
    fi

    # Assert unknown option exits with 1
    OUTPUT_UNKNOWN=$("$bscript" --completely-invalid-flag 2>&1 || true)
    set +e
    "$bscript" --completely-invalid-flag >/dev/null 2>&1
    RET_UNKNOWN=$?
    set -e
    if [[ $RET_UNKNOWN -ne 1 ]]; then
        echo -e "  ${RED}Build script $(basename "$bscript") did not exit with code 1 on invalid option (exit code: $RET_UNKNOWN)${NC}" >&2
        BUILD_OPTS_OK=0
    fi
    if ! echo "$OUTPUT_UNKNOWN" | grep -qi "Unknown option"; then
        echo -e "  ${RED}Build script $(basename "$bscript") did not report unknown option error:${NC} $OUTPUT_UNKNOWN" >&2
        BUILD_OPTS_OK=0
    fi
done

# Test non-existent ISO path rejection on 05_verify_iso.sh
OUTPUT_VERIFY_NONEXISTENT=$("$VERIFY_ISO" --iso "${TEST_TMP_DIR}/missing_image.iso" 2>&1 || true)
if ! echo "$OUTPUT_VERIFY_NONEXISTENT" | grep -qi "does not exist"; then
    echo -e "  ${RED}05_verify_iso.sh did not report non-existent ISO error:${NC} $OUTPUT_VERIFY_NONEXISTENT" >&2
    BUILD_OPTS_OK=0
fi

if [[ $BUILD_OPTS_OK -eq 1 ]]; then
    test_pass "All build scripts properly parse --help and reject unknown/missing arguments."
else
    test_fail "Build scripts failed CLI option validation."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}--------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}Tier 2 Test Results: Total: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS}${NC}"
echo -e "${BOLD}--------------------------------------------------------------------------------${NC}\n"

if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
