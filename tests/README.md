# Bash Helpers Test Suite

This directory contains comprehensive tests for the bash-helpers library modules.

## Test Structure

### Test Framework (`test_framework.sh`)
A lightweight testing framework that provides:
- Test suite organization
- Test case management with isolated execution
- Assertion functions for common test patterns
- Automatic cleanup of temporary resources
- Clear test reporting

### Module Tests
- **`test_log.sh`** - Tests for the logging module (`lib/log.sh`)
- **`test_lifecycle.sh`** - Tests for the lifecycle module (`lib/lifecycle.sh`)
- **`test_config.sh`** - Tests for the configuration module (`lib/config.sh`)
- **`test_integration.sh`** - Integration tests for module combinations

## Running Tests

### Using the Test Runner (Recommended)
```bash
# Run all tests
./run_tests.sh

# Run specific module tests
./run_tests.sh log
./run_tests.sh lifecycle  
./run_tests.sh config
./run_tests.sh integration

# List available test suites
./run_tests.sh --list

# Get help
./run_tests.sh --help
```

### Running Individual Test Files
```bash
# Run a specific test file directly
./tests/test_log.sh
./tests/test_lifecycle.sh
./tests/test_config.sh
./tests/test_integration.sh
```

## Test Coverage

### Log Module Tests
- Module loading and guards
- Basic logging functions (log, warn, error, debug)
- Log level filtering
- File logging with timestamps
- Console output control (quiet/verbose modes)
- Configuration options parsing
- Error handling
- Integration with other modules

### Lifecycle Module Tests
- Module loading and guards
- Single instance enforcement with PID locks
- Lock file creation and cleanup
- Stale lock detection and removal
- Cleanup item management
- Signal trap installation
- Die function error handling
- Configuration options parsing
- Cross-module integration

### Configuration Module Tests
- Module loading and guards
- Basic configuration operations (get/set)
- Type conversion (string, int, bool, array)
- INI file parsing
- Environment variable integration
- Command-line argument parsing
- Configuration priority handling
- Key transformation utilities
- Validation functions
- Help system

### Integration Tests
- Multiple module loading
- Cross-module functionality
- Shared configuration scenarios
- End-to-end workflows
- Environment and CLI integration
- Error handling across modules
- Concurrent module loading

## Test Framework Features

### Assertion Functions
- `assert_equals` - Test value equality
- `assert_not_equals` - Test value inequality
- `assert_true` / `assert_false` - Test boolean conditions
- `assert_file_exists` / `assert_file_not_exists` - Test file presence
- `assert_contains` / `assert_not_contains` - Test string containment
- `assert_matches` - Test pattern matching
- `assert_command_success` / `assert_command_failure` - Test command execution

### Helper Functions
- `create_temp_file` - Create temporary files with content
- `create_temp_config` - Create configuration files in various formats
- `with_env_var` - Execute commands with environment variables

### Test Isolation
- Each test case runs in a separate subprocess
- Temporary directories are created and cleaned up automatically
- Environment variables are isolated between tests
- Module state is reset between test cases

## Test Patterns

### Basic Test Structure
```bash
#!/usr/bin/env bash
set -euo pipefail

# Load test framework
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
source "${SCRIPT_DIR}/test_framework.sh"

# Test function
test_example() {
    source "${ROOT_DIR}/lib/log.sh" >/dev/null 2>&1
    
    # Test logging
    local output
    output="$(log "test message" 2>&1)"
    assert_contains "${output}" "test message" "Log should contain message"
}

# Run tests
test_suite "Example Tests"
test_case "Example Test" test_example
run_tests
```

### Testing with Configuration Files
```bash
test_config_loading() {
    local config_file
    config_file="$(create_temp_config "ini" "
[app]
name=TestApp
debug=true
")"
    
    source "${ROOT_DIR}/lib/config.sh" >/dev/null 2>&1
    load_config "${config_file}"
    
    local app_name
    app_name="$(get_config "app.name")"
    assert_equals "TestApp" "${app_name}" "Should load app name from config"
}
```

### Testing with Environment Variables
```bash
test_environment() {
    with_env_var "LOG_LEVEL" "DEBUG" bash -c '
        source lib/log.sh >/dev/null 2>&1
        [[ "${LOG_LEVEL}" == "DEBUG" ]]
    '
    assert_true $? "Environment variable should be set"
}
```

## Adding New Tests

1. Create test functions that use the assertion framework
2. Use the `test_case` function to register each test
3. Group related tests in the same test suite
4. Use temporary files and directories (automatically cleaned up)
5. Test both success and failure cases
6. Test edge cases and error conditions
7. Add integration tests for cross-module functionality

## Continuous Integration

The test suite is designed to work in CI/CD environments:
- All tests are self-contained
- No external dependencies beyond basic Unix tools
- Clear exit codes (0 for success, 1 for failure)
- Detailed output for debugging failures
- Individual test suite execution for targeted testing

## Troubleshooting

### Common Issues
- **Permission errors**: Ensure test files are executable (`chmod +x`)
- **Module not found**: Check that lib/ directory contains the required modules
- **Temporary file issues**: Tests create files in system temp directory
- **Environment conflicts**: Tests run in subshells to avoid conflicts

### Debugging Failed Tests
1. Run individual test files to isolate issues
2. Use `--verbose` flag with the test runner
3. Check that all required modules are present
4. Verify that system has required tools (mktemp, readlink, etc.)
5. Look at assertion failure messages for specific details

### Test Performance
- Tests are designed to be fast and lightweight
- Each test case runs in isolation for reliability
- Temporary resources are automatically cleaned up
- Module loading is optimized with guard patterns