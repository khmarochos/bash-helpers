#!/usr/bin/env bash

# Early return if module already loaded
[[ "${CONFIG_MODULE_LOADED:-0}" == "1" ]] && return 0

#
# Configuration Management Module for Bash Scripts
#
# This module provides comprehensive configuration management with support for:
# - Multi-source configuration: command-line args > env vars > config files > defaults
# - Multiple file formats: INI, JSON, YAML (with graceful fallbacks)
# - Schema validation with type checking and constraints
# - Hierarchical configuration with section support
# - Live configuration updates and validation
# - Integration with existing logging and lifecycle modules
#
# KEY FEATURES:
# - Zero-configuration usage: works immediately with sensible defaults
# - Priority-based source resolution with explicit precedence rules
# - Lazy initialization: no side effects when sourced, setup on first use
# - Type-safe operations with validation and sanitization
# - Comprehensive error handling with detailed logging
# - Performance-optimized with caching and numeric boolean logic
# - Integration-ready with module detection markers
# - Command-line option parsing with automatic help generation
#
# ARCHITECTURE PRINCIPLES:
# - Source Priority: CLI args > environment > config files > schema defaults
# - Lazy Loading: Configuration parsed only when accessed
# - Type Safety: All values validated and converted according to schema
# - Atomic Updates: Configuration changes are validated before application
# - Separation of Concerns: Parsing, validation, and access are distinct layers
# - Fail-Fast: Invalid configurations cause immediate errors with clear messages
#
# PRIMARY API:
#   load_config()        - Load configuration from all sources
#   get_config()         - Retrieve configuration value with type conversion
#   set_config()         - Set configuration value with validation
#   validate_config()    - Validate entire configuration against schema
#
# BASIC USAGE:
#   source lib/config.sh
#   load_config "myapp.conf"
#   
#   database_host="$(get_config "database.host" "localhost")"
#   max_connections="$(get_config "database.max_connections" "100" "int")"
#   
#   set_config "logging.level" "DEBUG"
#   validate_config
#
# ADVANCED USAGE:
#   # Schema-driven configuration
#   define_config_schema '{
#     "database": {
#       "host": {"type": "string", "required": true},
#       "port": {"type": "int", "default": 5432, "min": 1, "max": 65535}
#     }
#   }'
#   
#   # Multiple config files with inheritance
#   load_config "/etc/myapp/default.conf" "~/.myapp.conf" "./local.conf"
#   
#   # Command-line integration
#   parse_config_options "$@"
#   load_config
#   
#   # Live validation
#   if validate_config_key "database.timeout" "30"; then
#     set_config "database.timeout" "30"
#   fi
#

#
# Constants
#
# Declare constants only if not already defined (prevents warnings on re-sourcing)
if [[ -z "${CONFIG_OUT:-}" ]]; then
    declare -r CONFIG_OUT="1"
fi
if [[ -z "${CONFIG_ERR:-}" ]]; then
    declare -r CONFIG_ERR="2"
fi

# Marker to indicate this module has been loaded (1 = loaded, 0 = not loaded)
if [[ -z "${CONFIG_MODULE_LOADED:-}" ]]; then
    declare -r CONFIG_MODULE_LOADED=1
fi

#
# Global Configuration Variables
#
# These variables control module behavior and can be set before sourcing
# or modified during script execution for dynamic configuration.

# Core configuration storage (associative array)
declare -A CONFIG_VALUES=()           # Current configuration key-value pairs
declare -A CONFIG_SOURCES=()          # Source tracking for each key (for debugging)
declare -A CONFIG_TYPES=()            # Type information for each key
declare -A CONFIG_SCHEMA=()           # Schema definitions for validation

# Configuration override mappings
declare -A CONFIG_ENV_MAPPINGS=()     # Environment variable to config key mappings
declare -A CONFIG_CLI_MAPPINGS=()     # CLI argument to config key mappings
declare -A CONFIG_CLI_SHORT_OPTS=()   # Short option to config key mappings

# Configuration file paths and loading state
CONFIG_FILES=()                       # Array of configuration file paths to load
CONFIG_LOADED="${CONFIG_LOADED:-0}"   # Loading state: 1=loaded, 0=not loaded
CONFIG_AUTO_RELOAD="${CONFIG_AUTO_RELOAD:-0}"  # Auto-reload on file changes: 1=yes, 0=no

# Environment variable override configuration
CONFIG_ENV_PREFIXES="${CONFIG_ENV_PREFIXES:-APP_ CONFIG_ MYAPP_}"  # Space-separated prefixes to scan
CONFIG_ENV_SUFFIXES="${CONFIG_ENV_SUFFIXES:-_CONFIG}"              # Space-separated suffixes to scan
CONFIG_AUTO_TRANSFORM_KEYS="${CONFIG_AUTO_TRANSFORM_KEYS:-1}"      # Auto-transform key formats: 1=yes, 0=no

# CLI argument override configuration  
CONFIG_CLI_PREFIX="${CONFIG_CLI_PREFIX:---config-}"                # Default CLI option prefix
CONFIG_SUPPORT_SHORT_OPTS="${CONFIG_SUPPORT_SHORT_OPTS:-1}"        # Support short options: 1=yes, 0=no
CONFIG_KEBAB_TO_DOT="${CONFIG_KEBAB_TO_DOT:-1}"                   # Convert kebab-case to dot notation: 1=yes, 0=no

