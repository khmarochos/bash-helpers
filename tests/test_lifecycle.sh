#!/usr/bin/env bash

# test_lifecycle.sh - Comprehensive tests for lifecycle.sh module
#
# Description:
#   Tests all functionality of the lifecycle module including:
#   - Module loading and guards
#   - Single instance enforcement
#   - PID lock file management
#   - Cleanup item management
#   - Signal handling
#   - Error handling (die function)

set -euo pipefail

# Get script directory and load test framework
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_framework.sh"

# Test functions

test_module_loading() {
    # Test that module loads without errors
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    
    # Check module loaded marker
    assert_equals "1" "${LIFECYCLE_MODULE_LOADED}" "Module should be marked as loaded"
    
    # Test functions are available
    assert_command_success "declare -f ensure_single_instance" "ensure_single_instance function should be available"
    assert_command_success "declare -f add_cleanup_item" "add_cleanup_item function should be available"
    assert_command_success "declare -f remove_cleanup_item" "remove_cleanup_item function should be available"
    assert_command_success "declare -f die" "die function should be available"
    assert_command_success "declare -f cleanup" "cleanup function should be available"
}

test_module_loading_guard() {
    # Load module first time
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    local first_load="${LIFECYCLE_MODULE_LOADED}"
    
    # Load module second time (should return immediately)
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    local second_load="${LIFECYCLE_MODULE_LOADED}"
    
    assert_equals "${first_load}" "${second_load}" "Module guard should prevent reinitialization"
    assert_equals "1" "${second_load}" "Module should still be marked as loaded"
}

test_default_lock_file_computation() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Get the computed default
        local default_lock
        default_lock="$(_compute_default_lock_file)"
        
        # Should contain user and script name
        assert_contains "${default_lock}" "${USER}" "Default lock file should contain username"
        assert_contains "${default_lock}" "/tmp/" "Default lock file should be in /tmp"
        assert_contains "${default_lock}" ".lock" "Default lock file should have .lock extension"
    )
}

test_lock_file_creation_and_cleanup() {
    local test_lock="${TEST_TEMP_DIR}/test.lock"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Test lock creation
        create_lock "${test_lock}"
        assert_file_exists "${test_lock}" "Lock file should be created"
        
        # Check lock file contains PID
        local lock_content
        lock_content="$(cat "${test_lock}")"
        assert_equals "$$" "${lock_content}" "Lock file should contain current PID"
    )
    
    # Lock file should be cleaned up when subshell exits
    # Note: We can't easily test this since cleanup happens in the subshell
}

test_single_instance_enforcement() {
    local test_lock="${TEST_TEMP_DIR}/single_instance.lock"
    
    # First instance should succeed
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        check_running "${test_lock}"
        create_lock "${test_lock}"
        
        # Lock should exist with our PID
        assert_file_exists "${test_lock}" "Lock file should exist"
        local lock_pid
        lock_pid="$(cat "${test_lock}")"
        assert_equals "$$" "${lock_pid}" "Lock should contain our PID"
    )
}

test_stale_lock_cleanup() {
    local test_lock="${TEST_TEMP_DIR}/stale.lock"
    
    # Create a stale lock with invalid PID
    echo "999999" > "${test_lock}"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # This should clean up the stale lock and succeed
        check_running "${test_lock}"
        
        # Lock should be removed or replaced
        if [[ -f "${test_lock}" ]]; then
            local new_pid
            new_pid="$(cat "${test_lock}")"
            assert_not_equals "999999" "${new_pid}" "Stale lock should be replaced"
        fi
    )
}

test_cleanup_item_management() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Create test files
        local test_file1="${TEST_TEMP_DIR}/cleanup1.txt"
        local test_file2="${TEST_TEMP_DIR}/cleanup2.txt"
        echo "test1" > "${test_file1}"
        echo "test2" > "${test_file2}"
        
        # Add to cleanup
        add_cleanup_item "${test_file1}"
        add_cleanup_item "${test_file2}"
        
        # Check they're in the cleanup array
        local cleanup_list="${TO_BE_REMOVED[*]}"
        assert_contains "${cleanup_list}" "${test_file1}" "File1 should be in cleanup list"
        assert_contains "${cleanup_list}" "${test_file2}" "File2 should be in cleanup list"
        
        # Remove one item
        remove_cleanup_item "${test_file1}"
        cleanup_list="${TO_BE_REMOVED[*]}"
        assert_not_contains "${cleanup_list}" "${test_file1}" "File1 should be removed from cleanup list"
        assert_contains "${cleanup_list}" "${test_file2}" "File2 should still be in cleanup list"
        
        # Test manual cleanup
        cleanup
        
        # File1 should still exist (removed from cleanup list)
        # File2 should be removed by cleanup
        assert_file_exists "${test_file1}" "File1 should still exist (removed from cleanup)"
        assert_file_not_exists "${test_file2}" "File2 should be cleaned up"
    )
}

