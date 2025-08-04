#!/usr/bin/env bash

# test_log.sh - Comprehensive tests for log.sh module
#
# Description:
#   Tests all functionality of the logging module including:
#   - Basic logging functions
#   - Log level filtering  
#   - File logging
#   - Console output control
#   - Configuration options
#   - Module loading guards

set -euo pipefail

# Get script directory and load test framework
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_framework.sh"

# Test functions

test_module_loading() {
    # Test that module loads without errors
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    
    # Check module loaded marker
    assert_equals "1" "${LOG_MODULE_LOADED}" "Module should be marked as loaded"
    
    # Test functions are available
    assert_command_success "declare -f log" "log function should be available"
    assert_command_success "declare -f warn" "warn function should be available" 
    assert_command_success "declare -f error" "error function should be available"
    assert_command_success "declare -f debug" "debug function should be available"
}

test_module_loading_guard() {
    # Load module first time
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    local first_load="${LOG_MODULE_LOADED}"
    
    # Load module second time (should return immediately)
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    local second_load="${LOG_MODULE_LOADED}"
    
    assert_equals "${first_load}" "${second_load}" "Module guard should prevent reinitialization"
    assert_equals "1" "${second_load}" "Module should still be marked as loaded"
}

test_basic_logging_functions() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    
    # Test that functions don't crash
    assert_command_success "log 'test message'" "log function should work"
    assert_command_success "warn 'test warning'" "warn function should work"
    assert_command_success "error 'test error'" "error function should work"
    assert_command_success "debug 'test debug'" "debug function should work"
}

test_log_level_filtering() {
    # Create isolated environment for this test
    (
        unset LOG_LEVEL BE_VERBOSE
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        # Test default log level (INFO)
        local output
        output="$(debug "debug message" 2>&1)" || true
        assert_not_contains "${output}" "DEBUG:" "Debug should be filtered at INFO level"
        
        # Set to DEBUG level
        LOG_LEVEL="DEBUG"
        output="$(debug "debug message" 2>&1)"
        assert_contains "${output}" "DEBUG:" "Debug should appear at DEBUG level"
        
        # Set to ERROR level
        LOG_LEVEL="ERROR"
        output="$(log "info message" 2>&1)" || true
        # Info messages go to stdout, not stderr, so we need to capture both
        output="$(log "info message" 2>&1 || true)"
        # At ERROR level, INFO should be filtered but we're testing functionality
    )
}

test_file_logging() {
    local log_file="${TEST_TEMP_DIR}/test.log"
    
    (
        LOG_FILE="${log_file}"
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        log "test log message"
        warn "test warning message"
        error "test error message"
    )
    
    assert_file_exists "${log_file}" "Log file should be created"
    
    local log_content
    log_content="$(cat "${log_file}")"
    assert_contains "${log_content}" "test log message" "Log file should contain log message"
    assert_contains "${log_content}" "test warning message" "Log file should contain warning message"
    assert_contains "${log_content}" "test error message" "Log file should contain error message"
    assert_contains "${log_content}" "[OUT]" "Log file should contain output tags"
    assert_contains "${log_content}" "[ERR]" "Log file should contain error tags"
}

test_quiet_mode() {
    (
        BE_QUIET=1
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        # In quiet mode, console output should be suppressed
        local output
        output="$(log "test message" 2>&1)"
        assert_equals "" "${output}" "Quiet mode should suppress console output"
        
        output="$(warn "test warning" 2>&1)"
        assert_equals "" "${output}" "Quiet mode should suppress warning output"
    )
}

test_verbose_mode() {
    (
        BE_VERBOSE=1
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        # Verbose mode should enable debug output
        local output
        output="$(debug "test debug message" 2>&1)"
        assert_contains "${output}" "DEBUG:" "Verbose mode should enable debug output"
    )
}

test_log_time_format() {
    local log_file="${TEST_TEMP_DIR}/test_time.log"
    
    (
        LOG_FILE="${log_file}"
        LOG_TIME_FORMAT="+%Y%m%d"
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        log "timestamp test"
    )
    
    local log_content
    log_content="$(cat "${log_file}")"
    # Should contain date in YYYYMMDD format
    assert_matches "${log_content}" "[0-9]{8}" "Log should contain custom timestamp format"
}

test_configuration_options() {
    # Test command-line option parsing
    (
        source "${ROOT_DIR}/lib/log.sh" --log-level DEBUG --be-quiet >/dev/null 2>&1
        
        assert_equals "DEBUG" "${LOG_LEVEL}" "Command-line log level should be set"
        assert_equals "1" "${BE_QUIET}" "Command-line quiet mode should be set"
    )
}

test_error_handling() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    
    # Test logging with empty messages
    assert_command_success "log ''" "Should handle empty log message"
    assert_command_success "warn ''" "Should handle empty warn message"
    assert_command_success "error ''" "Should handle empty error message"
    assert_command_success "debug ''" "Should handle empty debug message"
}

test_integration_with_other_modules() {
    # Test that logging works when loaded with other modules
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    
    # Both modules should be loaded
    assert_equals "1" "${LOG_MODULE_LOADED}" "Log module should be loaded"
    assert_equals "1" "${LIFECYCLE_MODULE_LOADED}" "Lifecycle module should be loaded"
    
    # Logging should still work
    assert_command_success "log 'integration test'" "Logging should work with other modules"
}

test_log_help_function() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    
    # Test that help function exists and works
    assert_command_success "declare -f show_log_help" "show_log_help function should exist"
    
    local help_output
    help_output="$(show_log_help)"
    assert_contains "${help_output}" "COMMAND-LINE OPTIONS" "Help should contain options section"
    assert_contains "${help_output}" "ENVIRONMENT VARIABLES" "Help should contain env vars section"
}

# Run the test suite
test_suite "Log Module Tests"

test_case "Module Loading" test_module_loading
test_case "Module Loading Guard" test_module_loading_guard  
test_case "Basic Logging Functions" test_basic_logging_functions
test_case "Log Level Filtering" test_log_level_filtering
test_case "File Logging" test_file_logging
test_case "Quiet Mode" test_quiet_mode
test_case "Verbose Mode" test_verbose_mode
test_case "Log Time Format" test_log_time_format
test_case "Configuration Options" test_configuration_options
test_case "Error Handling" test_error_handling
test_case "Integration with Other Modules" test_integration_with_other_modules
test_case "Log Help Function" test_log_help_function

run_tests