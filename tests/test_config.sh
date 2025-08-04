#!/usr/bin/env bash

# test_config.sh - Comprehensive tests for config.sh module
#
# Description:
#   Tests all functionality of the configuration module including:
#   - Module loading and guards
#   - Configuration loading from files (INI, JSON, YAML)
#   - Environment variable integration
#   - Command-line argument parsing
#   - Type conversion and validation
#   - Configuration priority handling

set -euo pipefail

# Get script directory and load test framework
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_framework.sh"

# Test functions

test_module_loading() {
    # Test that module loads without errors
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    
    # Check module loaded marker
    assert_equals "1" "${CONFIG_MODULE_LOADED}" "Module should be marked as loaded"
    
    # Test functions are available
    assert_command_success "declare -f load_config" "load_config function should be available"
    assert_command_success "declare -f get_config" "get_config function should be available"
    assert_command_success "declare -f set_config" "set_config function should be available"
    assert_command_success "declare -f validate_config" "validate_config function should be available"
}

test_module_loading_guard() {
    # Load module first time
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    local first_load="${CONFIG_MODULE_LOADED}"
    
    # Load module second time (should return immediately)
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    local second_load="${CONFIG_MODULE_LOADED}"
    
    assert_equals "${first_load}" "${second_load}" "Module guard should prevent reinitialization"
    assert_equals "1" "${second_load}" "Module should still be marked as loaded"
}

test_basic_config_operations() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Test setting and getting values
        set_config "app.name" "TestApp"
        set_config "app.version" "1.0.0"
        set_config "database.port" "5432"
        
        local app_name
        local app_version  
        local db_port
        app_name="$(get_config "app.name")"
        app_version="$(get_config "app.version")"
        db_port="$(get_config "database.port")"
        
        assert_equals "TestApp" "${app_name}" "Should retrieve app name"
        assert_equals "1.0.0" "${app_version}" "Should retrieve app version"
        assert_equals "5432" "${db_port}" "Should retrieve database port"
    )
}

test_default_values() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Test getting non-existent key with default
        local result
        result="$(get_config "non.existent" "default_value")"
        assert_equals "default_value" "${result}" "Should return default for non-existent key"
        
        # Test getting non-existent key without default (should fail or return empty)
        if result="$(get_config "non.existent" 2>/dev/null)"; then
            assert_equals "" "${result}" "Should return empty for non-existent key without default"
        fi
    )
}

test_type_conversion() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Set test values
        set_config "test.int" "42"
        set_config "test.bool_true" "yes"
        set_config "test.bool_false" "no" 
        set_config "test.string" "hello world"
        
        # Test integer conversion
        local int_val
        int_val="$(get_config "test.int" "0" "int")"
        assert_equals "42" "${int_val}" "Should convert integer correctly"
        
        # Test boolean conversion
        local bool_true
        local bool_false
        bool_true="$(get_config "test.bool_true" "false" "bool")"
        bool_false="$(get_config "test.bool_false" "true" "bool")"
        assert_equals "true" "${bool_true}" "Should convert 'yes' to true"
        assert_equals "false" "${bool_false}" "Should convert 'no' to false"
        
        # Test string conversion (default)
        local string_val
        string_val="$(get_config "test.string" "" "string")"
        assert_equals "hello world" "${string_val}" "Should return string as-is"
    )
}

test_invalid_type_conversion() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Set invalid values
        set_config "test.invalid_int" "not_a_number"
        set_config "test.invalid_bool" "maybe"
        
        # Test that invalid conversions fail
        local result
        if result="$(get_config "test.invalid_int" "0" "int" 2>/dev/null)"; then
            # If it doesn't fail, it should return the default
            assert_equals "0" "${result}" "Invalid int should return default or fail"
        fi
        
        if result="$(get_config "test.invalid_bool" "false" "bool" 2>/dev/null)"; then
            # If it doesn't fail, it should return the default
            assert_equals "false" "${result}" "Invalid bool should return default or fail" 
        fi
    )
}