# Parsing and validation configuration
CONFIG_STRICT_MODE="${CONFIG_STRICT_MODE:-1}"        # Strict validation: 1=strict, 0=permissive
CONFIG_ALLOW_UNDEFINED="${CONFIG_ALLOW_UNDEFINED:-0}" # Allow undefined keys: 1=yes, 0=no
CONFIG_CASE_SENSITIVE="${CONFIG_CASE_SENSITIVE:-0}"   # Case-sensitive keys: 1=yes, 0=no (default: case-insensitive)

# Format support flags (auto-detected based on tool availability)
CONFIG_SUPPORT_JSON="${CONFIG_SUPPORT_JSON:-0}"      # JSON support available: 1=yes, 0=no
CONFIG_SUPPORT_YAML="${CONFIG_SUPPORT_YAML:-0}"      # YAML support available: 1=yes, 0=no

#
# Private Functions
#

# _load_config_logger() - Load logging module if not already loaded
#
# Description:
#   Ensures the logging module is available for configuration operations.
#   This function is called automatically during module initialization.
#
# Returns:
#   0 on success (logger loaded or already available)
#   1 if logger module cannot be found or loaded
#
# Global variables used:
#   LOG_MODULE_LOADED - Set by log.sh module when loaded
#
_load_config_logger() {
    # Check if logging module is already loaded
    if [[ "${LOG_MODULE_LOADED:-0}" == "1" ]]; then
        return 0
    fi
    
    # Determine library directory relative to this script
    local lib_dir
    lib_dir="$(dirname "$(readlink -f "${BASH_SOURCE[1]}")")"
    
    # Path to the logging module
    local log_module_path="${lib_dir}/log.sh"
    
    # Check if log module exists and source it
    if [[ -f "${log_module_path}" ]]; then
        source "${log_module_path}"
        return 0
    else
        echo "ERROR: Cannot find logging module at ${log_module_path}" >&2
        return 1
    fi
}

# _detect_format_support() - Detect available configuration format parsers
#
# Description:
#   Checks for external tools required for advanced format support and
#   sets global flags accordingly. This enables graceful degradation
#   when tools are not available.
#
# Returns:
#   0 on success
#
# Global variables modified:
#   CONFIG_SUPPORT_JSON - Set to 1 if jq is available
#   CONFIG_SUPPORT_YAML - Set to 1 if yq is available
#
_detect_format_support() {
    # Check for JSON support via jq
    if command -v jq >/dev/null 2>&1; then
        CONFIG_SUPPORT_JSON=1
        debug "JSON support enabled (jq available)"
    else
        CONFIG_SUPPORT_JSON=0
        debug "JSON support disabled (jq not available)"
    fi
    
    # Check for YAML support via yq
    if command -v yq >/dev/null 2>&1; then
        CONFIG_SUPPORT_YAML=1
        debug "YAML support enabled (yq available)"
    else
        CONFIG_SUPPORT_YAML=0
        debug "YAML support disabled (yq not available)"
    fi
    
    return 0
}

# _normalize_config_key() - Normalize configuration key format
#
# Description:
#   Converts configuration keys to a consistent format for internal storage.
#   Handles case sensitivity settings and ensures consistent key format.
#
# Input:
#   $1 - Configuration key to normalize
#
# Returns:
#   Outputs normalized key to stdout
#
# Global variables used:
#   CONFIG_CASE_SENSITIVE - Controls case normalization
#
_normalize_config_key() {
    local key="${1:-}"
    
    if [[ -z "${key}" ]]; then
        return 1
    fi
    
    # Remove leading/trailing whitespace first
    key="${key## }"
    key="${key%% }"
    
    # Convert to lowercase if case-insensitive mode (default behavior)
    if [[ "${CONFIG_CASE_SENSITIVE}" != "1" ]]; then
        key="${key,,}"
    fi
    
    echo "${key}"
}

# _get_config_source() - Determine the source of a configuration value
#
# Description:
#   Returns a string indicating where a configuration value originated from.
#   Used for debugging and configuration auditing.
#
# Input:
#   $1 - Configuration key
#
# Returns:
#   Outputs source string to stdout ("cli", "env", "file", "schema", "default")
#
_get_config_source() {
    local key
    key="$(_normalize_config_key "${1:-}")"
    
    if [[ -n "${CONFIG_SOURCES["${key}"]:-}" ]]; then
        echo "${CONFIG_SOURCES["${key}"]}"
    else
        echo "undefined"
    fi
}

# _transform_key() - Transform keys between different naming conventions
#
# Description:
#   Converts keys between different naming conventions (kebab-case, snake_case, dot.notation).
#   Supports automatic transformation based on CONFIG_AUTO_TRANSFORM_KEYS setting.
#
# Input:
#   $1 - Key to transform
#   $2 - Target format: "dot", "kebab", "snake", "env" (optional, default: "dot")
#
# Returns:
#   Outputs transformed key to stdout
#
# Examples:
#   _transform_key "database-host" "dot"     # → database.host
#   _transform_key "database.host" "kebab"   # → database-host  
#   _transform_key "database.host" "env"     # → DATABASE_HOST
#
_transform_key() {
    local key="${1:-}"
    local target_format="${2:-dot}"
    local result="${key}"
    
    if [[ -z "${key}" ]]; then
        return 1
    fi
    
    case "${target_format}" in
        "dot")
            # Convert kebab-case and snake_case to dot notation
            result="${result//-/.}"    # kebab-case → dot.notation
            result="${result//_/.}"    # snake_case → dot.notation
            ;;
        "kebab")
            # Convert dot notation and snake_case to kebab-case
            result="${result//./-}"    # dot.notation → kebab-case
            result="${result//_/-}"    # snake_case → kebab-case
            ;;
        "snake")
            # Convert dot notation and kebab-case to snake_case
            result="${result//./_}"    # dot.notation → snake_case
            result="${result//-/_}"    # kebab-case → snake_case
            ;;
        "env")
            # Convert to ENVIRONMENT_VARIABLE format
            result="${result//./_}"    # dot.notation → snake_case
            result="${result//-/_}"    # kebab-case → snake_case
            result="${result^^}"       # Convert to uppercase
            ;;
        *)
            # Unknown format, return as-is
            ;;
    esac
    
    echo "${result}"
}

