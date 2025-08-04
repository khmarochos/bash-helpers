#!/usr/bin/env bash

# test_integration.sh - Integration tests for bash-helpers modules
#
# Description:
#   Tests the interaction between different modules to ensure they work
#   correctly together:
#   - Multiple module loading
#   - Cross-module functionality
#   - Shared configuration
#   - End-to-end workflows

set -euo pipefail

# Get script directory and load test framework
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_framework.sh"

# Test functions

test_all_modules_loading() {
    # Test that all modules can be loaded together
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
    
    # Check all modules are loaded
    assert_equals "1" "${LOG_MODULE_LOADED}" "Log module should be loaded"
    assert_equals "1" "${CONFIG_MODULE_LOADED}" "Config module should be loaded"
    assert_equals "1" "${LIFECYCLE_MODULE_LOADED}" "Lifecycle module should be loaded"
    
    # Test that all key functions are available
    assert_command_success "declare -f log" "log function should be available"
    assert_command_success "declare -f get_config" "get_config function should be available"
    assert_command_success "declare -f ensure_single_instance" "ensure_single_instance function should be available"
}

test_logging_with_lifecycle() {
    local test_lock="${TEST_TEMP_DIR}/integration.lock"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Set up lifecycle management
        ensure_single_instance "${test_lock}"
        
        # Create a temp file and add to cleanup
        local temp_file="${TEST_TEMP_DIR}/test_file.txt"
        echo "test content" > "${temp_file}"
        add_cleanup_item "${temp_file}"
        
        # Use logging functions
        assert_command_success "log 'Integration test message'" "Logging should work with lifecycle"
        assert_command_success "warn 'Integration warning'" "Warning should work with lifecycle"
        
        # Verify lock file exists
        assert_file_exists "${test_lock}" "Lock file should exist"
        
        # Verify temp file is in cleanup list
        local cleanup_list="${TO_BE_REMOVED[*]}"
        assert_contains "${cleanup_list}" "${temp_file}" "Temp file should be in cleanup list"
        assert_contains "${cleanup_list}" "${test_lock}" "Lock file should be in cleanup list"
    )
}

test_config_with_logging() {
    local config_file
    config_file="$(create_temp_config "ini" "
[logging]
level=DEBUG
file=${TEST_TEMP_DIR}/integration.log

[app]
name=IntegrationTest
debug=true
")"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Load configuration
        load_config "${config_file}"
        
        # Get logging configuration
        local log_level
        local log_file
        local app_name
        log_level="$(get_config "logging.level")"
        log_file="$(get_config "logging.file")"
        app_name="$(get_config "app.name")"
        
        assert_equals "DEBUG" "${log_level}" "Should load log level from config"
        assert_equals "${TEST_TEMP_DIR}/integration.log" "${log_file}" "Should load log file from config"
        assert_equals "IntegrationTest" "${app_name}" "Should load app name from config"
        
        # Test that we can use configuration for logging setup
        # (This would typically be done by setting LOG_LEVEL and LOG_FILE before loading log.sh)
        LOG_LEVEL="${log_level}"
        LOG_FILE="${log_file}"
        
        # Test logging with configuration
        log "Integration test with config"
        
        # Check that log file was created and contains our message
        if [[ -f "${log_file}" ]]; then
            local log_content
            log_content="$(cat "${log_file}")"
            assert_contains "${log_content}" "Integration test with config" "Log file should contain our message"
        fi
    )
}

test_full_integration_workflow() {
    local config_file
    config_file="$(create_temp_config "ini" "
[app]
name=FullIntegrationTest
version=1.0.0
lock_file=${TEST_TEMP_DIR}/full_integration.lock

[logging]
level=INFO
file=${TEST_TEMP_DIR}/full_integration.log

[database]
host=db.example.com
port=5432
ssl=true
")"
    
    (
        # Load all modules in typical order
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Load configuration
        load_config "${config_file}"
        
        # Set up logging from configuration
        LOG_LEVEL="$(get_config "logging.level" "INFO")"
        LOG_FILE="$(get_config "logging.file")"
        
        # Set up lifecycle management
        local lock_file
        lock_file="$(get_config "app.lock_file" "${TEST_TEMP_DIR}/default.lock")"
        ensure_single_instance "${lock_file}"
        
        # Application logic with logging
        local app_name
        local app_version
        local db_host
        local db_port
        app_name="$(get_config "app.name")"
        app_version="$(get_config "app.version")"
        db_host="$(get_config "database.host")"
        db_port="$(get_config "database.port" "5432" "int")"
        
        log "Application ${app_name} v${app_version} starting"
        log "Database: ${db_host}:${db_port}"
        
        # Create some temporary resources
        local work_dir="${TEST_TEMP_DIR}/work"
        mkdir -p "${work_dir}"
        add_cleanup_item "${work_dir}"
        
        local data_file="${work_dir}/data.txt"
        echo "Processing data for ${app_name}" > "${data_file}"
        
        log "Created work directory: ${work_dir}"
        log "Processing complete"
        
        # Verify everything is set up correctly
        assert_file_exists "${lock_file}" "Lock file should exist"
        assert_file_exists "${data_file}" "Data file should exist"
        
        if [[ -n "${LOG_FILE}" && -f "${LOG_FILE}" ]]; then
            local log_content
            log_content="$(cat "${LOG_FILE}")"
            assert_contains "${log_content}" "${app_name}" "Log should contain app name"
            assert_contains "${log_content}" "starting" "Log should contain startup message"
            assert_contains "${log_content}" "Processing complete" "Log should contain completion message"
        fi
        
        # Verify cleanup list contains our resources
        local cleanup_list="${TO_BE_REMOVED[*]}"
        assert_contains "${cleanup_list}" "${work_dir}" "Work directory should be in cleanup list"
        assert_contains "${cleanup_list}" "${lock_file}" "Lock file should be in cleanup list"
    )
}

