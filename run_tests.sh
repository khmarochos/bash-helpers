#!/usr/bin/env bash

# run_tests.sh - Test runner for bash-helpers
#
# Description:  
#   Runs all tests for the bash-helpers library with proper reporting.
#   Supports running individual test suites or all tests.
#
# Usage:
#   ./run_tests.sh                    # Run all tests
#   ./run_tests.sh log                # Run only log module tests
#   ./run_tests.sh lifecycle          # Run only lifecycle module tests
#   ./run_tests.sh config             # Run only config module tests
#   ./run_tests.sh integration        # Run only integration tests
#   ./run_tests.sh --list             # List available test suites
#   ./run_tests.sh --help             # Show help

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
TESTS_DIR="${SCRIPT_DIR}/tests"

# Available test suites
declare -A TEST_SUITES=(
    ["log"]="test_log.sh"
    ["lifecycle"]="test_lifecycle.sh"
    ["config"]="test_config.sh"
    ["integration"]="test_integration.sh"
)

# Test results tracking
declare -i TOTAL_SUITES=0
declare -i PASSED_SUITES=0
declare -i FAILED_SUITES=0
declare -a FAILED_SUITE_NAMES=()

# show_help() - Display usage information
show_help() {
    cat << EOF
Bash Helpers Test Runner

USAGE:
    ${0##*/} [OPTIONS] [TEST_SUITE]

OPTIONS:
    --help              Show this help message
    --list              List available test suites
    --verbose           Enable verbose output

TEST SUITES:
    log                 Test the logging module (lib/log.sh)
    lifecycle           Test the lifecycle module (lib/lifecycle.sh)  
    config              Test the configuration module (lib/config.sh)
    integration         Test module integration and workflows
    
    If no test suite is specified, all tests will be run.

EXAMPLES:
    ${0##*/}                    # Run all tests
    ${0##*/} log                # Run only logging tests
    ${0##*/} config lifecycle   # Run config and lifecycle tests
    ${0##*/} --list             # Show available test suites

EXIT CODES:
    0                   All tests passed
    1                   One or more tests failed
    2                   Invalid arguments or setup error
EOF
}

# list_test_suites() - List available test suites
list_test_suites() {
    echo "Available test suites:"
    echo
    for suite in "${!TEST_SUITES[@]}"; do
        local file="${TEST_SUITES[${suite}]}"
        if [[ -f "${TESTS_DIR}/${file}" ]]; then
            echo "  ${suite}        ${file}"
        else
            echo "  ${suite}        ${file} (MISSING)"
        fi
    done
}

# run_test_suite() - Run a single test suite
run_test_suite() {
    local suite_name="${1}"
    local test_file="${TEST_SUITES[${suite_name}]:-}"
    
    if [[ -z "${test_file}" ]]; then
        echo "ERROR: Unknown test suite: ${suite_name}" >&2
        return 1
    fi
    
    local test_path="${TESTS_DIR}/${test_file}"
    if [[ ! -f "${test_path}" ]]; then
        echo "ERROR: Test file not found: ${test_path}" >&2
        return 1
    fi
    
    echo "Running ${suite_name} tests..."
    echo "==============================="
    
    ((TOTAL_SUITES++))
    
    if bash "${test_path}"; then
        echo
        echo "✓ ${suite_name} tests PASSED"
        ((PASSED_SUITES++))
        return 0
    else
        echo
        echo "✗ ${suite_name} tests FAILED"
        ((FAILED_SUITES++))
        FAILED_SUITE_NAMES+=("${suite_name}")
        return 1
    fi
}

# run_all_tests() - Run all available test suites
run_all_tests() {
    local suite_failed=0
    
    echo "Running all bash-helpers tests..."
    echo "================================="
    echo
    
    # Check that test framework exists
    if [[ ! -f "${TESTS_DIR}/test_framework.sh" ]]; then
        echo "ERROR: Test framework not found: ${TESTS_DIR}/test_framework.sh" >&2
        return 2
    fi
    
    # Run each test suite
    for suite in log lifecycle config integration; do
        if ! run_test_suite "${suite}"; then
            suite_failed=1
        fi
        echo
    done
    
    # Print summary
    echo "========================================="
    echo "TEST SUMMARY"
    echo "========================================="
    echo "Total test suites: ${TOTAL_SUITES}"
    echo "Passed: ${PASSED_SUITES}"
    echo "Failed: ${FAILED_SUITES}"
    
    if [[ ${FAILED_SUITES} -gt 0 ]]; then
        echo
        echo "Failed test suites:"
        for failed_suite in "${FAILED_SUITE_NAMES[@]}"; do
            echo "  - ${failed_suite}"
        done
        echo
        return 1
    else
        echo
        echo "All test suites passed!"
        return 0
    fi
}

# validate_environment() - Check that required tools are available
validate_environment() {
    local missing_tools=()
    
    # Check for required commands
    if ! command -v mktemp >/dev/null 2>&1; then
        missing_tools+=("mktemp")
    fi
    
    if ! command -v readlink >/dev/null 2>&1; then
        missing_tools+=("readlink")
    fi
    
    # Check that lib directory exists
    if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
        echo "ERROR: lib directory not found: ${SCRIPT_DIR}/lib" >&2
        return 1
    fi
    
    # Check that required modules exist
    local missing_modules=()
    for module in log.sh lifecycle.sh config.sh; do
        if [[ ! -f "${SCRIPT_DIR}/lib/${module}" ]]; then
            missing_modules+=("${module}")
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        echo "ERROR: Missing required modules:" >&2
        for module in "${missing_modules[@]}"; do
            echo "  - lib/${module}" >&2
        done
        return 1
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools:" >&2
        for tool in "${missing_tools[@]}"; do
            echo "  - ${tool}" >&2
        done
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    local run_specific_tests=()
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --help|-h)
                show_help
                exit 0
                ;;
            --list)
                list_test_suites
                exit 0
                ;;
            --verbose|-v)
                set -x
                shift
                ;;
            --*)
                echo "ERROR: Unknown option: ${1}" >&2
                echo "Use --help for usage information." >&2
                exit 2
                ;;
            *)
                # Check if it's a valid test suite
                if [[ -n "${TEST_SUITES[${1}]:-}" ]]; then
                    run_specific_tests+=("${1}")
                else
                    echo "ERROR: Unknown test suite: ${1}" >&2
                    echo "Use --list to see available test suites." >&2
                    exit 2
                fi
                shift
                ;;
        esac
    done
    
    # Validate environment
    if ! validate_environment; then
        exit 2
    fi
    
    # Determine what to run
    if [[ ${#run_specific_tests[@]} -eq 0 ]]; then
        # Run all tests
        run_all_tests
    else
        # Run specific test suites
        local any_failed=0
        
        for suite in "${run_specific_tests[@]}"; do
            if ! run_test_suite "${suite}"; then
                any_failed=1
            fi
            echo
        done
        
        # Print summary for multiple specific tests
        if [[ ${#run_specific_tests[@]} -gt 1 ]]; then
            echo "Summary for selected test suites:"
            echo "Passed: ${PASSED_SUITES}/${TOTAL_SUITES}"
            if [[ ${FAILED_SUITES} -gt 0 ]]; then
                echo "Failed suites: ${FAILED_SUITE_NAMES[*]}"
            fi
        fi
        
        exit ${any_failed}
    fi
}

# Run main function with all arguments
main "$@"