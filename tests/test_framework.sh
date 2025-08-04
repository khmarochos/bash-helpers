#!/usr/bin/env bash

# test_framework.sh - Lightweight testing framework for bash-helpers
#
# Description:
#   A simple but effective testing framework for bash scripts that provides:
#   - Test suite organization
#   - Test case management with setup/teardown
#   - Assertion functions
#   - Result reporting
#   - Test isolation
#
# Usage:
#   source tests/test_framework.sh
#   test_suite "Test Suite Name"
#   test_case "Test Case Name" test_function
#   run_tests

set -euo pipefail

# Global test state
declare -i TESTS_RUN=0
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -a FAILED_TESTS=()
declare CURRENT_TEST=""
declare CURRENT_SUITE=""
declare TEST_TEMP_DIR=""

# test_suite() - Start a new test suite
#
# Description:
#   Initializes a new test suite with the given name.
#
# Input:
#   $1 - Test suite name
#
test_suite() {
    local suite_name="${1:-}"
    
    if [[ -z "${suite_name}" ]]; then
        echo "ERROR: test_suite() requires a suite name" >&2
        return 1
    fi
    
    CURRENT_SUITE="${suite_name}"
    echo "=== ${suite_name} ==="
    echo
}

# test_case() - Execute a test case
#
# Description:
#   Runs a single test case with proper setup, execution, and teardown.
#
# Input:
#   $1 - Test case name
#   $2 - Test function name
#
test_case() {
    local test_name="${1:-}"
    local test_function="${2:-}"
    
    if [[ -z "${test_name}" || -z "${test_function}" ]]; then
        echo "ERROR: test_case() requires test name and function" >&2
        return 1
    fi
    
    CURRENT_TEST="${test_name}"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Create isolated temp directory for this test
    TEST_TEMP_DIR="$(mktemp -d -t bash_helpers_test.XXXXXX)"
    
    echo -n "  ${test_name}... "
    
    # Run the test in a subshell for isolation
    if (
        cd "${TEST_TEMP_DIR}"
        "${test_function}"
    ); then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("${CURRENT_SUITE}: ${test_name}")
    fi
    
    # Cleanup temp directory
    [[ -d "${TEST_TEMP_DIR}" ]] && rm -rf "${TEST_TEMP_DIR}"
    TEST_TEMP_DIR=""
}

# skip_test() - Skip a test case
#
# Description:
#   Marks a test case as skipped with an optional reason.
#
# Input:
#   $1 - Test case name
#   $2 - Skip reason (optional)
#
skip_test() {
    local test_name="${1:-}"
    local skip_reason="${2:-No reason given}"
    
    echo "  ${test_name}... SKIP (${skip_reason})"
}

# Assert functions for common test patterns

# assert_equals() - Assert two values are equal
assert_equals() {
    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values should be equal}"
    
    if [[ "${expected}" != "${actual}" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Expected: '${expected}'"
        echo "  Actual:   '${actual}'"
        return 1
    fi
}

# assert_not_equals() - Assert two values are not equal
assert_not_equals() {
    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values should not be equal}"
    
    if [[ "${expected}" == "${actual}" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Both values: '${expected}'"
        return 1
    fi
}

# assert_true() - Assert condition is true
assert_true() {
    local condition_result="${1:-}"
    local message="${2:-Condition should be true}"
    
    if [[ "${condition_result}" != "0" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Condition returned: ${condition_result}"
        return 1
    fi
}

# assert_false() - Assert condition is false
assert_false() {
    local condition_result="${1:-}"
    local message="${2:-Condition should be false}"
    
    if [[ "${condition_result}" == "0" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Condition returned: ${condition_result}"
        return 1
    fi
}

# assert_file_exists() - Assert file exists
assert_file_exists() {
    local file_path="${1:-}"
    local message="${2:-File should exist}"
    
    if [[ ! -f "${file_path}" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  File: '${file_path}'"
        return 1
    fi
}

# assert_file_not_exists() - Assert file does not exist
assert_file_not_exists() {
    local file_path="${1:-}"
    local message="${2:-File should not exist}"
    
    if [[ -f "${file_path}" ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  File: '${file_path}'"
        return 1
    fi
}

# assert_contains() - Assert string contains substring
assert_contains() {
    local string="${1:-}"
    local substring="${2:-}"
    local message="${3:-String should contain substring}"
    
    if [[ "${string}" != *"${substring}"* ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  String:    '${string}'"
        echo "  Substring: '${substring}'"
        return 1
    fi
}

# assert_not_contains() - Assert string does not contain substring
assert_not_contains() {
    local string="${1:-}"
    local substring="${2:-}"
    local message="${3:-String should not contain substring}"
    
    if [[ "${string}" == *"${substring}"* ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  String:    '${string}'"
        echo "  Substring: '${substring}'"
        return 1
    fi
}

# assert_matches() - Assert string matches pattern
assert_matches() {
    local string="${1:-}"
    local pattern="${2:-}"
    local message="${3:-String should match pattern}"
    
    if [[ ! "${string}" =~ ${pattern} ]]; then
        echo "ASSERTION FAILED: ${message}"
        echo "  String:  '${string}'"
        echo "  Pattern: '${pattern}'"
        return 1
    fi
}

# assert_command_success() - Assert command succeeds
assert_command_success() {
    local command="${1:-}"
    local message="${2:-Command should succeed}"
    
    if ! eval "${command}" >/dev/null 2>&1; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Command: '${command}'"
        return 1
    fi
}

# assert_command_failure() - Assert command fails
assert_command_failure() {
    local command="${1:-}"
    local message="${2:-Command should fail}"
    
    if eval "${command}" >/dev/null 2>&1; then
        echo "ASSERTION FAILED: ${message}"
        echo "  Command: '${command}'"
        return 1
    fi
}

# Helper functions for test setup

# create_temp_file() - Create a temporary file with content
create_temp_file() {
    local filename="${1:-test_file}"
    local content="${2:-}"
    
    local temp_file="${TEST_TEMP_DIR}/${filename}"
    echo "${content}" > "${temp_file}"
    echo "${temp_file}"
}

# create_temp_config() - Create a temporary configuration file
create_temp_config() {
    local format="${1:-ini}"
    local content="${2:-}"
    
    case "${format}" in
        ini)
            create_temp_file "test.ini" "${content}"
            ;;
        json)
            create_temp_file "test.json" "${content}"
            ;;
        yaml)
            create_temp_file "test.yaml" "${content}"
            ;;
        *)
            echo "ERROR: Unknown config format: ${format}" >&2
            return 1
            ;;
    esac
}

# with_env_var() - Execute command with environment variable set
with_env_var() {
    local var_name="${1}"
    local var_value="${2}"
    shift 2
    
    (
        export "${var_name}=${var_value}"
        "$@"
    )
}

# run_tests() - Generate final test report
#
# Description:
#   Prints a summary of test results and exits with appropriate code.
#
run_tests() {
    echo
    echo "Test Results:"
    echo "============="
    echo "Tests Run:    ${TESTS_RUN}"
    echo "Tests Passed: ${TESTS_PASSED}"
    
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo "Tests Failed: ${TESTS_FAILED}"
        echo
        echo "Failed Tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  - ${failed_test}"
        done
        echo
        exit 1
    else
        echo "Tests Failed: 0"
        echo
        echo "All tests passed!"
        exit 0
    fi
}

# Test framework is loaded
echo "Bash Helpers Test Framework loaded"