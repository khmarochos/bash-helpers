# Bash Helpers Library

A collection of reusable Bash modules designed for robust script development with modern practices, comprehensive logging, and reliable resource management.

## Overview

This library provides modular, well-documented Bash utilities that follow contemporary shell scripting best practices. Each module can be used independently or combined for enhanced functionality.

## Modules

### Core Modules

| Module | Purpose | Key Features |
|--------|---------|--------------|
| **[lifecycle.sh](#lifecycle-module)** | Complete script lifecycle management | Single-instance enforcement, resource cleanup, lazy initialization |
| **[log.sh](#logging-module)** | Enhanced logging system | Multi-level logging, file output, console control |
| **[config.sh](#configuration-module)** | Configuration management | Multi-format support (INI/JSON/YAML), environment overrides, CLI integration |

## Quick Start

### Simple Script with Lifecycle Management

```bash
#!/usr/bin/env bash

# Module loading
LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh"

# Complete single-instance setup in one call
ensure_single_instance

# Add temporary resources
temp_dir="$(mktemp -d)"
add_cleanup_item "${temp_dir}"

# Your script logic here
echo "Script running with automatic cleanup..."

# All cleanup happens automatically on exit
```

### Advanced Service Script

```bash
#!/usr/bin/env bash

# Load with configuration
LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh" --lock-file /var/run/myservice.pid --log-level DEBUG

# Complete lifecycle setup
ensure_single_instance

# Service configuration
SERVICE_NAME="myservice"
log "Starting ${SERVICE_NAME}..."

# Create runtime resources
runtime_config="$(mktemp)"
add_cleanup_item "${runtime_config}"

# Generate configuration
cat > "${runtime_config}" <<EOF
port=8080
workers=4
EOF

# Service main loop
while true; do
    debug "Service heartbeat"
    # Service logic here
    sleep 10
done
```

## Lifecycle Module

The lifecycle.sh module provides complete script lifecycle management with lazy initialization.

### Key Features

- **Zero-Configuration**: Works immediately with intelligent defaults
- **Lazy Initialization**: No side effects during module loading
- **Single-Instance Enforcement**: Automatic PID-based lock file management
- **Resource Cleanup**: Automatic cleanup of temporary files/directories
- **Signal Handling**: Graceful shutdown on INT, TERM, QUIT signals
- **Parametrization**: Command-line options and environment variables

### Primary API

```bash
# Complete lifecycle setup (recommended)
ensure_single_instance [lock_file]

# Resource management
add_cleanup_item <path>
remove_cleanup_item <path>

# Error handling
die <exit_code> <message...>
```

### Configuration Options

```bash
# Command-line options (during module sourcing)
source lib/lifecycle.sh --lock-file /var/run/app.pid --strict-lock

# Environment variables
LOCK_FILE="/var/run/app.pid" source lib/lifecycle.sh

# Global variables (set before sourcing)
LOCK_FILE="/var/run/app.pid"
CLEANUP_ON_SUCCESS=0
source lib/lifecycle.sh
```

## Logging Module

The log.sh module provides comprehensive logging with immediate initialization.

### Key Features

- **Multi-Destination Output**: Console and file logging simultaneously
- **Log Level Filtering**: DEBUG, INFO, WARN, ERROR levels
- **Performance Optimized**: Numeric boolean flags throughout
- **Command-line Configuration**: Options processed during sourcing
- **Integration Ready**: Automatic detection by other modules

### Primary API

```bash
# Logging functions
log "message"           # INFO level to stdout
warn "message"          # WARN level to stderr
error "message"         # ERROR level to stderr
debug "message"         # DEBUG level (only when LOG_LEVEL=DEBUG)
```

### Configuration Options

```bash
# Command-line options (during module sourcing)
source lib/log.sh --log-file /var/log/app.log --log-level DEBUG --be-quiet

# Environment variables
LOG_FILE="/var/log/app.log" LOG_LEVEL=DEBUG source lib/log.sh
```

## Configuration Module

The config.sh module provides comprehensive configuration management with multi-source support.

### Key Features

- **Multi-Format Support**: INI, JSON, YAML configuration files (with graceful fallbacks)
- **Priority-Based Loading**: CLI args > environment > config files > defaults
- **Environment Integration**: Automatic environment variable mapping with prefixes/suffixes
- **CLI Integration**: Command-line argument parsing with kebab-case conversion
- **Type Conversion**: Automatic type conversion with validation (string, int, bool, array)
- **Schema Validation**: Configuration validation against defined schemas
- **Live Updates**: Runtime configuration updates with validation

### Primary API

```bash
# Configuration loading and access
load_config "app.conf"                           # Load configuration
host="$(get_config "database.host" "localhost")"  # Get value with default
port="$(get_config "database.port" "5432" "int")" # Get with type conversion
enabled="$(get_config "feature.enabled" "false" "bool")" # Boolean conversion

# Configuration modification
set_config "database.timeout" "30"              # Set value
validate_config                                  # Validate all configuration
```

### Configuration Sources (Priority Order)

1. **Command-line arguments** (highest priority)
2. **Environment variables** 
3. **Configuration files** (loaded in order)
4. **Schema defaults** (lowest priority)

### Multi-Format File Support

```bash
# Load different configuration formats
load_config "config.ini"     # INI format with [sections]
load_config "config.json"    # JSON format (requires jq)
load_config "config.yaml"    # YAML format (requires yq)

# Multiple files with inheritance
load_config "base.conf" "env.conf" "local.conf"
```

### Environment Variable Integration

```bash
# Automatic environment variable patterns
export APP_DATABASE_HOST="db.example.com"        # → database.host
export CONFIG_LOG_LEVEL="DEBUG"                  # → log.level  
export MYAPP_FEATURE_ENABLED="true"              # → feature.enabled
export DATABASE_CONFIG="/path/to/db.conf"        # → database.config

# Custom prefixes and suffixes
add_config_env_prefix "MYSERVICE_"    # Scan MYSERVICE_* variables
add_config_env_suffix "_CFG"          # Scan *_CFG variables

# Explicit mappings for precise control
define_config_overrides env "DB_HOST" "database.host"
define_config_overrides env "DB_PORT" "database.port"
```

### Command-Line Integration

```bash
# Traditional config prefix
./script.sh --config-database.host=db.example.com --config-port=5432

# Automatic kebab-case conversion  
./script.sh --database-host=db.example.com --log-level=DEBUG

# Short options (with explicit mapping)
define_config_overrides short "-h" "database.host"
./script.sh -h db.example.com

# Mixed formats
./script.sh --config-file app.conf --database-host=prod.db.com --verbose
```

### Configuration File Formats

#### INI Format (.ini, .conf, .cfg)
```ini
# Basic key-value pairs
debug=true
timeout=30

# Sections for hierarchical structure
[database]
host=localhost
port=5432
username=app_user

[logging]
level=INFO
file=/var/log/app.log
```

#### JSON Format (.json)
```json
{
  "database": {
    "host": "localhost",
    "port": 5432,
    "ssl": true
  },
  "logging": {
    "level": "INFO",
    "console": true
  }
}
```

#### YAML Format (.yaml, .yml)  
```yaml
database:
  host: localhost
  port: 5432
  ssl: true

logging:
  level: INFO
  console: true
```

### Advanced Configuration Management

```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/config.sh"

# Define custom environment mappings
define_config_overrides env "DB_URL" "database.connection_string"
define_config_overrides cli "--db-url" "database.connection_string"

# Add custom prefixes for environment scanning
add_config_env_prefix "MYAPP_"
add_config_env_suffix "_CONFIG"

# Parse command-line options first (highest priority)
parse_config_options "$@"

# Load configuration from multiple sources
load_config "/etc/myapp/default.conf" "~/.myapp.conf" "./local.conf"

# Access configuration with type conversion
db_host="$(get_config "database.host" "localhost")"
db_port="$(get_config "database.port" "5432" "int")"
ssl_enabled="$(get_config "database.ssl" "false" "bool")"
allowed_hosts="$(get_config "security.allowed_hosts" "" "array")"

# Validate configuration
if ! validate_config; then
    die 1 "Configuration validation failed"
fi

log "Database: ${db_host}:${db_port} (SSL: ${ssl_enabled})"
```

## Global Variables Reference

⚠️ **Important**: Review these global variables to avoid naming conflicts in your scripts.

### Lifecycle Module (lifecycle.sh)

#### Readonly Constants (Cannot be overwritten)
- `LOGGER_OUT` - Output stream constant (value: "1")
- `LOGGER_ERR` - Error stream constant (value: "2") 
- `LIFECYCLE_MODULE_LOADED` - Module loaded marker (value: 1)

#### Configuration Variables (Can be set by user)
- `LOCK_FILE` - Path to lock file (default: `/tmp/${USER}-${script_name}.lock`)
- `CLEANUP_ON_SUCCESS` - Cleanup on successful completion (1=yes, 0=no, default: 1)
- `CLEANUP_ON_ERROR` - Cleanup on error/signal (1=yes, 0=no, default: 1)
- `STRICT_LOCK_CHECK` - Strict PID validation (1=strict, 0=permissive, default: 1)
- `LOCK_WAIT_TIMEOUT` - Lock acquisition timeout in seconds (default: 0)

#### Internal State Variables (Should not be modified by user)
- `TO_BE_REMOVED` - Array of items to clean up on exit
- `CLEANUP_TRAPS_INSTALLED` - Track whether signal traps are installed (1=installed, 0=not)

### Logging Module (log.sh)

#### Readonly Constants (Cannot be overwritten)
- `LOGGER_OUT` - Output stream constant (value: "1")
- `LOGGER_ERR` - Error stream constant (value: "2")
- `LOG_MODULE_LOADED` - Module loaded marker (value: 1)

#### Configuration Variables (Can be set by user)
- `LOG_FILE` - Path to log file (empty = no file logging)
- `LOG_TIME_FORMAT` - Timestamp format (default: "+%Y-%m-%d %H:%M:%S")
- `LOG_LEVEL` - Minimum log level (DEBUG, INFO, WARN, ERROR, default: INFO)
- `BE_QUIET` - Suppress console output (1=quiet, 0=normal, default: 0)
- `BE_VERBOSE` - Enable verbose output (1=verbose, 0=normal, default: 0)

### Configuration Module (config.sh)

#### Readonly Constants (Cannot be overwritten)
- `CONFIG_OUT` - Output stream constant (value: "1")
- `CONFIG_ERR` - Error stream constant (value: "2")
- `CONFIG_MODULE_LOADED` - Module loaded marker (value: 1)

#### Configuration Variables (Can be set by user)
- `CONFIG_FILES` - Array of configuration file paths to load
- `CONFIG_ENV_PREFIXES` - Space-separated prefixes to scan (default: "APP_ CONFIG_ MYAPP_")
- `CONFIG_ENV_SUFFIXES` - Space-separated suffixes to scan (default: "_CONFIG")
- `CONFIG_AUTO_TRANSFORM_KEYS` - Auto-transform key formats (1=yes, 0=no, default: 1)
- `CONFIG_STRICT_MODE` - Strict validation (1=strict, 0=permissive, default: 1)
- `CONFIG_ALLOW_UNDEFINED` - Allow undefined keys (1=yes, 0=no, default: 0)
- `CONFIG_CASE_SENSITIVE` - Case-sensitive keys (1=yes, 0=no, default: 0)

#### Internal State Variables (Should not be modified by user)
- `CONFIG_VALUES` - Associative array storing configuration key-value pairs
- `CONFIG_SOURCES` - Associative array tracking source of each configuration value
- `CONFIG_TYPES` - Associative array storing type information for each key
- `CONFIG_SCHEMA` - Associative array storing schema definitions
- `CONFIG_ENV_MAPPINGS` - Environment variable to config key mappings
- `CONFIG_CLI_MAPPINGS` - CLI argument to config key mappings
- `CONFIG_CLI_SHORT_OPTS` - Short option to config key mappings

### ⚠️ Potential Conflicts and Warnings

#### Variable Name Conflicts
- **Avoid variables starting with**: `CLEANUP_`, `LOCK_`, `LOGGER_`, `LOG_`, `BE_`, `CONFIG_`
- **Arrays**: Don't modify `TO_BE_REMOVED` or `CONFIG_*` arrays directly - use provided functions
- **Function Names**: Avoid function names matching module functions

#### Signal Trap Conflicts
- **lifecycle.sh overrides these signal traps**: `EXIT`, `INT`, `TERM`, `QUIT`
- **Warning**: Existing traps for these signals will be replaced
- **Solution**: Use `add_cleanup_item()` to register cleanup instead of custom traps

#### Environment Variable Precedence
- **Environment variables take precedence** over script defaults
- **Example**: If `LOCK_FILE` is set in environment, it overrides script assignments
- **Check with**: `echo "LOCK_FILE=${LOCK_FILE}"`

#### File Path Validation
- **lifecycle.sh uses `rm -rf`** on cleanup items - validate paths before adding
- **log.sh writes to `LOG_FILE`** - ensure directory exists and is writable
- **Lock files**: Default to `/tmp/${USER}-${script}.lock` - ensure `/tmp` is writable

## Common Usage Patterns

### Temporary File Management

```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh"

ensure_single_instance

# Create temporary resources with automatic cleanup
temp_dir="$(mktemp -d)"
temp_file="${temp_dir}/data.tmp"
add_cleanup_item "${temp_dir}"  # Will remove entire directory

# Use temporary resources
echo "processing data" > "${temp_file}"
process_file "${temp_file}"

# Cleanup happens automatically on exit (success or error)
```

### Configuration Validation

```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh"

ensure_single_instance

CONFIG_FILE="${1:-/etc/myapp/config.conf}"

# Validate configuration with automatic cleanup on error
[[ -f "${CONFIG_FILE}" ]] || die 1 "Configuration file not found: ${CONFIG_FILE}"
[[ -r "${CONFIG_FILE}" ]] || die 2 "Configuration file not readable: ${CONFIG_FILE}"

source "${CONFIG_FILE}"
[[ -n "${REQUIRED_SETTING}" ]] || die 3 "Missing required setting: REQUIRED_SETTING"

log "Configuration loaded successfully"
```

### Service with Resource Management

```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh" --lock-file /var/run/myservice.pid

ensure_single_instance

# Create service runtime directory
runtime_dir="/var/run/myservice"
mkdir -p "${runtime_dir}" || die 1 "Cannot create runtime directory"
add_cleanup_item "${runtime_dir}"

# Create PID file in runtime directory  
pidfile="${runtime_dir}/service.pid"
echo $$ > "${pidfile}"
add_cleanup_item "${pidfile}"

# Service main loop
log "Service started with PID $$"
while true; do
    # Service logic here
    debug "Service heartbeat"
    sleep 10
done
```

### Conditional Cleanup

```bash
#!/usr/bin/env bash

# Configure cleanup behavior
source lib/lifecycle.sh --no-cleanup-on-success --cleanup-on-error

ensure_single_instance

work_dir="$(mktemp -d)"
add_cleanup_item "${work_dir}"

# Process data
if process_data "${work_dir}"; then
    echo "Success! Work directory preserved at: ${work_dir}"
    # work_dir is NOT cleaned up due to --no-cleanup-on-success
    remove_cleanup_item "${work_dir}"  # Remove from cleanup list
    mv "${work_dir}" "/var/lib/myapp/results"
else
    echo "Failed! Work directory will be cleaned up automatically"
    # work_dir IS cleaned up due to --cleanup-on-error
    die 1 "Processing failed"
fi
```

## Command Line Options

### Lifecycle Options

```bash
# Lock file configuration
./script.sh --lock-file /var/run/myapp.pid

# Cleanup behavior
./script.sh --no-cleanup-on-success --cleanup-on-error

# Lock validation
./script.sh --strict-lock          # Strict PID validation (default)
./script.sh --permissive-lock      # Permissive lock handling

# Timeout configuration
./script.sh --lock-timeout 30      # Wait up to 30 seconds for lock
```

### Logging Options  

```bash
# File logging
./script.sh --log-file /var/log/script.log

# Log levels
./script.sh --log-level DEBUG
./script.sh --log-level ERROR

# Output control
./script.sh --be-quiet             # Suppress console output
./script.sh --be-verbose           # Enable debug output

# Combined options
./script.sh --log-file /var/log/app.log --log-level DEBUG --be-quiet
```

### Configuration Options

```bash
# Configuration file loading
./script.sh --config-file /etc/myapp/config.conf --config-file ~/.myapp.conf

# Configuration value overrides
./script.sh --config-database.host=prod.db.com --config-port=5432

# Automatic kebab-case conversion
./script.sh --database-host=prod.db.com --log-level=DEBUG

# Configuration behavior
./script.sh --strict-config        # Enable strict validation
./script.sh --permissive-config    # Enable permissive validation
./script.sh --auto-transform-keys   # Enable automatic key transformation
```

### Environment Variables

```bash
# Lifecycle configuration
LOCK_FILE="/var/run/app.pid" CLEANUP_ON_SUCCESS=0 ./script.sh

# Logging configuration  
LOG_FILE="/var/log/app.log" LOG_LEVEL=DEBUG BE_QUIET=1 ./script.sh

# Combined configuration
LOCK_FILE="/var/run/app.pid" LOG_FILE="/var/log/app.log" LOG_LEVEL=DEBUG ./script.sh
```

## Best Practices

### Module Loading

```bash
# Good: Determine library directory dynamically
LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"

# Good: Load modules in logical order (logging first)
source "${LIB_DIR}/log.sh"
source "${LIB_DIR}/lifecycle.sh"

# Good: Check if critical modules exist
[[ -f "${LIB_DIR}/lifecycle.sh" ]] || {
    echo "Error: Required module not found: ${LIB_DIR}/lifecycle.sh" >&2
    exit 1
}
```

### Variable Naming Conventions

```bash
# Follow the global variable naming conventions
local_var="value"              # Local variables: lowercase with underscores
GLOBAL_VAR="value"             # Global variables: UPPERCASE
readonly CONSTANT_VAR="value"  # Constants: UPPERCASE with readonly

# Avoid conflicts with module variables
my_lock_file="/tmp/my.lock"    # Good: doesn't conflict
LOCK_FILE="/tmp/my.lock"       # Caution: may override module default
```

### Error Handling

```bash
# Use consistent exit codes
die 0   # Success (though die() shouldn't be used for success)
die 1   # General error
die 2   # Misuse of shell command

# Application-specific codes
die 10  # Configuration error
die 11  # Network error
die 12  # Database error
die 13  # Permission error
```

### Resource Management

```bash
# Good: Add to cleanup immediately after creation
temp_file="$(mktemp)"
add_cleanup_item "${temp_file}"

# Good: Remove from cleanup when resource becomes permanent
if process_and_save "${temp_file}" "${permanent_location}"; then
    remove_cleanup_item "${temp_file}"
fi

# Avoid: Manual cleanup (unless special circumstances)
# rm -f "${temp_file}"  # Let the module handle this
```

## Testing

### Basic Test Script

```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh" --log-level DEBUG

echo "Testing lifecycle module..."

# Test single instance
ensure_single_instance

# Test resource cleanup
temp_file="$(mktemp)"
add_cleanup_item "${temp_file}"
echo "test data" > "${temp_file}"

[[ -f "${temp_file}" ]] || die 1 "Temporary file not created"

echo "Test completed - cleanup should happen automatically"
```

### Module Integration Test

```bash
#!/usr/bin/env bash

# Test with both modules
LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/log.sh" --log-level DEBUG
source "${LIB_DIR}/lifecycle.sh"

log "Starting integration test..."

ensure_single_instance

temp_dir="$(mktemp -d)"
add_cleanup_item "${temp_dir}"

log "Created temporary directory: ${temp_dir}"
debug "Cleanup will happen automatically on exit"

# Test error handling
[[ -d "${temp_dir}" ]] || die 1 "Temporary directory not created"

log "Integration test completed successfully"
```

## Troubleshooting

### Common Issues

**Module not found:**
```bash
# Debug module loading
LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
echo "Looking for modules in: ${LIB_DIR}"
ls -la "${LIB_DIR}/"
```

**Variable conflicts:**
```bash
# Check for conflicts before sourcing
echo "Current LOCK_FILE: ${LOCK_FILE:-<unset>}"
echo "Current LOG_FILE: ${LOG_FILE:-<unset>}"

# Source modules
source "${LIB_DIR}/lifecycle.sh"

# Check values after sourcing
echo "Final LOCK_FILE: ${LOCK_FILE}"
echo "Module loaded: ${LIFECYCLE_MODULE_LOADED}"
```

**Lock file permissions:**
```bash
# Test lock file creation
test_lock="/tmp/test-${USER}.lock"
echo $$ > "${test_lock}" || {
    echo "Cannot create lock file in /tmp" >&2
    exit 1
}
rm -f "${test_lock}"
```

**Signal trap conflicts:**
```bash
# Check existing traps before module loading
trap -p EXIT INT TERM QUIT

# Load module
source "${LIB_DIR}/lifecycle.sh"

# Check traps after loading
trap -p EXIT INT TERM QUIT
```

### Debug Mode

```bash
# Enable comprehensive debugging
export LOG_LEVEL=DEBUG
export BE_VERBOSE=1

# Run with debug output
./your_script.sh --be-verbose --log-level DEBUG
```

### Module State Inspection

```bash
# Check module loading state
echo "Lifecycle module loaded: ${LIFECYCLE_MODULE_LOADED:-0}"
echo "Log module loaded: ${LOG_MODULE_LOADED:-0}"

# Check cleanup state
echo "Cleanup items: ${#TO_BE_REMOVED[@]}"
echo "Traps installed: ${CLEANUP_TRAPS_INSTALLED:-0}"

# List cleanup items
for item in "${TO_BE_REMOVED[@]}"; do
    echo "  Will cleanup: ${item}"
done
```

## Contributing

When adding new modules or modifying existing ones:

1. **Follow established conventions**: Variable naming, function documentation, error handling
2. **Document global variables**: List all global variables with conflict warnings
3. **Maintain backward compatibility**: Existing scripts should continue to work
4. **Add comprehensive tests**: Test normal operation, error conditions, and edge cases
5. **Update documentation**: Include usage examples and integration patterns
6. **Consider conflicts**: Avoid variable names that might conflict with user scripts

## License

This project follows the MIT License. See individual module files for specific licensing information.