test_ensure_single_instance_function() {
    local test_lock="${TEST_TEMP_DIR}/ensure_test.lock"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # This should set up complete lifecycle management
        ensure_single_instance "${test_lock}"
        
        # Lock file should exist
        assert_file_exists "${test_lock}" "ensure_single_instance should create lock file"
        
        # Lock should be in cleanup list
        local cleanup_list="${TO_BE_REMOVED[*]}"
        assert_contains "${cleanup_list}" "${test_lock}" "Lock file should be in cleanup list"
        
        # Traps should be installed
        assert_equals "1" "${CLEANUP_TRAPS_INSTALLED}" "Cleanup traps should be installed"
    )
}

test_die_function() {
    # Test die function in subshell (since it exits)
    local output
    output="$(
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        die 42 "test error message" 2>&1
    )" || local exit_code=$?
    
    # Should have specific exit code (note: might be different due to subshell)
    assert_contains "${output}" "test error message" "Die should output error message"
    assert_contains "${output}" "ERROR:" "Die should format as error"
    assert_contains "${output}" "42" "Die should include exit code"
}

test_configuration_options() {
    # Test command-line option parsing
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" --lock-file "${TEST_TEMP_DIR}/config_test.lock" --cleanup-on-success >/dev/null 2>&1
        
        assert_equals "${TEST_TEMP_DIR}/config_test.lock" "${LOCK_FILE}" "Command-line lock file should be set"
        assert_equals "1" "${CLEANUP_ON_SUCCESS}" "Command-line cleanup option should be set"
    )
}

test_signal_trap_installation() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Initially no traps
        assert_equals "0" "${CLEANUP_TRAPS_INSTALLED}" "Traps should not be installed initially"
        
        # Add cleanup item should install traps
        add_cleanup_item "${TEST_TEMP_DIR}/dummy"
        assert_equals "1" "${CLEANUP_TRAPS_INSTALLED}" "Traps should be installed after adding cleanup item"
        
        # Check that traps are actually set
        local trap_output
        trap_output="$(trap -p EXIT)"
        assert_contains "${trap_output}" "cleanup" "EXIT trap should be set to cleanup function"
    )
}

test_error_handling() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    
    # Test functions with invalid inputs
    assert_command_failure "add_cleanup_item ''" "Should reject empty cleanup item"
    assert_command_failure "remove_cleanup_item ''" "Should reject empty cleanup item removal"
    
    # Test with non-existent files (should not crash)
    assert_command_success "add_cleanup_item '/non/existent/file'" "Should accept non-existent file for cleanup"
}

test_help_function() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    
    # Test that help function exists and works
    assert_command_success "declare -f show_lifecycle_help" "show_lifecycle_help function should exist"
    
    local help_output
    help_output="$(show_lifecycle_help)"
    assert_contains "${help_output}" "COMMAND-LINE OPTIONS" "Help should contain options section"
    assert_contains "${help_output}" "ENVIRONMENT VARIABLES" "Help should contain env vars section"
    assert_contains "${help_output}" "lock-file" "Help should mention lock-file option"
}

# Run the test suite
test_suite "Lifecycle Module Tests"

test_case "Module Loading" test_module_loading
test_case "Module Loading Guard" test_module_loading_guard
test_case "Default Lock File Computation" test_default_lock_file_computation
test_case "Lock File Creation and Cleanup" test_lock_file_creation_and_cleanup
test_case "Single Instance Enforcement" test_single_instance_enforcement
test_case "Stale Lock Cleanup" test_stale_lock_cleanup
test_case "Cleanup Item Management" test_cleanup_item_management
test_case "Ensure Single Instance Function" test_ensure_single_instance_function
test_case "Die Function" test_die_function
test_case "Configuration Options" test_configuration_options
test_case "Signal Trap Installation" test_signal_trap_installation
test_case "Error Handling" test_error_handling
test_case "Help Function" test_help_function

run_tests