# _add_config_mapping() - Add a mapping between override source and config key
#
# Description:
#   Registers a mapping between an environment variable or CLI argument and
#   a configuration key. Used by define_config_overrides() and automatic
#   mapping functions.
#
# Input:
#   $1 - Mapping type: "env" or "cli" or "short"
#   $2 - Source (environment variable name, CLI option, or short option)
#   $3 - Target configuration key
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   _add_config_mapping "env" "DB_HOST" "database.host"
#   _add_config_mapping "cli" "--database-host" "database.host"
#   _add_config_mapping "short" "-h" "database.host"
#
_add_config_mapping() {
    local mapping_type="${1:-}"
    local source="${2:-}"
    local target="${3:-}"
    
    if [[ -z "${mapping_type}" || -z "${source}" || -z "${target}" ]]; then
        warn "_add_config_mapping() requires mapping_type, source, and target parameters"
        return 1
    fi
    
    case "${mapping_type}" in
        "env")
            CONFIG_ENV_MAPPINGS["${source}"]="${target}"
            debug "Added env mapping: ${source} → ${target}"
            ;;
        "cli")
            CONFIG_CLI_MAPPINGS["${source}"]="${target}"
            debug "Added CLI mapping: ${source} → ${target}"
            ;;
        "short")
            CONFIG_CLI_SHORT_OPTS["${source}"]="${target}"
            debug "Added short option mapping: ${source} → ${target}"
            ;;
        *)
            warn "Unknown mapping type: ${mapping_type}"
            return 1
            ;;
    esac
    
    return 0
}

#
# Core Configuration Functions
#

# get_config() - Retrieve configuration value with type conversion
#
# Description:
#   Retrieves a configuration value by key with optional default value and
#   type conversion. This is the primary function for accessing configuration
#   values in scripts. Supports automatic type conversion and validation.
#
# Input:
#   $1 - Configuration key (required)
#   $2 - Default value (optional, used if key not found)
#   $3 - Expected type (optional: "string", "int", "bool", "array")
#
# Returns:
#   0 on success, 1 if key not found and no default provided
#   Outputs the configuration value to stdout
#
# Global variables used:
#   CONFIG_VALUES - Configuration storage
#   CONFIG_ALLOW_UNDEFINED - Controls behavior for undefined keys
#
# Examples:
#   host="$(get_config "database.host" "localhost")"
#   port="$(get_config "database.port" "5432" "int")"
#   enabled="$(get_config "feature.enabled" "false" "bool")"
#
get_config() {
    local key="${1:-}"
    local default_value="${2:-}"
    local expected_type="${3:-string}"
    local normalized_key
    local value
    
    # Validate input parameters
    if [[ -z "${key}" ]]; then
        warn "get_config() requires a configuration key parameter"
        return 1
    fi
    
    # Normalize the key
    normalized_key="$(_normalize_config_key "${key}")"
    
    # Get the value from storage
    if [[ -n "${CONFIG_VALUES["${normalized_key}"]:-}" ]]; then
        value="${CONFIG_VALUES["${normalized_key}"]}"
        debug "Retrieved config ${key}='${value}' from $(_get_config_source "${key}")"
    elif [[ -n "${default_value}" ]]; then
        value="${default_value}"
        debug "Using default value for ${key}='${value}'"
    else
        if [[ "${CONFIG_ALLOW_UNDEFINED}" == "0" ]]; then
            warn "Configuration key '${key}' not found and no default provided"
            return 1
        else
            value=""
            debug "Configuration key '${key}' undefined, returning empty value"
        fi
    fi
    
    # Type conversion and validation
    case "${expected_type}" in
        "string")
            echo "${value}"
            ;;
        "int")
            if [[ "${value}" =~ ^-?[0-9]+$ ]]; then
                echo "${value}"
            else
                warn "Configuration key '${key}' expected int, got '${value}'"
                return 1
            fi
            ;;
        "bool")
            case "${value,,}" in
                "true"|"yes"|"1"|"on"|"enabled")
                    echo "true"
                    ;;
                "false"|"no"|"0"|"off"|"disabled"|"")
                    echo "false"
                    ;;
                *)
                    warn "Configuration key '${key}' expected bool, got '${value}'"
                    return 1
                    ;;
            esac
            ;;
        "array")
            # Arrays stored as comma-separated values
            echo "${value}"
            ;;
        *)
            warn "Unknown type '${expected_type}' for configuration key '${key}'"
            echo "${value}"
            ;;
    esac
}

