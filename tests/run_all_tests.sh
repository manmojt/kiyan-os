#!/usr/bin/env bash
# ==============================================================================
# KIAN-OS v3: Master E2E Test Suite Runner
# Path: tests/run_all_tests.sh
# Description: Executes all 4 test tiers (Features, Boundaries, Integration,
#              Scenarios) verifying all 29 features of the KIAN-OS v3 operating system.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI Color Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TARGET_TIER="all"
VERBOSE=0

show_usage() {
    cat <<EOF
KIAN-OS v3 Master Test Runner
Usage: $(basename "$0") [OPTIONS]

Options:
  --tier <1|2|3|4|all>  Execute specific test tier (default: all)
  -v, --verbose          Enable verbose output
  -h, --help             Display this help message and exit

Test Tiers:
  Tier 1: Feature coverage across kernel symbols, patch diffs, desktop files, fontconfig XML, calamares YAML, shell scripts syntax
  Tier 2: Boundary & error-handling tests for scripts, switcher invalid args, rollback missing snapshots, corrupted metadata
  Tier 3: Cross-feature integration tests: GRUB menu generation from mock btrfs snapshots, Calamares hook execution in mock root, fontconfig metric aliases
  Tier 4: Real-world workload tests: build pipeline dry-run execution, rollback lifecycle simulation, recovery watchdog logic

Examples:
  ./tests/run_all_tests.sh
  ./tests/run_all_tests.sh --tier 1
  ./tests/run_all_tests.sh --tier 3 -v
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            TARGET_TIER="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            show_usage
            ;;
    esac
done

START_TIME=$(date +%s)

echo -e "\n${BOLD}${CYAN}================================================================================${NC}"
echo -e "${BOLD}${CYAN}            KIAN-OS v3 End-to-End Test Suite Execution Engine                   ${NC}"
echo -e "${BOLD}${CYAN}================================================================================${NC}"
echo -e "Project Root: ${PROJECT_ROOT}"
echo -e "Target Scope: Tier ${TARGET_TIER}"
echo -e "Start Time:   $(date -u +"%Y-%m-%d %H:%M:%SZ")\n"

TIER1_SCRIPT="${SCRIPT_DIR}/test_tier1_features.sh"
TIER2_SCRIPT="${SCRIPT_DIR}/test_tier2_boundaries.sh"
TIER3_SCRIPT="${SCRIPT_DIR}/test_tier3_integration.sh"
TIER4_SCRIPT="${SCRIPT_DIR}/test_tier4_scenarios.sh"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

declare -A SUITE_STATUS
declare -A SUITE_TESTS
declare -A SUITE_PASSED
declare -A SUITE_FAILED

run_tier() {
    local tier_num="$1"
    local tier_name="$2"
    local script_path="$3"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo -e "${BOLD}${PURPLE}>>> Executing Tier ${tier_num}: ${tier_name} <<<${NC}"

    local output
    local exit_code=0
    set +e
    output=$("$script_path" 2>&1)
    exit_code=$?
    set -e

    echo "$output"

    # Extract test counts from script summary
    # Format: Tier X Test Results: Total: N | Passed: N | Failed: N
    local total_count
    local pass_count
    local fail_count
    total_count=$(echo "$output" | grep -o 'Total: [0-9]*' | tail -n 1 | cut -d' ' -f2 || echo 0)
    pass_count=$(echo "$output" | grep -o 'Passed: [0-9]*' | tail -n 1 | cut -d' ' -f2 || echo 0)
    fail_count=$(echo "$output" | grep -o 'Failed: [0-9]*' | tail -n 1 | cut -d' ' -f2 || echo 0)

    SUITE_TESTS["Tier ${tier_num}"]=${total_count:-0}
    SUITE_PASSED["Tier ${tier_num}"]=${pass_count:-0}
    SUITE_FAILED["Tier ${tier_num}"]=${fail_count:-0}

    if [[ $exit_code -eq 0 && ${fail_count:-0} -eq 0 ]]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        SUITE_STATUS["Tier ${tier_num}"]="PASSED"
        echo -e "${BOLD}${GREEN}>>> Tier ${tier_num} (${tier_name}) COMPLETED: SUCCESS <<<${NC}\n"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        SUITE_STATUS["Tier ${tier_num}"]="FAILED"
        echo -e "${BOLD}${RED}>>> Tier ${tier_num} (${tier_name}) COMPLETED: FAILURE (exit code ${exit_code}) <<<${NC}\n"
    fi
}

case "$TARGET_TIER" in
    1)
        run_tier 1 "Feature Coverage & Static Validation" "$TIER1_SCRIPT"
        ;;
    2)
        run_tier 2 "Boundary & Error-Handling Tests" "$TIER2_SCRIPT"
        ;;
    3)
        run_tier 3 "Cross-Feature Integration Tests" "$TIER3_SCRIPT"
        ;;
    4)
        run_tier 4 "Real-World Workload Scenarios" "$TIER4_SCRIPT"
        ;;
    all|ALL)
        run_tier 1 "Feature Coverage & Static Validation" "$TIER1_SCRIPT"
        run_tier 2 "Boundary & Error-Handling Tests" "$TIER2_SCRIPT"
        run_tier 3 "Cross-Feature Integration Tests" "$TIER3_SCRIPT"
        run_tier 4 "Real-World Workload Scenarios" "$TIER4_SCRIPT"
        ;;
    *)
        echo -e "${RED}Invalid tier specified: ${TARGET_TIER}. Choose from 1, 2, 3, 4, or all.${NC}" >&2
        exit 1
        ;;
