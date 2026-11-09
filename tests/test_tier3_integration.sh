#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 E2E Test Suite - Tier 3: Cross-Feature Integration Tests
# Path: tests/test_tier3_integration.sh
# Description: Cross-feature tests: GRUB snapshot menu generation, Calamares
#              pre/post install hook execution in mock root, fontconfig metric
#              aliases, Triple-Shell switching engine, and installer alignment.
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

# Isolated temp directory for mock environments
MOCK_BASE=$(mktemp -d /tmp/kian-tier3-integration-XXXXXX)
cleanup() {
    rm -rf "${MOCK_BASE}"
    rm -f /tmp/kian_hw_test_* /tmp/kian_hw_apple /tmp/kian_hw_apple_spi /tmp/kian_hw_surface
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
echo -e "${BOLD}${BLUE}   KIAN-OS v3 Test Suite: Tier 3 - Cross-Feature Integration Tests              ${NC}"
echo -e "${BOLD}${BLUE}================================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. GRUB Snapshot Menu Generation from Mock Btrfs Snapshots
# ------------------------------------------------------------------------------
test_start "GRUB snapshot menu generation with ephemeral OverlayFS from mock Btrfs repository"

MOCK_SNAPS="${MOCK_BASE}/mock_snapshots"
mkdir -p "${MOCK_SNAPS}/snap_1_pre"
mkdir -p "${MOCK_SNAPS}/snap_2_post"
mkdir -p "${MOCK_SNAPS}/snap_3_manual"

cat << 'EOF' > "${MOCK_SNAPS}/snap_1_pre/.kian_snapshot_meta.json"
{
  "id": 1,
  "type": "pre",
  "name": "snap_1_pre",
  "timestamp": "2026-11-09 10:00:00",
  "kernel": "6.8.0-31-kian-v3",
  "trigger": "apt-pre-invoke"
}
EOF

cat << 'EOF' > "${MOCK_SNAPS}/snap_2_post/.kian_snapshot_meta.json"
{
  "id": 2,
  "type": "post",
  "name": "snap_2_post",
  "timestamp": "2026-11-09 10:05:00",
  "kernel": "6.8.0-31-kian-v3",
  "trigger": "apt-post-invoke"
}
EOF

cat << 'EOF' > "${MOCK_SNAPS}/snap_3_manual/.kian_snapshot_meta.json"
{
  "id": 3,
  "type": "manual",
  "name": "snap_3_manual",
  "timestamp": "2026-11-09 12:00:00",
  "kernel": "6.8.0-31-kian-v3",
  "trigger": "manual-backup"
}
EOF

TEST_UUID="e7a4b892-1234-5678-9abc-def012345678"
GRUB_OUTPUT=$(KIAN_SNAPSHOTS_DIR="${MOCK_SNAPS}" KIAN_TEST_FS_UUID="${TEST_UUID}" "${PROJECT_ROOT}/scripts/41_kian_snapshots")

GRUB_CHECK_OK=1

# Check Submenu Header and Closure
if ! echo "$GRUB_OUTPUT" | grep -q 'submenu ">> KIAN-OS v3 Snapshot Rollback & Recovery <<"'; then
    echo -e "  ${RED}Missing recovery submenu header in GRUB output${NC}" >&2
    GRUB_CHECK_OK=0
fi

# Check UUID Search
if ! echo "$GRUB_OUTPUT" | grep -q "search --no-floppy --fs-uuid --set=root ${TEST_UUID}"; then
    echo -e "  ${RED}Missing UUID root search statement in GRUB output${NC}" >&2
    GRUB_CHECK_OK=0
fi

# Check Kernel Command Line OverlayFS Parameters
if ! echo "$GRUB_OUTPUT" | grep -q "kian.overlay=1" || \
   ! echo "$GRUB_OUTPUT" | grep -q "rootflags=subvol=@snapshots/snap_3_manual"; then
    echo -e "  ${RED}Missing Ephemeral OverlayFS command line parameters in GRUB output${NC}" >&2
    GRUB_CHECK_OK=0
fi

# Check Snapshot Metadata Rendering
if ! echo "$GRUB_OUTPUT" | grep -q "\[MANUAL\] snap_3_manual" || \
   ! echo "$GRUB_OUTPUT" | grep -q "\[POST\] snap_2_post" || \
   ! echo "$GRUB_OUTPUT" | grep -q "\[PRE\] snap_1_pre"; then
    echo -e "  ${RED}Snapshot metadata entries not properly formatted in GRUB menu${NC}" >&2
    GRUB_CHECK_OK=0
fi

if [[ $GRUB_CHECK_OK -eq 1 ]]; then
    test_pass "Dynamic GRUB menu generated cleanly with all 3 snapshots, UUID search, and OverlayFS flags."
else
    test_fail "GRUB snapshot menu generation failed integration verification."
fi

# ------------------------------------------------------------------------------
# 2. Calamares Post-Install Hook Execution in Mock Target Root
# ------------------------------------------------------------------------------
test_start "Calamares post-install driver configuration & live session sanitization in mock root"

MOCK_ROOT="${MOCK_BASE}/target_root"
mkdir -p "${MOCK_ROOT}/etc/sddm.conf.d" \
         "${MOCK_ROOT}/etc/systemd/system/sddm.service.d" \
         "${MOCK_ROOT}/etc/sudoers.d" \
         "${MOCK_ROOT}/etc/skel/Desktop" \
         "${MOCK_ROOT}/etc/skel/.config/autostart" \
         "${MOCK_ROOT}/home/kian/Desktop" \
         "${MOCK_ROOT}/home/kian/.config/autostart" \
         "${MOCK_ROOT}/root/Desktop" \
         "${MOCK_ROOT}/tmp" \
         "${MOCK_ROOT}/var/tmp" \
         "${MOCK_ROOT}/var/lib/apt/lists"

# Create mock live artifacts to purge
touch "${MOCK_ROOT}/etc/sddm.conf.d/autologin.conf" \
      "${MOCK_ROOT}/etc/systemd/system/sddm.service.d/autologin.conf" \
      "${MOCK_ROOT}/etc/sudoers.d/99-live-autologin" \
      "${MOCK_ROOT}/etc/sudoers.d/casper" \
      "${MOCK_ROOT}/etc/skel/Desktop/calamares.desktop" \
      "${MOCK_ROOT}/etc/skel/Desktop/install-kian.desktop" \
      "${MOCK_ROOT}/etc/skel/.config/autostart/calamares.desktop" \
      "${MOCK_ROOT}/home/kian/Desktop/calamares.desktop" \
      "${MOCK_ROOT}/home/kian/.config/autostart/calamares.desktop" \
      "${MOCK_ROOT}/root/Desktop/calamares.desktop" \
      "${MOCK_ROOT}/tmp/live_scratch.tmp" \
      "${MOCK_ROOT}/var/lib/apt/lists/archive_ubuntu.list"

# Simulate Apple Mac hardware detection flag
touch /tmp/kian_hw_apple /tmp/kian_hw_apple_spi

# Execute post-install hook in test mode
KIAN_TEST_MODE=1 "${PROJECT_ROOT}/installer/calamares/hooks/post-install-drivers-and-clean.sh" "${MOCK_ROOT}" >/dev/null 2>&1

POST_HOOK_OK=1

# Verify live autologin purged
if [[ -f "${MOCK_ROOT}/etc/sddm.conf.d/autologin.conf" ]] || \
   [[ -f "${MOCK_ROOT}/etc/systemd/system/sddm.service.d/autologin.conf" ]] || \
   [[ -f "${MOCK_ROOT}/etc/sudoers.d/99-live-autologin" ]] || \
   [[ -f "${MOCK_ROOT}/etc/sudoers.d/casper" ]]; then
    echo -e "  ${RED}Live autologin configurations were not removed by hook${NC}" >&2
    POST_HOOK_OK=0
fi

# Verify desktop shortcuts purged
if [[ -f "${MOCK_ROOT}/etc/skel/Desktop/calamares.desktop" ]] || \
   [[ -f "${MOCK_ROOT}/etc/skel/Desktop/install-kian.desktop" ]] || \
   [[ -f "${MOCK_ROOT}/home/kian/Desktop/calamares.desktop" ]] || \
   [[ -f "${MOCK_ROOT}/root/Desktop/calamares.desktop" ]]; then
    echo -e "  ${RED}Live desktop launchers were not removed by hook${NC}" >&2
    POST_HOOK_OK=0
fi

# Verify Apple Mac hardware driver configuration created
MAC_CONF="${MOCK_ROOT}/etc/modprobe.d/kian-apple-mac.conf"
if [[ ! -f "$MAC_CONF" ]]; then
    echo -e "  ${RED}Apple Mac modprobe configuration not created:${NC} $MAC_CONF" >&2
    POST_HOOK_OK=0
else
    if ! grep -q "swap_opt_cmd=1" "$MAC_CONF" || ! grep -q "touch_mode=2" "$MAC_CONF"; then
        echo -e "  ${RED}Apple Mac modprobe options invalid in:${NC} $MAC_CONF" >&2
        POST_HOOK_OK=0
    fi
fi

# Verify temporary files cleared
if [[ -f "${MOCK_ROOT}/tmp/live_scratch.tmp" ]] || [[ -f "${MOCK_ROOT}/var/lib/apt/lists/archive_ubuntu.list" ]]; then
    echo -e "  ${RED}Temporary directories not purged by hook${NC}" >&2
    POST_HOOK_OK=0
fi

if [[ $POST_HOOK_OK -eq 1 ]]; then
    test_pass "Calamares post-install hook cleanly purged live artifacts and staged Apple Mac drivers."
else
    test_fail "Calamares post-install hook failed mock root transformations."
fi

# ------------------------------------------------------------------------------
# 3. Calamares Pre-Install Hardware Probe Execution
# ------------------------------------------------------------------------------
test_start "Calamares pre-install hardware probe execution in test mode"

if KIAN_TEST_MODE=1 "${PROJECT_ROOT}/installer/calamares/hooks/pre-install-probe.sh" >/dev/null 2>&1; then
    test_pass "Calamares pre-install probe executed cleanly and logged system telemetry."
else
    test_fail "Calamares pre-install probe failed execution."
fi

# ------------------------------------------------------------------------------
# 4. Fontconfig Typography Metric Aliases & Subpixel Configuration Parsing
# ------------------------------------------------------------------------------
test_start "Fontconfig metric-compatible aliases and subpixel rasterization pipeline"

FONT_CONF="${PROJECT_ROOT}/desktop/fonts/50-kian-subpixel-typography.conf"

PYTHON_FONT_TEST=$(python3 -c "
import xml.etree.ElementTree as ET
import sys

tree = ET.parse('${FONT_CONF}')
root = tree.getroot()

# Required system font aliases
expected_aliases = [
    'system-ui',
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Segoe UI Variable',
    'SF Pro Display',
    'Ubuntu',
    'Cantarell'
]

found_aliases = set()
for match in root.findall('match'):
    if match.get('target') == 'pattern':
        test_elem = match.find('test')
        if test_elem is not None and test_elem.get('name') == 'family':
            str_elem = test_elem.find('string')
            if str_elem is not None and str_elem.text in expected_aliases:
                edit_elem = match.find('edit')
                if edit_elem is not None and edit_elem.get('name') == 'family':
                    strings = [s.text for s in edit_elem.findall('string')]
                    if 'Inter Display' in strings and 'Vazirmatn' in strings:
                        found_aliases.add(str_elem.text)

missing_aliases = set(expected_aliases) - found_aliases
if missing_aliases:
    print(f'Missing aliases: {missing_aliases}', file=sys.stderr)
    sys.exit(1)

# Check generic aliases
generic_found = {'sans-serif': False, 'serif': False, 'monospace': False}
for alias in root.findall('alias'):
    family = alias.find('family')
    prefer = alias.find('prefer')
    if family is not None and prefer is not None:
        fam_name = family.text
        if fam_name in generic_found:
            pref_families = [f.text for f in prefer.findall('family')]
            if fam_name == 'sans-serif' and pref_families[0] == 'Inter Display' and 'Vazirmatn' in pref_families:
                generic_found['sans-serif'] = True
            elif fam_name == 'serif' and 'Noto Serif' in pref_families and 'Vazirmatn' in pref_families:
                generic_found['serif'] = True
            elif fam_name == 'monospace' and 'Fira Code' in pref_families and 'Vazirmatn' in pref_families:
                generic_found['monospace'] = True

if not all(generic_found.values()):
    print(f'Missing generic aliases: {generic_found}', file=sys.stderr)
    sys.exit(2)

print('OK')
" 2>&1)

if [[ "$PYTHON_FONT_TEST" == "OK" ]]; then
    test_pass "Fontconfig metric aliases (8 system families -> Inter Display + Vazirmatn) verified."
else
    test_fail "Fontconfig typography alias assertions failed: $PYTHON_FONT_TEST"
fi

# ------------------------------------------------------------------------------
# 5. Triple-Shell Personality Hot-Swap Engine Integration
# ------------------------------------------------------------------------------
test_start "Triple-Shell zero-reboot hot-swap engine (native, fluent, aqua)"

MOCK_CONFIG="${MOCK_BASE}/mock_config"
SWITCHER="${PROJECT_ROOT}/desktop/triple-shell/kian-shell-switcher"

SHELL_SWAP_OK=1

# Test 5a: Switch to 'native'
XDG_CONFIG_HOME="${MOCK_CONFIG}" "$SWITCHER" --theme native >/dev/null 2>&1
CURRENT_NATIVE=$(cat "${MOCK_CONFIG}/kian/current-shell" 2>/dev/null || echo "")
KWIN_NATIVE=$(cat "${MOCK_CONFIG}/kwinrc" 2>/dev/null || echo "")
KVANTUM_NATIVE=$(cat "${MOCK_CONFIG}/Kvantum/kvantum.kvconfig" 2>/dev/null || echo "")
KDEGLOBALS_NATIVE=$(cat "${MOCK_CONFIG}/kdeglobals" 2>/dev/null || echo "")

if [[ "$CURRENT_NATIVE" != "kian-native" ]] || \
   ! echo "$KWIN_NATIVE" | grep -q "pluginName=org.kde.kdecoration2" || \
   ! echo "$KVANTUM_NATIVE" | grep -q "theme=KianGlass" || \
   ! echo "$KDEGLOBALS_NATIVE" | grep -q "ColorScheme=KianDarkCrystal"; then
    echo -e "  ${RED}Failed switching to native shell personality${NC}" >&2
    SHELL_SWAP_OK=0
fi

# Test 5b: Switch to 'fluent'
XDG_CONFIG_HOME="${MOCK_CONFIG}" "$SWITCHER" --theme fluent >/dev/null 2>&1
CURRENT_FLUENT=$(cat "${MOCK_CONFIG}/kian/current-shell" 2>/dev/null || echo "")
KWIN_FLUENT=$(cat "${MOCK_CONFIG}/kwinrc" 2>/dev/null || echo "")
KVANTUM_FLUENT=$(cat "${MOCK_CONFIG}/Kvantum/kvantum.kvconfig" 2>/dev/null || echo "")
KDEGLOBALS_FLUENT=$(cat "${MOCK_CONFIG}/kdeglobals" 2>/dev/null || echo "")

if [[ "$CURRENT_FLUENT" != "win11-fluent" ]] || \
   ! echo "$KWIN_FLUENT" | grep -q "pluginName=org.kde.breeze" || \
   ! echo "$KVANTUM_FLUENT" | grep -q "theme=FluentDark" || \
   ! echo "$KDEGLOBALS_FLUENT" | grep -q "ColorScheme=FluentDark"; then
    echo -e "  ${RED}Failed switching to fluent shell personality${NC}" >&2
    SHELL_SWAP_OK=0
fi

# Test 5c: Switch to 'aqua'
XDG_CONFIG_HOME="${MOCK_CONFIG}" "$SWITCHER" --theme aqua >/dev/null 2>&1
CURRENT_AQUA=$(cat "${MOCK_CONFIG}/kian/current-shell" 2>/dev/null || echo "")
KWIN_AQUA=$(cat "${MOCK_CONFIG}/kwinrc" 2>/dev/null || echo "")
KVANTUM_AQUA=$(cat "${MOCK_CONFIG}/Kvantum/kvantum.kvconfig" 2>/dev/null || echo "")
KDEGLOBALS_AQUA=$(cat "${MOCK_CONFIG}/kdeglobals" 2>/dev/null || echo "")

if [[ "$CURRENT_AQUA" != "macos-aqua" ]] || \
   ! echo "$KWIN_AQUA" | grep -q "pluginName=org.kde.kdecoration2" || \
   ! echo "$KVANTUM_AQUA" | grep -q "theme=KianAquaGlass" || \
   ! echo "$KDEGLOBALS_AQUA" | grep -q "ColorScheme=WhiteSurDark"; then
    echo -e "  ${RED}Failed switching to aqua shell personality${NC}" >&2
    SHELL_SWAP_OK=0
fi

# Test 5d: Query current shell via CLI
QUERY_SHELL=$(XDG_CONFIG_HOME="${MOCK_CONFIG}" "$SWITCHER" --current 2>/dev/null || echo "")
if [[ "$QUERY_SHELL" != "macos-aqua" ]]; then
    echo -e "  ${RED}kian-shell-switcher --current returned '$QUERY_SHELL', expected 'macos-aqua'${NC}" >&2
    SHELL_SWAP_OK=0
fi

if [[ $SHELL_SWAP_OK -eq 1 ]]; then
    test_pass "Triple-Shell switcher hot-swapped native, fluent, and aqua states cleanly with atomic state recording."
else
    test_fail "Triple-Shell personality hot-swap failed integration verification."
fi

# ------------------------------------------------------------------------------
# 6. Calamares Module Sequence & Btrfs Subvolume Alignment
# ------------------------------------------------------------------------------
test_start "Calamares module sequence ordering and Btrfs subvolume layout alignment"

SETTINGS_FILE="${PROJECT_ROOT}/installer/calamares/settings.conf"
PARTITION_FILE="${PROJECT_ROOT}/installer/calamares/modules/partition.conf"

PYTHON_CAL_TEST=$(python3 -c "
import yaml
import sys

with open('${SETTINGS_FILE}') as f:
    settings = yaml.safe_load(f)

with open('${PARTITION_FILE}') as f:
    partition = yaml.safe_load(f)

# 1. Verify Btrfs Partition Configuration
if partition.get('defaultFileSystemType') != 'btrfs':
    print('defaultFileSystemType is not btrfs', file=sys.stderr)
    sys.exit(1)

subvol_map = {sv['mountPoint']: sv['subvolume'] for sv in partition.get('btrfsSubvolumes', [])}
required_subvols = {
    '/': '/@rootfs',
    '/.snapshots': '/@snapshots',
    '/home': '/@home'
}
for mp, sv in required_subvols.items():
    if subvol_map.get(mp) != sv:
        print(f'Missing or mismatched subvolume for {mp}: {subvol_map.get(mp)} != {sv}', file=sys.stderr)
        sys.exit(2)

# 2. Verify Execution Sequence
exec_seq = None
for section in settings.get('sequence', []):
    if 'exec' in section:
        exec_seq = section['exec']
        break

if not exec_seq:
    print('No exec sequence found in Calamares settings.conf', file=sys.stderr)
    sys.exit(3)

# Assert ordering:
# kian_preinstall MUST be before partition
# partition MUST be before mount and unpackfs
# packages MUST be before kian_driver_and_clean
# kian_driver_and_clean MUST be before initramfscfg and bootloader
try:
    idx_preinstall = exec_seq.index('shellprocess@kian_preinstall')
    idx_partition = exec_seq.index('partition')
    idx_mount = exec_seq.index('mount')
    idx_unpack = exec_seq.index('unpackfs')
    idx_packages = exec_seq.index('packages')
    idx_driver = exec_seq.index('shellprocess@kian_driver_and_clean')
    idx_initramfs = exec_seq.index('initramfscfg')
    idx_bootloader = exec_seq.index('bootloader')

    assert idx_preinstall < idx_partition, 'preinstall must precede partition'
    assert idx_partition < idx_mount, 'partition must precede mount'
    assert idx_mount < idx_unpack, 'mount must precede unpackfs'
    assert idx_packages < idx_driver, 'packages must precede driver_and_clean'
    assert idx_driver < idx_initramfs, 'driver_and_clean must precede initramfscfg'
    assert idx_initramfs < idx_bootloader, 'initramfscfg must precede bootloader'
except (ValueError, AssertionError) as e:
    print(f'Execution sequence order violation: {e}', file=sys.stderr)
    sys.exit(4)

print('OK')
" 2>&1)

if [[ "$PYTHON_CAL_TEST" == "OK" ]]; then
    test_pass "Calamares execution sequence and Btrfs subvolume mapping strictly aligned."
else
    test_fail "Calamares sequence alignment verification failed: $PYTHON_CAL_TEST"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}--------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}Tier 3 Test Results: Total: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS}${NC}"
echo -e "${BOLD}--------------------------------------------------------------------------------${NC}\n"

if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