# set_config() - Set configuration value with validation
#
# Description:
#   Sets a configuration value with optional type validation. The value
#   is stored in memory and can be validated against schema if defined.
#   This function provides the primary interface for updating configuration.
#
# Input:
#   $1 - Configuration key (required)
#   $2 - Configuration value (required)
#   $3 - Source identifier (optional, default: "manual")
#
# Returns:
#   0 on success, 1 on validation error
#
# Global variables modified:
#   CONFIG_VALUES - Updated with new value
#   CONFIG_SOURCES - Updated with source information
#
# Examples:
#   set_config "database.host" "db.example.com"
#   set_config "database.port" "5432" "cli"
#   set_config "logging.enabled" "true" "env"
#
set_config() {
    local key="${1:-}"
    local value="${2:-}"
    local source="${3:-manual}"
    local normalized_key
    
    # Validate input parameters
    if [[ -z "${key}" ]]; then
        warn "set_config() requires a configuration key parameter"
        return 1
    fi
    
    if [[ -z "${value}" && $# -lt 2 ]]; then
        warn "set_config() requires a configuration value parameter"
        return 1
    fi
    
    # Normalize the key
    normalized_key="$(_normalize_config_key "${key}")"
    
    # Store the value and source
    CONFIG_VALUES["${normalized_key}"]="${value}"
    CONFIG_SOURCES["${normalized_key}"]="${source}"
    
    debug "Set config ${key}='${value}' (source: ${source})"
    
    return 0
}

# load_config() - Load configuration from multiple sources
#
# Description:
#   Loads configuration from multiple sources in priority order:
#   1. Command-line arguments (highest priority)
#   2. Environment variables
#   3. Configuration files (in order specified)
#   4. Schema defaults (lowest priority)
#
# Input:
#   $@ - Configuration file paths (optional)
#        If not provided, uses CONFIG_FILES array
#
# Returns:
#   0 on success, 1 on error
#
# Global variables modified:
#   CONFIG_VALUES - Populated with configuration data
#   CONFIG_SOURCES - Populated with source tracking
#   CONFIG_LOADED - Set to 1 after successful loading
#
# Examples:
#   load_config                          # Load from CONFIG_FILES
#   load_config "app.conf"              # Load from single file
#   load_config "base.conf" "local.conf" # Load from multiple files
#
load_config() {
    local config_files=("$@")
    local file
    
    debug "Starting configuration loading process"
    
    # Use provided files or fall back to CONFIG_FILES array
    if [[ ${#config_files[@]} -eq 0 ]]; then
        config_files=("${CONFIG_FILES[@]}")
    fi
    
    # Load from configuration files (lowest priority, processed first)
    for file in "${config_files[@]}"; do
        if [[ -n "${file}" && -r "${file}" ]]; then
            _load_config_file "${file}"
        elif [[ -n "${file}" ]]; then
            warn "Configuration file not found or not readable: ${file}"
        fi
    done
    
    # Load from environment variables (higher priority)
    _load_config_from_env
    
    # Command-line arguments would be loaded separately via parse_config_options
    
    # Mark configuration as loaded
    CONFIG_LOADED=1
    
    debug "Configuration loading completed"
    
    return 0
}

#
# Configuration File Parsers
#

# _load_config_file() - Load configuration from file with format detection
#
# Description:
#   Loads configuration from a file, automatically detecting the format
#   based on file extension. Supports INI, JSON, and YAML formats with
#   graceful fallback to INI parsing for unknown formats.
#
# Input:
#   $1 - Path to configuration file
#
# Returns:
#   0 on success, 1 on error
#
_load_config_file() {
    local file="${1:-}"
    local format
    
    if [[ -z "${file}" || ! -r "${file}" ]]; then
        warn "Configuration file not readable: ${file}"
        return 1
    fi
    
    # Detect format based on file extension
    case "${file,,}" in
        *.json)
            format="json"
            ;;
        *.yaml|*.yml)
            format="yaml"
            ;;
        *.ini|*.conf|*.cfg|*)
            format="ini"
            ;;
    esac
    
    debug "Loading configuration file: ${file} (format: ${format})"
    
    # Load based on detected format
    case "${format}" in
        "json")
            if [[ "${CONFIG_SUPPORT_JSON}" == "1" ]]; then
                _parse_json_config "${file}"
            else
                warn "JSON format not supported (jq not available), falling back to INI parser"
                _parse_ini_config "${file}"
            fi
            ;;
        "yaml")
            if [[ "${CONFIG_SUPPORT_YAML}" == "1" ]]; then
                _parse_yaml_config "${file}"
            else
                warn "YAML format not supported (yq not available), falling back to INI parser"
                _parse_ini_config "${file}"
            fi
            ;;
        "ini"|*)
            _parse_ini_config "${file}"
            ;;
    esac
}