esac

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

OVERALL_TOTAL=0
OVERALL_PASSED=0
OVERALL_FAILED=0

for key in "${!SUITE_TESTS[@]}"; do
    OVERALL_TOTAL=$((OVERALL_TOTAL + ${SUITE_TESTS[$key]:-0}))
    OVERALL_PASSED=$((OVERALL_PASSED + ${SUITE_PASSED[$key]:-0}))
    OVERALL_FAILED=$((OVERALL_FAILED + ${SUITE_FAILED[$key]:-0}))
done

echo -e "${BOLD}${CYAN}================================================================================${NC}"
echo -e "${BOLD}${CYAN}                     KIAN-OS v3 Test Execution Summary                          ${NC}"
echo -e "${BOLD}${CYAN}================================================================================${NC}"
printf "${BOLD}%-10s  %-40s  %-8s  %-8s  %-8s  %-8s${NC}\n" "TIER" "SUITE NAME" "STATUS" "TOTAL" "PASSED" "FAILED"
echo "--------------------------------------------------------------------------------"

for tier_idx in 1 2 3 4; do
    tier_label="Tier ${tier_idx}"
    if [[ -v SUITE_STATUS["$tier_label"] ]]; then
        st="${SUITE_STATUS[$tier_label]}"
        tot="${SUITE_TESTS[$tier_label]}"
        pas="${SUITE_PASSED[$tier_label]}"
        fai="${SUITE_FAILED[$tier_label]}"

        case "$tier_idx" in
            1) title="Feature Coverage & Static Validation" ;;
            2) title="Boundary & Error-Handling Tests" ;;
            3) title="Cross-Feature Integration Tests" ;;
            4) title="Real-World Workload Scenarios" ;;
        esac

        if [[ "$st" == "PASSED" ]]; then
            printf "%-10s  %-40s  ${GREEN}%-8s${NC}  %-8s  %-8s  %-8s\n" "$tier_label" "$title" "$st" "$tot" "$pas" "$fai"
        else
            printf "%-10s  %-40s  ${RED}%-8s${NC}  %-8s  %-8s  %-8s\n" "$tier_label" "$title" "$st" "$tot" "$pas" "$fai"
        fi
    fi
done

echo "--------------------------------------------------------------------------------"
printf "${BOLD}%-10s  %-40s  %-8s  %-8s  %-8s  %-8s${NC}\n" "OVERALL" "All Executed Tiers" \
    "$([[ $FAILED_SUITES -eq 0 ]] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")" \
    "$OVERALL_TOTAL" "$OVERALL_PASSED" "$OVERALL_FAILED"
echo -e "${BOLD}${CYAN}================================================================================${NC}"
echo -e "Execution Duration: ${DURATION}s"
echo -e "Completed At:       $(date -u +"%Y-%m-%d %H:%M:%SZ")\n"

if [[ $FAILED_SUITES -eq 0 && $OVERALL_FAILED -eq 0 ]]; then
    echo -e "${BOLD}${GREEN}>>> ALL KIAN-OS v3 TEST SUITES PASSED WITH 100% SUCCESS RATE! <<<${NC}\n"
    exit 0
else
    echo -e "${BOLD}${RED}>>> ONE OR MORE TEST SUITES FAILED! REVIEW LOGS ABOVE. <<<${NC}\n"
    exit 1
fi
