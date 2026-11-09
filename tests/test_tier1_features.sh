#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3 E2E Test Suite - Tier 1: Feature Coverage & Static Validation
# Path: tests/test_tier1_features.sh
# Description: Validates shell syntax, kernel configs, patch diff headers,
#              desktop files, fontconfig XML, Calamares YAML, and specifications.
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
echo -e "${BOLD}${BLUE}   KIAN-OS v3 Test Suite: Tier 1 - Feature Coverage & Static Validation         ${NC}"
echo -e "${BOLD}${BLUE}================================================================================${NC}\n"

# ------------------------------------------------------------------------------
# 1. Shell Script Syntax Validation (bash -n)
# ------------------------------------------------------------------------------
test_start "Shell script syntax validation (bash -n) across all project scripts"

SHELL_SCRIPTS=(
    "${PROJECT_ROOT}/build/common.sh"
    "${PROJECT_ROOT}/build/01_build_kernel.sh"
    "${PROJECT_ROOT}/build/02_bootstrap_rootfs.sh"
    "${PROJECT_ROOT}/build/03_customize_desktop.sh"
    "${PROJECT_ROOT}/build/04_build_iso.sh"
    "${PROJECT_ROOT}/build/05_verify_iso.sh"
    "${PROJECT_ROOT}/build/build_all.sh"
    "${PROJECT_ROOT}/scripts/kian-rollback"
    "${PROJECT_ROOT}/scripts/btrfs-apt-hook"
    "${PROJECT_ROOT}/scripts/41_kian_snapshots"
    "${PROJECT_ROOT}/installer/calamares/hooks/pre-install-probe.sh"
    "${PROJECT_ROOT}/installer/calamares/hooks/post-install-drivers-and-clean.sh"
    "${PROJECT_ROOT}/desktop/triple-shell/kian-shell-switcher"
)

SYNTAX_ERRORS=0
for script in "${SHELL_SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
        echo -e "  ${RED}Missing script:${NC} $script" >&2
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    elif ! bash -n "$script" 2>&1; then
        echo -e "  ${RED}Syntax error in:${NC} $script" >&2
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done

if [[ $SYNTAX_ERRORS -eq 0 ]]; then
    test_pass "All ${#SHELL_SCRIPTS[@]} shell scripts validated with bash -n clean syntax."
else
    test_fail "Detected $SYNTAX_ERRORS syntax errors in shell scripts."
fi

# ------------------------------------------------------------------------------
# 2. Kernel Configuration Symbol Assertions (linux-kian v3 .config)
# ------------------------------------------------------------------------------
test_start "Kernel configuration symbols in config-6.8-kian-v3"
KERNEL_CONFIG="${PROJECT_ROOT}/kernel/config-6.8-kian-v3"

if [[ ! -f "$KERNEL_CONFIG" ]]; then
    test_fail "Kernel config file not found: $KERNEL_CONFIG"
else
    REQUIRED_SYMBOLS=(
        "CONFIG_HZ_1000=y"
        "CONFIG_SCHED_BORE=y"
        "CONFIG_PREEMPT=y"
        "CONFIG_PREEMPT_DYNAMIC=y"
        "CONFIG_NTSYNC=m"
        "CONFIG_BINFMT_MISC=y"
        "CONFIG_SYNC_FILE=y"
        "CONFIG_SURFACE_PLATFORMS=y"
        "CONFIG_SURFACE_AGGREGATOR=m"
        "CONFIG_SURFACE_HID=m"
        "CONFIG_INTEL_IPU6=m"
        "CONFIG_INTEL_IPU6_ISYS=m"
        "CONFIG_KEYBOARD_APPLESPI=m"
        "CONFIG_B43=m"
        "CONFIG_BTRFS_FS=y"
        "CONFIG_BTRFS_FS_POSIX_ACL=y"
        "CONFIG_TCP_CONG_BBR=y"
        "CONFIG_OVERLAY_FS=y"
    )

    MISSING_SYMBOLS=0
    for sym in "${REQUIRED_SYMBOLS[@]}"; do
        if ! grep -Fxq "$sym" "$KERNEL_CONFIG"; then
            echo -e "  ${RED}Missing required kernel symbol:${NC} $sym" >&2
            MISSING_SYMBOLS=$((MISSING_SYMBOLS + 1))
        fi
    done

    MUTEX_UNSET_SYMBOLS=(
        "# CONFIG_HZ_250 is not set"
        "# CONFIG_PREEMPT_NONE is not set"
        "# CONFIG_DEFAULT_CUBIC is not set"
    )
    for sym in "${MUTEX_UNSET_SYMBOLS[@]}"; do
        if ! grep -Fxq "$sym" "$KERNEL_CONFIG"; then
            echo -e "  ${RED}Mutually exclusive symbol not properly unset:${NC} $sym" >&2
            MISSING_SYMBOLS=$((MISSING_SYMBOLS + 1))
        fi
    done

    if [[ $MISSING_SYMBOLS -eq 0 ]]; then
        test_pass "All ${#REQUIRED_SYMBOLS[@]} essential kernel symbols verified in config-6.8-kian-v3."
    else
        test_fail "Missing $MISSING_SYMBOLS kernel configuration symbols."
    fi