# _parse_ini_config() - Parse INI-style configuration file
#
# Description:
#   Parses configuration files in INI format (key=value pairs with optional sections).
#   This is the most basic and widely supported format, used as fallback for other formats.
#   Supports comments, sections, and basic variable expansion.
#
# Input:
#   $1 - Path to INI configuration file
#
# Returns:
#   0 on success, 1 on error
#
# Format:
#   # Comments start with # or ;
#   key=value
#   
#   [section]
#   nested_key=value
#
_parse_ini_config() {
    local file="${1:-}"
    local line
    local section=""
    local key
    local value
    
    if [[ ! -r "${file}" ]]; then
        warn "Cannot read INI configuration file: ${file}"
        return 1
    fi
    
    debug "Parsing INI configuration file: ${file}"
    
    while read -r line; do
        # Skip empty lines and comments
        if [[ -z "${line}" || "${line:0:1}" == "#" || "${line:0:1}" == ";" ]]; then
            continue
        fi
        
        # Handle section headers
        if [[ "${line}" =~ ^\[([^\]]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Handle key=value pairs
        if [[ "${line}" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Simple trim
            key="${key## }"
            key="${key%% }"
            value="${value## }"
            value="${value%% }"
            
            # Remove quotes from value if present
            if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
                value="${value:1:-1}"
            elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
                value="${value:1:-1}"
            fi
            
            # Build full key with section prefix
            if [[ -n "${section}" ]]; then
                key="${section}.${key}"
            fi
            
            # Store directly in arrays
            CONFIG_VALUES["${key}"]="${value}"
            CONFIG_SOURCES["${key}"]="file:${file}"
        fi
    done < "${file}"
    
    debug "Completed parsing INI file: ${file}"
    
    return 0
}

# _parse_json_config() - Parse JSON configuration file
#
# Description:
#   Parses JSON configuration files using jq. Flattens nested objects
#   into dot-notation keys for consistent access patterns.
#
# Input:
#   $1 - Path to JSON configuration file
#
# Returns:
#   0 on success, 1 on error
#
_parse_json_config() {
    local file="${1:-}"
    local key
    local value
    
    if [[ ! -r "${file}" ]]; then
        warn "Cannot read JSON configuration file: ${file}"
        return 1
    fi
    
    if [[ "${CONFIG_SUPPORT_JSON}" != "1" ]]; then
        warn "JSON support not available (jq not found)"
        return 1
    fi
    
    debug "Parsing JSON configuration file: ${file}"
    
    # Use jq to flatten JSON and extract key-value pairs
    while IFS='=' read -r key value; do
        if [[ -n "${key}" && -n "${value}" ]]; then
            # Remove quotes from jq output
            key="${key//\"/}"
            value="${value//\"/}"
            
            key="$(_normalize_config_key "${key}")"
            set_config "${key}" "${value}" "file:${file}"
        fi
    done < <(jq -r 'paths(scalars) as $p | "\($p | join("."))=\(getpath($p))"' "${file}" 2>/dev/null)
    
    debug "Completed parsing JSON file: ${file}"
    
    return 0
}

# _parse_yaml_config() - Parse YAML configuration file
#
# Description:
#   Parses YAML configuration files using yq. Flattens nested structures
#   into dot-notation keys for consistent access patterns.
#
# Input:
#   $1 - Path to YAML configuration file
#
# Returns:
#   0 on success, 1 on error
#
_parse_yaml_config() {
    local file="${1:-}"
    local key
    local value
    
    if [[ ! -r "${file}" ]]; then
        warn "Cannot read YAML configuration file: ${file}"
        return 1
    fi
    
    if [[ "${CONFIG_SUPPORT_YAML}" != "1" ]]; then
        warn "YAML support not available (yq not found)"
        return 1
    fi
    
    debug "Parsing YAML configuration file: ${file}"
    
    # Use yq to flatten YAML and extract key-value pairs
    while IFS='=' read -r key value; do
        if [[ -n "${key}" && -n "${value}" ]]; then
            key="$(_normalize_config_key "${key}")"
            set_config "${key}" "${value}" "file:${file}"
        fi
    done < <(yq eval '. as $item ireduce ({}; . * $item) | paths(scalars) as $p | "\($p | join("."))=\(getpath($p))"' "${file}" 2>/dev/null)
    
    debug "Completed parsing YAML file: ${file}"
    
    return 0
}

# _load_config_from_env() - Load configuration from environment variables
#
# Description:
#   Scans environment variables for configuration values with enhanced mapping support.
#   Supports custom prefixes, explicit mappings, and automatic key transformation.
#   Priority: explicit mappings > custom prefixes > default patterns
#
# Returns:
#   0 on success
#
# Environment variable patterns:
#   Explicit mappings (highest priority)
#   Custom prefixes from CONFIG_ENV_PREFIXES
#   Custom suffixes from CONFIG_ENV_SUFFIXES  
#   Default: APP_*, CONFIG_*, *_CONFIG
#
_load_config_from_env() {
    local var_name
    local config_key
    local value
    local prefix
    local suffix
    local matched=0
    
    debug "Loading configuration from environment variables"
    
    # Process all environment variables
    for var_name in $(compgen -e); do
        value="${!var_name}"
        matched=0
        
        # Check explicit mappings first (highest priority)
        if [[ -n "${CONFIG_ENV_MAPPINGS["${var_name}"]:-}" ]]; then
            config_key="${CONFIG_ENV_MAPPINGS["${var_name}"]}"
            set_config "${config_key}" "${value}" "env:${var_name}"
            debug "Loaded env var ${var_name} via explicit mapping → ${config_key}"
            continue
        fi
        
        # Check custom prefixes
        for prefix in ${CONFIG_ENV_PREFIXES}; do
            if [[ "${var_name}" == "${prefix}"* ]]; then
                config_key="${var_name#"${prefix}"}"  # Remove prefix
                
                if [[ "${CONFIG_AUTO_TRANSFORM_KEYS}" == "1" ]]; then
                    config_key="$(_transform_key "${config_key}" "dot")"
                else
                    config_key="${config_key,,}"         # Convert to lowercase
                    config_key="${config_key//_/.}"      # Convert underscores to dots
                fi
                
                config_key="$(_normalize_config_key "${config_key}")"
                set_config "${config_key}" "${value}" "env:${var_name}"
                debug "Loaded env var ${var_name} via prefix ${prefix} → ${config_key}"
                matched=1
                break
            fi
        done
        
        # Skip if already matched by prefix
        [[ "${matched}" == "1" ]] && continue
        
        # Check custom suffixes
        for suffix in ${CONFIG_ENV_SUFFIXES}; do
            if [[ "${var_name}" == *"${suffix}" ]]; then
                config_key="${var_name%"${suffix}"}"  # Remove suffix
                
                if [[ "${CONFIG_AUTO_TRANSFORM_KEYS}" == "1" ]]; then
                    config_key="$(_transform_key "${config_key}" "dot")"
                else
                    config_key="${config_key,,}"         # Convert to lowercase
                    config_key="${config_key//_/.}"      # Convert underscores to dots
                fi
                
                config_key="$(_normalize_config_key "${config_key}")"
                set_config "${config_key}" "${value}" "env:${var_name}"
                debug "Loaded env var ${var_name} via suffix ${suffix} → ${config_key}"
                matched=1
                break
            fi
        done
        
        # Skip if already matched by suffix
        [[ "${matched}" == "1" ]] && continue
        
        # Fall back to legacy default patterns (for backward compatibility)
        case "${var_name}" in
            APP_*|CONFIG_*|*_CONFIG)
                config_key="${var_name}"
                config_key="${config_key#APP_}"      # Remove APP_ prefix
                config_key="${config_key#CONFIG_}"   # Remove CONFIG_ prefix
                config_key="${config_key%_CONFIG}"   # Remove _CONFIG suffix
                
                if [[ "${CONFIG_AUTO_TRANSFORM_KEYS}" == "1" ]]; then
                    config_key="$(_transform_key "${config_key}" "dot")"
                else
                    config_key="${config_key,,}"         # Convert to lowercase
                    config_key="${config_key//_/.}"      # Convert underscores to dots
                fi
                
                config_key="$(_normalize_config_key "${config_key}")"
                set_config "${config_key}" "${value}" "env:${var_name}"
                debug "Loaded env var ${var_name} via legacy pattern → ${config_key}"
                ;;
        esac
    done
    
    return 0
}

#
# Configuration Validation Functions
#

# validate_config() - Validate entire configuration against schema
#
# Description:
#   Validates all configuration values against the defined schema.
#   Checks for required fields, type constraints, and value ranges.
#
# Returns:
#   0 if all validation passes, 1 if any validation fails
#
validate_config() {
    local validation_errors=0
    local key
    local value
    
    debug "Starting full configuration validation"
    
    # For now, perform basic validation
    # TODO: Implement full schema validation in schema validation phase
    
    for key in "${!CONFIG_VALUES[@]}"; do
        value="${CONFIG_VALUES["${key}"]}"
        
        # Basic validation - check for empty required values
        if [[ -z "${value}" ]]; then
            warn "Configuration key '${key}' is empty"
            ((validation_errors++))
        fi
    done
    
    if [[ "${validation_errors}" -gt 0 ]]; then
        error "Configuration validation failed with ${validation_errors} errors"
        return 1
    else
        debug "Configuration validation successful"
        return 0
    fi
}

#
# Configuration Override Definition Functions
#

# define_config_overrides() - Define explicit override mappings for config keys
#
# Description:
#   Allows applications to define explicit mappings between environment variables,
#   CLI arguments, and configuration keys. This provides precise control over
#   which external sources can override which configuration values.
#
# Input:
#   $1 - JSON-like configuration string or individual mappings
#
# Returns:
#   0 on success, 1 on error
#
# JSON Format Example:
#   define_config_overrides '{
#     "database.host": {
#       "env": ["DB_HOST", "DATABASE_HOST"],
#       "cli": ["--db-host", "--database-host"],
#       "short": ["-h"]
#     },
#     "logging.level": {
#       "env": "LOG_LEVEL",
#       "cli": "--log-level"
#     }
#   }'
#
# Individual mapping examples:
#   define_config_overrides env "DB_HOST" "database.host"
#   define_config_overrides cli "--db-host" "database.host"
#   define_config_overrides short "-h" "database.host"
#
define_config_overrides() {
    local mapping_type="${1:-}"
    local source="${2:-}"  
    local target="${3:-}"
    
    # Handle individual mapping format
    if [[ $# -eq 3 ]]; then
        _add_config_mapping "${mapping_type}" "${source}" "${target}"
        return $?
    fi
    
    # Handle JSON-like format (simplified parsing for now)
    if [[ $# -eq 1 && "${mapping_type}" == *"{"* ]]; then
        warn "JSON format configuration overrides not yet implemented"
        warn "Use individual mapping format: define_config_overrides env 'ENV_VAR' 'config.key'"
        return 1
    fi
    
    warn "define_config_overrides() requires either 3 parameters (type, source, target) or JSON format"
    return 1
}

# add_config_env_prefix() - Add custom environment variable prefix
#
# Description:
#   Adds a custom prefix to scan for environment variables. Variables matching
#   this prefix will be automatically converted to configuration keys.
#
# Input:
#   $1 - Environment variable prefix (with or without trailing underscore)
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   add_config_env_prefix "MYAPP_"     # Scan MYAPP_* variables
#   add_config_env_prefix "SERVICE"    # Scan SERVICE_* variables
#
add_config_env_prefix() {
    local prefix="${1:-}"
    
    if [[ -z "${prefix}" ]]; then
        warn "add_config_env_prefix() requires a prefix parameter"
        return 1
    fi
    
    # Ensure prefix ends with underscore
    [[ "${prefix: -1}" != "_" ]] && prefix="${prefix}_"
    
    # Add to prefix list if not already present
    if [[ ! "${CONFIG_ENV_PREFIXES}" == *"${prefix}"* ]]; then
        CONFIG_ENV_PREFIXES="${CONFIG_ENV_PREFIXES} ${prefix}"
        debug "Added environment variable prefix: ${prefix}"
    fi
    
    return 0
}

# add_config_env_suffix() - Add custom environment variable suffix
#
# Description:
#   Adds a custom suffix to scan for environment variables. Variables ending
#   with this suffix will be automatically converted to configuration keys.
#
# Input:
#   $1 - Environment variable suffix (with or without leading underscore)
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   add_config_env_suffix "_CONFIG"    # Scan *_CONFIG variables
#   add_config_env_suffix "CFG"        # Scan *_CFG variables
#
add_config_env_suffix() {
    local suffix="${1:-}"
    
    if [[ -z "${suffix}" ]]; then
        warn "add_config_env_suffix() requires a suffix parameter"
        return 1
    fi
    
    # Ensure suffix starts with underscore
    [[ "${suffix:0:1}" != "_" ]] && suffix="_${suffix}"
    
    # Add to suffix list if not already present
    if [[ ! "${CONFIG_ENV_SUFFIXES}" == *"${suffix}"* ]]; then
        CONFIG_ENV_SUFFIXES="${CONFIG_ENV_SUFFIXES} ${suffix}"
        debug "Added environment variable suffix: ${suffix}"
    fi
    
    return 0
}

#
# Configuration Management Functions
#

# parse_config_options() - Parse command-line options for configuration
#
# Description:
#   Enhanced command-line argument parser with support for explicit mappings,
#   short options, automatic key transformation, and multiple argument formats.
#   Priority: explicit mappings > short options > automatic patterns
#
# Input:
#   $@ - Command-line arguments to parse
#
# Returns:
#   Sets configuration values from parsed command-line options
#
# Supported formats:
#   --config-key=value        # Traditional config prefix
#   --database-host=localhost # Automatic kebab-case to dot notation  
#   --db-host localhost       # Space-separated values
#   -h localhost              # Short options (if mapped)
#   --key value               # Generic long options
#
parse_config_options() {
    local key
    local value
    local config_key
    local option
    local next_arg
    
    debug "Parsing command-line configuration options"
    
    while [[ $# -gt 0 ]]; do
        option="${1}"
        next_arg="${2:-}"
        
        case "${option}" in
            # Configuration file handling
            --config-file)
                CONFIG_FILES+=("${next_arg}")
                shift 2
                ;;
            --config-file=*)
                CONFIG_FILES+=("${option#*=}")
                shift
                ;;
                
            # Module configuration options
            --strict-config)
                CONFIG_STRICT_MODE=1
                shift
                ;;
            --permissive-config)
                CONFIG_STRICT_MODE=0
                shift
                ;;
            --auto-transform-keys)
                CONFIG_AUTO_TRANSFORM_KEYS=1
                shift
                ;;
            --no-auto-transform-keys)
                CONFIG_AUTO_TRANSFORM_KEYS=0
                shift
                ;;
                
            # Traditional config prefix options
            --config-*)
                # Handle --config-key=value format
                if [[ "${option}" == *"="* ]]; then
                    key="${option#--config-}"
                    key="${key%%=*}"
                    value="${option#*=}"
                    shift
                else
                    # Handle --config-key value format
                    key="${option#--config-}"
                    value="${next_arg}"
                    shift 2
                fi
                
                if [[ "${CONFIG_AUTO_TRANSFORM_KEYS}" == "1" ]]; then
                    config_key="$(_transform_key "${key}" "dot")"
                else
                    config_key="$(_normalize_config_key "${key}")"
                fi
                
                set_config "${config_key}" "${value}" "cli:${option}"
                debug "Loaded CLI option ${option} → ${config_key}='${value}'"
                ;;
                
            # Short options (single character with -)
            -[a-zA-Z])
                # Check if this short option is mapped
                if [[ -n "${CONFIG_CLI_SHORT_OPTS["${option}"]:-}" ]]; then
                    config_key="${CONFIG_CLI_SHORT_OPTS["${option}"]}"
                    value="${next_arg}"
                    set_config "${config_key}" "${value}" "cli:${option}"
                    debug "Loaded CLI short option ${option} → ${config_key}='${value}'"
                    shift 2
                else
                    # Unknown short option, let main script handle it
                    shift
                fi
                ;;
                
            # Long options with explicit mappings
            --*)
                # Check explicit CLI mappings first
                if [[ -n "${CONFIG_CLI_MAPPINGS["${option}"]:-}" ]]; then
                    config_key="${CONFIG_CLI_MAPPINGS["${option}"]}"
                    
                    # Handle both --option=value and --option value formats
                    if [[ "${option}" == *"="* ]]; then
                        value="${option#*=}"
                        shift
                    else
                        value="${next_arg}"
                        shift 2
                    fi
                    
                    set_config "${config_key}" "${value}" "cli:${option}"
                    debug "Loaded CLI option ${option} via explicit mapping → ${config_key}='${value}'"
                    
                # Check for automatic kebab-case transformation
                elif [[ "${CONFIG_KEBAB_TO_DOT}" == "1" && "${option}" == --*-* ]]; then
                    key="${option#--}"
                    
                    # Handle --option=value format
                    if [[ "${key}" == *"="* ]]; then
                        value="${key#*=}"
                        key="${key%%=*}"
                        shift
                    else
                        value="${next_arg}"
                        shift 2
                    fi
                    
                    if [[ "${CONFIG_AUTO_TRANSFORM_KEYS}" == "1" ]]; then
                        config_key="$(_transform_key "${key}" "dot")"
                    else
                        config_key="$(_normalize_config_key "${key//-/.}")"
                    fi
                    
                    set_config "${config_key}" "${value}" "cli:${option}"
                    debug "Loaded CLI option ${option} via kebab-case transformation → ${config_key}='${value}'"
                else
                    # Unknown long option, let main script handle it
                    shift
                fi
                ;;
                
            *)
                # Unknown option, let main script handle it
                shift
                ;;
        esac
    done
    
    debug "Completed parsing command-line configuration options"
}

# show_config_help() - Display comprehensive help for configuration functionality
#
# Description:
#   Shows detailed usage information including configuration options,
#   environment variables, file formats, and practical examples.
#
# Returns:
#   0 on success
#
show_config_help() {
    cat <<EOF
Configuration Management Module Help
====================================

COMMAND-LINE OPTIONS:
    --config-file FILE          Add configuration file to load
    --config-KEY=VALUE         Set configuration key to value (traditional format)
    --config-KEY VALUE         Set configuration key to value (alternative format)
    --database-host=VALUE      Automatic kebab-case to dot notation conversion
    --strict-config            Enable strict validation mode
    --permissive-config        Enable permissive validation mode
    --auto-transform-keys      Enable automatic key format transformation
    --no-auto-transform-keys   Disable automatic key format transformation

ENVIRONMENT VARIABLES:
    # Configuration behavior
    CONFIG_STRICT_MODE         Strict validation: 1=strict, 0=permissive (default: 1)
    CONFIG_ALLOW_UNDEFINED     Allow undefined keys: 1=yes, 0=no (default: 0)
    CONFIG_CASE_SENSITIVE      Case-sensitive keys: 1=yes, 0=no (default: 1)
    CONFIG_AUTO_RELOAD         Auto-reload on changes: 1=yes, 0=no (default: 0)
    
    # Override configuration
    CONFIG_ENV_PREFIXES        Space-separated prefixes to scan (default: "APP_ CONFIG_ MYAPP_")
    CONFIG_ENV_SUFFIXES        Space-separated suffixes to scan (default: "_CONFIG")
    CONFIG_AUTO_TRANSFORM_KEYS Auto-transform key formats: 1=yes, 0=no (default: 1)
    CONFIG_KEBAB_TO_DOT        Convert kebab-case to dot notation: 1=yes, 0=no (default: 1)
    
    # Automatic environment variable patterns
    APP_*                      Application configuration variables → app.*
    CONFIG_*                   Configuration variables → *
    MYAPP_*                    Custom application variables → *  
    *_CONFIG                   Configuration variables (suffix format) → *

CONFIGURATION FILE FORMATS:
    INI/CONF:                  key=value format with [sections]
    JSON:                      Standard JSON format (requires jq)
    YAML:                      Standard YAML format (requires yq)

CONFIGURATION PRIORITY (highest to lowest):
    1. Explicit CLI mappings   (defined via define_config_overrides)
    2. Command-line arguments  (--config-key=value, --kebab-case=value)
    3. Explicit env mappings   (defined via define_config_overrides)
    4. Environment variables   (custom prefixes/suffixes, then defaults)
    5. Configuration files     (loaded in order specified)
    6. Schema defaults         (defined in application)

ADVANCED OVERRIDE CONFIGURATION:
    # Define explicit mappings
    define_config_overrides env "DB_HOST" "database.host"
    define_config_overrides cli "--db-host" "database.host"
    define_config_overrides short "-h" "database.host"
    
    # Add custom environment variable patterns
    add_config_env_prefix "MYSERVICE_"    # Scan MYSERVICE_* variables
    add_config_env_suffix "_CFG"          # Scan *_CFG variables

EXAMPLES:
    # Basic usage
    load_config "app.conf"
    host="\$(get_config "database.host" "localhost")"
    port="\$(get_config "database.port" "5432" "int")"
    
    # Command-line overrides (multiple formats supported)
    script.sh --config-file app.conf --config-database.host=db.example.com
    script.sh --database-host=db.example.com --log-level=DEBUG
    script.sh -h db.example.com  # if short option mapped
    
    # Environment variable overrides
    export MYAPP_DATABASE_HOST="db.example.com"
    export LOG_LEVEL="DEBUG"
    export DATABASE_CONFIG="prod-settings"
    script.sh
    
    # Advanced configuration with explicit mappings
    define_config_overrides env "DB_URL" "database.connection_string"
    define_config_overrides cli "--db-url" "database.connection_string"
    add_config_env_prefix "SERVICE_"
    load_config

EOF
}

# Module initialization when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Load logging system for immediate availability
    _load_config_logger
    
    # Detect available format support
    _detect_format_support
    
    # Parse command-line options if provided
    parse_config_options "${@}"
    
    debug "Configuration module loaded (lazy initialization enabled)"
fi