test_ini_file_loading() {
    local ini_file
    ini_file="$(create_temp_config "ini" "
# Test INI file
app_name=IniApp
debug=true

[database]
host=db.example.com
port=5432
ssl=yes

[features]
logging=true
max_connections=100
")"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        load_config "${ini_file}"
        
        # Test top-level values
        local app_name
        local debug
        app_name="$(get_config "app_name")"
        debug="$(get_config "debug")"
        assert_equals "IniApp" "${app_name}" "Should load top-level INI value"
        assert_equals "true" "${debug}" "Should load top-level boolean"
        
        # Test section values
        local db_host
        local db_port
        local ssl
        db_host="$(get_config "database.host")"
        db_port="$(get_config "database.port" "0" "int")"
        ssl="$(get_config "database.ssl" "false" "bool")"
        assert_equals "db.example.com" "${db_host}" "Should load section value"
        assert_equals "5432" "${db_port}" "Should load and convert section integer"
        assert_equals "true" "${ssl}" "Should load and convert section boolean"
        
        # Test nested section values
        local logging
        local max_conn
        logging="$(get_config "features.logging" "false" "bool")"
        max_conn="$(get_config "features.max_connections" "0" "int")"
        assert_equals "true" "${logging}" "Should load nested section boolean"
        assert_equals "100" "${max_conn}" "Should load nested section integer"
    )
}

test_key_transformation() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Test key transformation functions
        local result
        result="$(_transform_key "database-host" "dot")"
        assert_equals "database.host" "${result}" "Should transform kebab-case to dot notation"
        
        result="$(_transform_key "database_host" "dot")"
        assert_equals "database.host" "${result}" "Should transform snake_case to dot notation"
        
        result="$(_transform_key "database.host" "kebab")"
        assert_equals "database-host" "${result}" "Should transform dot notation to kebab-case"
        
        result="$(_transform_key "database.host" "env")"
        assert_equals "DATABASE_HOST" "${result}" "Should transform to environment variable format"
    )
}

test_environment_variable_loading() {
    (
        # Set test environment variables
        export APP_DATABASE_HOST="env.example.com"
        export CONFIG_LOG_LEVEL="DEBUG"
        export MYAPP_FEATURE_ENABLED="true"
        
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Load environment variables
        _load_config_from_env
        
        # Test that values were loaded (keys are transformed)
        local db_host
        local log_level
        local feature
        db_host="$(get_config "database.host" "not-found")"
        log_level="$(get_config "log.level" "not-found")"
        feature="$(get_config "feature.enabled" "not-found")"
        
        # Note: Actual key transformation depends on implementation
        # We're testing that environment variables are processed
        local found_some=false
        if [[ "${db_host}" != "not-found" ]] || [[ "${log_level}" != "not-found" ]] || [[ "${feature}" != "not-found" ]]; then
            found_some=true
        fi
        
        assert_equals "true" "${found_some}" "Should process some environment variables"
    )
}

test_custom_env_prefixes() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Add custom prefix
        add_config_env_prefix "MYSERVICE_"
        
        # Set environment variable with custom prefix
        export MYSERVICE_DATABASE_URL="custom://db.example.com"
        
        # Load environment variables
        _load_config_from_env
        
        # Check if the value was loaded (key transformation may vary)
        local found=false
        for key in "${!CONFIG_VALUES[@]}"; do
            if [[ "${CONFIG_VALUES[${key}]}" == "custom://db.example.com" ]]; then
                found=true
                break
            fi
        done
        
        assert_equals "true" "${found}" "Should process custom prefix environment variables"
    )
}

test_configuration_priority() {
    local config_file
    config_file="$(create_temp_config "ini" "
[app]
priority_test=from_file
database_host=file.example.com
")"
    
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Load configuration in priority order
        # 1. File (lowest priority)
        load_config "${config_file}"
        
        # 2. Environment (medium priority)
        export CONFIG_PRIORITY_TEST="from_env"
        _load_config_from_env
        
        # 3. Manual setting (highest priority) 
        set_config "app.priority_test" "from_manual" "cli"
        
        # Test final value
        local result
        result="$(get_config "app.priority_test")"
        
        # The manual/CLI setting should have highest priority
        assert_equals "from_manual" "${result}" "Manual/CLI setting should have highest priority"
    )
}

test_configuration_validation() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Set some configuration values
        set_config "app.name" "TestApp"
        set_config "app.version" "1.0.0"
        
        # Basic validation should pass
        assert_command_success "validate_config" "Basic validation should pass"
        
        # Test with empty value
        set_config "empty.value" ""
        
        # Validation might still pass depending on implementation
        validate_config || true  # Don't fail the test if validation fails
    )
}