fi

# ------------------------------------------------------------------------------
# 3. Kernel Patches Diff & Header Integrity
# ------------------------------------------------------------------------------
test_start "Kernel patches header and unified diff validation in kernel/patches/"
PATCHES_DIR="${PROJECT_ROOT}/kernel/patches"

EXPECTED_PATCHES=(
    "0001-sched-bore-noble.patch"
    "0002-drivers-misc-ntsync.patch"
    "0003-drivers-media-ipu6-dphy-settle.patch"
    "0004-drivers-media-ov5693-acpi-hid.patch"
    "0005-net-ipv4-tcp-bbrv3.patch"
)

PATCH_ERRORS=0
for patch_name in "${EXPECTED_PATCHES[@]}"; do
    patch_path="${PATCHES_DIR}/${patch_name}"
    if [[ ! -f "$patch_path" ]]; then
        echo -e "  ${RED}Patch not found:${NC} $patch_path" >&2
        PATCH_ERRORS=$((PATCH_ERRORS + 1))
        continue
    fi

    # Check for git/unified patch markers
    if ! grep -q -E "^(From |diff --git|--- |\+\+\+ )" "$patch_path"; then
        echo -e "  ${RED}Invalid patch structure:${NC} $patch_name" >&2
        PATCH_ERRORS=$((PATCH_ERRORS + 1))
    fi

    # Check for Signed-off-by
    if ! grep -q "Signed-off-by:" "$patch_path"; then
        echo -e "  ${RED}Missing Signed-off-by in patch:${NC} $patch_name" >&2
        PATCH_ERRORS=$((PATCH_ERRORS + 1))
    fi

    # Check that new file additions specify new file mode and /dev/null
    if [[ "$patch_name" == "0002-drivers-misc-ntsync.patch" ]]; then
        if ! grep -q "new file mode 100644" "$patch_path" || ! grep -q -- "--- /dev/null" "$patch_path"; then
            echo -e "  ${RED}Patch 0002 missing git new file mode or /dev/null headers:${NC} $patch_name" >&2
            PATCH_ERRORS=$((PATCH_ERRORS + 1))
        fi
    fi
done

if [[ $PATCH_ERRORS -eq 0 ]]; then
    test_pass "All ${#EXPECTED_PATCHES[@]} kernel patches validated with git patch headers and signatures."
else
    test_fail "Detected $PATCH_ERRORS patch integrity failures."
fi

# ------------------------------------------------------------------------------
# 4. Pure Wayland SDDM & Systemd Service Files
# ------------------------------------------------------------------------------
test_start "Pure Wayland SDDM and systemd desktop service configuration"

SDDM_CONF="${PROJECT_ROOT}/desktop/sddm/sddm.conf.d/wayland.conf"
LOCALSEND_SVC="${PROJECT_ROOT}/desktop/sync/localsend.service"
KDECONNECT_SVC="${PROJECT_ROOT}/desktop/sync/kdeconnect-clipboard.service"
WATCHDOG_SVC="${PROJECT_ROOT}/scripts/kian-boot-success.service"

DESKTOP_CONF_ERRORS=0

# SDDM Assertions
if [[ ! -f "$SDDM_CONF" ]]; then
    echo -e "  ${RED}SDDM config missing:${NC} $SDDM_CONF" >&2
    DESKTOP_CONF_ERRORS=$((DESKTOP_CONF_ERRORS + 1))
else
    if ! grep -q "DisplayServer=wayland" "$SDDM_CONF" || \
       ! grep -q "ServerPath=/bin/false" "$SDDM_CONF" || \
       ! grep -q "CompositorCommand=kwin_wayland" "$SDDM_CONF" || \
       ! grep -q "Session=plasmawayland.desktop" "$SDDM_CONF"; then
        echo -e "  ${RED}SDDM Wayland enforcement parameters missing in:${NC} $SDDM_CONF" >&2
        DESKTOP_CONF_ERRORS=$((DESKTOP_CONF_ERRORS + 1))
    fi