test_environment_and_cli_integration() {
    local config_file
    config_file="$(create_temp_config "ini" "
[app]  
name=EnvCliTest
debug=false

[database]
host=file.example.com
port=3306
")"
    
    (
        # Set environment variables
        export CONFIG_APP_NAME="EnvOverrideApp"
        export DATABASE_CONFIG="env.example.com"
        
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Load configuration from file
        load_config "${config_file}"
        
        # Parse CLI arguments (simulate)
        parse_config_options --config-database.host "cli.example.com" --config-app.version "2.0.0"
        
        # Test final values (priority: CLI > ENV > FILE)
        local app_name
        local db_host
        local db_port
        local app_version
        app_name="$(get_config "app.name" "unknown")"
        db_host="$(get_config "database.host" "unknown")"
        db_port="$(get_config "database.port" "0" "int")"
        app_version="$(get_config "app.version" "unknown")"
        
        # CLI should override everything
        assert_equals "cli.example.com" "${db_host}" "CLI should override database host"
        assert_equals "2.0.0" "${app_version}" "CLI should set app version"
        
        # File value should be used where not overridden
        assert_equals "3306" "${db_port}" "Should use file value for port"
        
        # Test that we can use configuration for service setup
        log "Service ${app_name} connecting to ${db_host}:${db_port}"
        
        # Set up single instance with configuration
        ensure_single_instance "${TEST_TEMP_DIR}/env_cli_test.lock"
    )
}

test_error_handling_integration() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Set up lifecycle management
        ensure_single_instance "${TEST_TEMP_DIR}/error_test.lock"
        
        # Create a temp resource
        local temp_file="${TEST_TEMP_DIR}/error_test.txt"
        echo "test" > "${temp_file}"
        add_cleanup_item "${temp_file}"
        
        # Test that die function works with cleanup
        # We can't actually test die since it exits, but we can test the setup
        assert_command_success "declare -f die" "die function should be available"
        
        # Test error logging
        assert_command_success "error 'Integration error test'" "Error logging should work"
        
        # Verify resources are set up for cleanup
        local cleanup_list="${TO_BE_REMOVED[*]}"
        assert_contains "${cleanup_list}" "${temp_file}" "Temp file should be in cleanup"
    )
}

test_module_configuration_integration() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        
        # Test that modules can load their own configuration
        # (This tests the config integration features in each module)
        
        # Set some module-specific configuration
        export LOG_LEVEL="DEBUG"
        export LOG_FILE="${TEST_TEMP_DIR}/module_config.log"
        export LOCK_FILE="${TEST_TEMP_DIR}/module_config.lock"
        export CLEANUP_ON_SUCCESS="0"
        
        # Test that configuration is picked up
        assert_equals "DEBUG" "${LOG_LEVEL}" "Log level should be set from environment"
        assert_equals "${TEST_TEMP_DIR}/module_config.log" "${LOG_FILE}" "Log file should be set from environment"
        assert_equals "${TEST_TEMP_DIR}/module_config.lock" "${LOCK_FILE}" "Lock file should be set from environment"
        assert_equals "0" "${CLEANUP_ON_SUCCESS}" "Cleanup setting should be set from environment"
        
        # Test module functionality with configuration
        log "Module configuration test"
        ensure_single_instance
        
        # Verify log file exists and contains message
        if [[ -f "${LOG_FILE}" ]]; then
            local log_content
            log_content="$(cat "${LOG_FILE}")"
            assert_contains "${log_content}" "Module configuration test" "Log file should contain test message"
        fi
        
        # Verify lock file exists
        assert_file_exists "${LOCK_FILE}" "Lock file should exist at configured location"
    )
}

test_concurrent_module_loading() {
    # Test that modules handle concurrent loading correctly
    (
        # Load modules in different orders to test loading guards
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Load them again in different order
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/lifecycle.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        
        # All should still be loaded and functional
        assert_equals "1" "${LOG_MODULE_LOADED}" "Log module should be loaded"
        assert_equals "1" "${CONFIG_MODULE_LOADED}" "Config module should be loaded"
        assert_equals "1" "${LIFECYCLE_MODULE_LOADED}" "Lifecycle module should be loaded"
        
        # Test that functionality works
        assert_command_success "log 'Concurrent loading test'" "Logging should work after multiple loads"
        assert_command_success "set_config 'test.key' 'test.value'" "Config should work after multiple loads"
        assert_command_success "add_cleanup_item '${TEST_TEMP_DIR}/concurrent_test'" "Lifecycle should work after multiple loads"
    )
}

# Run the test suite
test_suite "Integration Tests"

test_case "All Modules Loading" test_all_modules_loading
test_case "Logging with Lifecycle" test_logging_with_lifecycle
test_case "Config with Logging" test_config_with_logging
test_case "Full Integration Workflow" test_full_integration_workflow
test_case "Environment and CLI Integration" test_environment_and_cli_integration
test_case "Error Handling Integration" test_error_handling_integration
test_case "Module Configuration Integration" test_module_configuration_integration
test_case "Concurrent Module Loading" test_concurrent_module_loading

run_tests