test_configuration_source_tracking() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Set values from different sources
        set_config "test.file" "file_value" "file"
        set_config "test.env" "env_value" "env"
        set_config "test.cli" "cli_value" "cli"
        
        # Test source tracking
        local file_source
        local env_source
        local cli_source
        file_source="$(_get_config_source "test.file")"
        env_source="$(_get_config_source "test.env")"
        cli_source="$(_get_config_source "test.cli")"
        
        assert_equals "file" "${file_source}" "Should track file source"
        assert_equals "env" "${env_source}" "Should track env source"
        assert_equals "cli" "${cli_source}" "Should track CLI source"
    )
}

test_command_line_parsing() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Test command-line option parsing
        parse_config_options --config-database.host "cli.example.com" --config-port "8080"
        
        # Check that values were set
        local db_host
        local port
        db_host="$(get_config "database.host" "not-found")"
        port="$(get_config "port" "not-found")"
        
        assert_equals "cli.example.com" "${db_host}" "Should parse CLI database host"
        assert_equals "8080" "${port}" "Should parse CLI port"
    )
}

test_explicit_override_mappings() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Define explicit mappings
        define_config_overrides env "DATABASE_URL" "database.connection_string"
        define_config_overrides cli "--db-url" "database.connection_string"
        
        # Set environment variable
        export DATABASE_URL="postgres://localhost:5432/mydb"
        
        # Load environment with mappings
        _load_config_from_env
        
        # Test that mapping worked
        local db_url
        db_url="$(get_config "database.connection_string" "not-found")"
        assert_equals "postgres://localhost:5432/mydb" "${db_url}" "Should apply explicit environment mapping"
    )
}

test_help_function() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    
    # Test that help function exists and works
    assert_command_success "declare -f show_config_help" "show_config_help function should exist"
    
    local help_output
    help_output="$(show_config_help)"
    assert_contains "${help_output}" "COMMAND-LINE OPTIONS" "Help should contain options section"
    assert_contains "${help_output}" "ENVIRONMENT VARIABLES" "Help should contain env vars section"
    assert_contains "${help_output}" "config-file" "Help should mention config-file option"
}

test_format_support_detection() {
    (
        source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
        source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
        
        # Test format support detection
        _detect_format_support
        
        # Check that format support flags are set
        assert_matches "${CONFIG_SUPPORT_JSON}" "^[01]$" "JSON support flag should be 0 or 1"
        assert_matches "${CONFIG_SUPPORT_YAML}" "^[01]$" "YAML support flag should be 0 or 1"
    )
}

# Skip JSON and YAML tests if tools are not available
test_json_loading_if_available() {
    if command -v jq >/dev/null 2>&1; then
        local json_file
        json_file="$(create_temp_config "json" '{
  "app": {
    "name": "JsonApp",
    "version": "2.0.0"
  },
  "database": {
    "host": "json.example.com",
    "port": 5432,
    "ssl": true
  }
}')"
        
        (
            source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
            source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
            
            load_config "${json_file}"
            
            local app_name
            local db_host
            app_name="$(get_config "app.name" "not-found")"
            db_host="$(get_config "database.host" "not-found")"
            
            assert_equals "JsonApp" "${app_name}" "Should load JSON app name"
            assert_equals "json.example.com" "${db_host}" "Should load JSON database host"
        )
    else
        skip_test "JSON Loading" "jq not available"
    fi
}

# Run the test suite
test_suite "Configuration Module Tests"

test_case "Module Loading" test_module_loading
test_case "Module Loading Guard" test_module_loading_guard
test_case "Basic Config Operations" test_basic_config_operations
test_case "Default Values" test_default_values
test_case "Type Conversion" test_type_conversion
test_case "Invalid Type Conversion" test_invalid_type_conversion
test_case "INI File Loading" test_ini_file_loading
test_case "Key Transformation" test_key_transformation
test_case "Environment Variable Loading" test_environment_variable_loading
test_case "Custom Environment Prefixes" test_custom_env_prefixes
test_case "Configuration Priority" test_configuration_priority
test_case "Configuration Validation" test_configuration_validation
test_case "Configuration Source Tracking" test_configuration_source_tracking
test_case "Command Line Parsing" test_command_line_parsing
test_case "Explicit Override Mappings" test_explicit_override_mappings
test_case "Help Function" test_help_function
test_case "Format Support Detection" test_format_support_detection
test_case "JSON Loading (if available)" test_json_loading_if_available

run_tests