fi

# LocalSend & KDE Connect Services
if [[ ! -f "$LOCALSEND_SVC" ]] || ! grep -q "ExecStart=/usr/bin/localsend" "$LOCALSEND_SVC"; then
    echo -e "  ${RED}LocalSend systemd service missing or invalid:${NC} $LOCALSEND_SVC" >&2
    DESKTOP_CONF_ERRORS=$((DESKTOP_CONF_ERRORS + 1))
fi

if [[ ! -f "$KDECONNECT_SVC" ]] || ! grep -q "ExecStart=/usr/libexec/kdeconnectd" "$KDECONNECT_SVC"; then
    echo -e "  ${RED}KDE Connect systemd service missing or invalid:${NC} $KDECONNECT_SVC" >&2
    DESKTOP_CONF_ERRORS=$((DESKTOP_CONF_ERRORS + 1))
fi

# Watchdog Service
if [[ ! -f "$WATCHDOG_SVC" ]] || ! grep -q "grub-editenv" "$WATCHDOG_SVC" || ! grep -q "bootcount=0" "$WATCHDOG_SVC"; then
    echo -e "  ${RED}Watchdog service missing or invalid:${NC} $WATCHDOG_SVC" >&2
    DESKTOP_CONF_ERRORS=$((DESKTOP_CONF_ERRORS + 1))
fi

if [[ $DESKTOP_CONF_ERRORS -eq 0 ]]; then
    test_pass "SDDM Wayland, LocalSend, KDE Connect, and Watchdog service definitions verified."
else
    test_fail "Detected $DESKTOP_CONF_ERRORS errors in desktop and service configurations."
fi

# ------------------------------------------------------------------------------
# 5. Triple-Shell Layouts & Kvantum Themes
# ------------------------------------------------------------------------------
test_start "Triple-Shell layouts and glassmorphic Kvantum styling templates"

LAYOUTS_DIR="${PROJECT_ROOT}/desktop/triple-shell/layouts"
KVANTUM_THEME="${PROJECT_ROOT}/desktop/triple-shell/kvantum/KianGlass/KianGlass.kvconfig"

SHELL_ERRORS=0
REQUIRED_LAYOUTS=("kian-native.js" "windows-fluent.js" "macos-aqua.js")

for layout in "${REQUIRED_LAYOUTS[@]}"; do
    layout_file="${LAYOUTS_DIR}/${layout}"
    if [[ ! -s "$layout_file" ]]; then
        echo -e "  ${RED}Missing or empty shell layout script:${NC} $layout" >&2
        SHELL_ERRORS=$((SHELL_ERRORS + 1))
    fi
done

if [[ ! -s "$KVANTUM_THEME" ]]; then
    echo -e "  ${RED}Missing or empty Kvantum theme config:${NC} $KVANTUM_THEME" >&2
    SHELL_ERRORS=$((SHELL_ERRORS + 1))
else
    if ! grep -q -E "\[%?General\]" "$KVANTUM_THEME" || ! grep -q "blur" "$KVANTUM_THEME"; then
        echo -e "  ${RED}Kvantum theme missing required blur parameters:${NC} $KVANTUM_THEME" >&2
        SHELL_ERRORS=$((SHELL_ERRORS + 1))
    fi
fi

if [[ $SHELL_ERRORS -eq 0 ]]; then
    test_pass "Triple-Shell layout scripts (native, fluent, aqua) and Kvantum theme validated."
else
    test_fail "Detected $SHELL_ERRORS errors in Triple-Shell assets."
fi

# ------------------------------------------------------------------------------
# 6. Fontconfig XML Validation & Metric Aliases
# ------------------------------------------------------------------------------
test_start "Fontconfig XML structure and metric aliases (Inter Display & Vazirmatn)"

FONTCONFIG_FILE="${PROJECT_ROOT}/desktop/fonts/50-kian-subpixel-typography.conf"

if [[ ! -f "$FONTCONFIG_FILE" ]]; then
    test_fail "Fontconfig file not found: $FONTCONFIG_FILE"
elif ! xmllint --noout "$FONTCONFIG_FILE" 2>&1; then
    test_fail "Fontconfig file failed xmllint XML syntax validation."
else
    # Verify typography definitions
    if grep -q "Inter Display" "$FONTCONFIG_FILE" && \
       grep -q "Vazirmatn" "$FONTCONFIG_FILE" && \
       grep -q "lcddefault" "$FONTCONFIG_FILE" && \
       grep -q "hintslight" "$FONTCONFIG_FILE"; then
        test_pass "Fontconfig XML validated with Inter Display, Vazirmatn, and subpixel LCD filters."
    else
        test_fail "Fontconfig XML missing required typography rules."
    fi
fi

# ------------------------------------------------------------------------------
# 7. Calamares YAML Configuration Validation
# ------------------------------------------------------------------------------
test_start "Calamares YAML module syntax and partitioning definitions"

CALAMARES_DIR="${PROJECT_ROOT}/installer/calamares"
CALAMARES_FILES=(
    "${CALAMARES_DIR}/settings.conf"
    "${CALAMARES_DIR}/modules/partition.conf"
    "${CALAMARES_DIR}/modules/packages.conf"
    "${CALAMARES_DIR}/modules/unpackfs.conf"
    "${CALAMARES_DIR}/modules/shellprocess_kian_preinstall.conf"
    "${CALAMARES_DIR}/modules/shellprocess_kian_drivers_and_clean.conf"
)

YAML_ERRORS=0
for yaml_file in "${CALAMARES_FILES[@]}"; do
    if [[ ! -f "$yaml_file" ]]; then
        echo -e "  ${RED}Missing Calamares config file:${NC} $yaml_file" >&2
        YAML_ERRORS=$((YAML_ERRORS + 1))
    elif ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>&1; then
        echo -e "  ${RED}Invalid YAML syntax in:${NC} $yaml_file" >&2
        YAML_ERRORS=$((YAML_ERRORS + 1))
    fi
done

# Partitioning specific check
PARTITION_CONF="${CALAMARES_DIR}/modules/partition.conf"
if ! grep -q 'defaultFileSystemType: "btrfs"' "$PARTITION_CONF" || \
   ! grep -q '/@rootfs' "$PARTITION_CONF" || \
   ! grep -q '/@snapshots' "$PARTITION_CONF"; then
    echo -e "  ${RED}Calamares partition.conf missing Btrfs flat subvolume mappings.${NC}" >&2
    YAML_ERRORS=$((YAML_ERRORS + 1))
fi

if [[ $YAML_ERRORS -eq 0 ]]; then
    test_pass "All ${#CALAMARES_FILES[@]} Calamares configurations validated with Btrfs subvolume layout."
else
    test_fail "Detected $YAML_ERRORS errors in Calamares configurations."
fi

# ------------------------------------------------------------------------------
# 8. Master Technical Specifications & Compatibility Matrix
# ------------------------------------------------------------------------------
test_start "Technical specifications and kernel patch compatibility matrix"

SPEC_DOC="${PROJECT_ROOT}/docs/KIAN_OS_V3_PRODUCTION_SPECIFICATION.md"
MATRIX_DOC="${PROJECT_ROOT}/kernel/PATCH_COMPATIBILITY_MATRIX.md"

DOC_ERRORS=0
if [[ ! -s "$SPEC_DOC" ]]; then
    echo -e "  ${RED}Master specification document missing or empty:${NC} $SPEC_DOC" >&2
    DOC_ERRORS=$((DOC_ERRORS + 1))
else
    # Check for coverage of all core subsystems
    for keyword in "BORE" "ntsync" "futex_waitv" "Surface" "IPU6" "Apple" "BBRv3" "Btrfs" "Wayland" "Triple-Shell"; do
        if ! grep -qi "$keyword" "$SPEC_DOC"; then
            echo -e "  ${RED}Specification missing keyword coverage:${NC} $keyword" >&2
            DOC_ERRORS=$((DOC_ERRORS + 1))
        fi
    done
fi

if [[ ! -s "$MATRIX_DOC" ]]; then
    echo -e "  ${RED}Compatibility matrix document missing or empty:${NC} $MATRIX_DOC" >&2
    DOC_ERRORS=$((DOC_ERRORS + 1))
else
    if ! grep -q "Linux 6.8" "$MATRIX_DOC" || ! grep -q "Linux 6.11" "$MATRIX_DOC" || ! grep -q "update_curr" "$MATRIX_DOC"; then
        echo -e "  ${RED}Compatibility matrix missing 6.8/6.11 or conflict resolution details.${NC}" >&2
        DOC_ERRORS=$((DOC_ERRORS + 1))
    fi
fi

if [[ $DOC_ERRORS -eq 0 ]]; then
    test_pass "Master production specification and compatibility matrix verified."
else
    test_fail "Detected $DOC_ERRORS documentation deficiencies."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}--------------------------------------------------------------------------------${NC}"
echo -e "${BOLD}Tier 1 Test Results: Total: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS}${NC}"
echo -e "${BOLD}--------------------------------------------------------------------------------${NC}\n"

if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
