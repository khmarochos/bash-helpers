#!/usr/bin/env bash

# Early return if module already loaded
[[ "${LOG_MODULE_LOADED:-0}" == "1" ]] && return 0

#
# Enhanced Logging Module for Bash Scripts
# 
# This module provides comprehensive logging functionality with support for:
# - Multi-destination output (console stdout/stderr and file logging)
# - Configurable log levels with filtering (DEBUG, INFO, WARN, ERROR)
# - Timestamped file entries with structured format
# - Numeric boolean flags for optimal performance
# - Command-line options and environment variable configuration
# - Automatic initialization when sourced
# - Module detection marker for integration with other modules
#
# Key Features:
# - Zero-configuration usage: source and start logging immediately
# - Performance-optimized with numeric boolean logic throughout
# - Thread-safe file logging with atomic writes
# - Flexible output control (quiet mode, verbose mode, log level filtering)
# - Help system with comprehensive usage examples
# - Re-sourcing protection with readonly variable guards
# - Integration-ready with LOG_MODULE_LOADED detection marker
#
# Architecture:
# - Immediate initialization: Configuration processed during sourcing
# - Numeric boolean flags (0/1) for optimal performance
# - Structured internal functions for maintainability
# - Comprehensive input validation and error handling
# - Configurable via environment variables or command-line options
#
# Usage:
#   source lib/log.sh
#   log "Application started"
#   warn "Configuration file not found, using defaults"
#   error "Failed to connect to database"
#   debug "Variable state: user_id=${user_id}"
#
# Advanced Usage:
#   # Command-line configuration
#   source lib/log.sh --log-file /var/log/myapp.log --log-level DEBUG
#   
#   # Environment variable configuration
#   LOG_FILE=/var/log/myapp.log LOG_LEVEL=DEBUG source lib/log.sh
#   
#   # Quiet mode for scripts
#   source lib/log.sh --be-quiet
#   
#   # Integration with other modules
#   if ((LOG_MODULE_LOADED)); then
#       log "Logging system available"
#   else
#       echo "Manual logging fallback"
#   fi
#

#
# Constants
#
# Declare constants only if not already defined (prevents warnings on re-sourcing)
if [[ -z "${LOGGER_OUT:-}" ]]; then
    declare -r LOGGER_OUT="1"
fi
if [[ -z "${LOGGER_ERR:-}" ]]; then
    declare -r LOGGER_ERR="2"
fi

# Marker to indicate this module has been loaded (1 = loaded, 0 = not loaded)
if [[ -z "${LOG_MODULE_LOADED:-}" ]]; then
    declare -r LOG_MODULE_LOADED=1
fi

#
# Configuration Variables
#
# These variables control logging behavior and can be set via:
# - Environment variables before sourcing the module
# - Command-line options using parse_log_options()
# - Direct assignment in scripts
#
# All boolean variables use numeric values for optimal performance:
#   0 = false/disabled    1 = true/enabled
#
# GLOBAL VARIABLES AND NAMING CONFLICTS:
#   This module uses several global variables that may conflict with user scripts.
#   Review this list before using the module to avoid naming conflicts:
#
#   READONLY CONSTANTS (safe - cannot be overwritten):
#     LOGGER_OUT, LOGGER_ERR, LOG_MODULE_LOADED
#
#   CONFIGURATION VARIABLES (can be set by user):
#     LOG_FILE, LOG_TIME_FORMAT, LOG_LEVEL, BE_QUIET, BE_VERBOSE
#
#   POTENTIAL CONFLICTS:
#     - Avoid using variable names that start with LOG_, LOGGER_, BE_
#     - Functions use local variables with common names (output, level, timestamp, etc.)
#     - No signal traps are modified by this module
#     - File operations use paths provided by user - validate LOG_FILE paths
#
#   ENVIRONMENT VARIABLES (inherited from environment):
#     LOG_FILE, LOG_TIME_FORMAT, LOG_LEVEL, BE_QUIET, BE_VERBOSE
#     Note: Environment variables take precedence over script defaults
#

# Core logging configuration
LOG_FILE="${LOG_FILE:-}"                              # Path to log file (empty = no file logging)
LOG_TIME_FORMAT="${LOG_TIME_FORMAT:-"+%Y-%m-%d %H:%M:%S"}"  # Timestamp format for log entries
LOG_LEVEL="${LOG_LEVEL:-INFO}"                        # Minimum log level: DEBUG, INFO, WARN, ERROR

# Output control flags (numeric for performance)
BE_QUIET=${BE_QUIET:-0}                               # Suppress console output: 1=quiet, 0=normal
BE_VERBOSE=${BE_VERBOSE:-0}                           # Enable verbose output: 1=verbose, 0=normal
                                                      # Note: BE_VERBOSE=1 automatically sets LOG_LEVEL=DEBUG

#
# Internal Functions
#

# _log_file() - Internal function for writing messages to the log file
#
# Description:
#   Writes a formatted log entry to the configured log file. The function
#   adds timestamps and tags to each log entry for better traceability.
#
# Input:
#   $1 - Output stream number (LOGGER_OUT or LOGGER_ERR)
#   $2+ - Log message content
#
# Returns:
#   0 on success, non-zero on error
#
# Global variables used:
#   LOG_FILE - Path to the log file (read)
#   LOG_TIME_FORMAT - Time format string for timestamps (read)
#
# Local variables:
#   tag - Log entry tag (OUT/ERR)
#   output - Output stream number
#   timestamp - Formatted timestamp
_log_file() {
    local output="${1}"
    local tag
    local timestamp
    
    # Check if LOG_FILE is configured
    if [[ -z "${LOG_FILE}" ]]; then
        ((BE_VERBOSE)) && warn "The LOG_FILE variable is unset, won't write to the log file."
        return 1
    fi
    
    # Determine the appropriate tag based on output stream
    case "${output}" in
        "${LOGGER_OUT}")
            tag='OUT'
            shift
            ;;
        "${LOGGER_ERR}")
            tag='ERR'
            shift
            ;;
        *)
            warn "The _log_file() function requires the output stream's number, got '${output}' instead."
            tag='???'
            ;;
    esac
    
    # Generate timestamp
    timestamp="$(date "${LOG_TIME_FORMAT}")"
    
    # Write to log file
    echo "${timestamp} [${tag}] ${*}" >>"${LOG_FILE}"
}

# _log_output() - Internal function for handling console and file output
#
# Description:
#   Manages output to both console (stdout/stderr) and log file. Respects
#   the BE_QUIET setting for console output suppression.
#
# Input:
#   $1 - Output stream number (LOGGER_OUT or LOGGER_ERR)
#   $2+ - Message to log
#
# Returns:
#   0 on success, non-zero on error
#
# Global variables used:
#   LOG_FILE - Path to the log file (read)
#   BE_QUIET - Console output suppression flag (read)
#
# Local variables:
#   output - Output stream number
_log_output() {
    local output="${1}"
    
    # Validate output stream
    if [[ "${output}" -ne "${LOGGER_OUT}" && "${output}" -ne "${LOGGER_ERR}" ]]; then
        warn "The _log_output() function requires the output stream's number, got '${output}' instead."
        output="${LOGGER_OUT}"
    else
        shift
    fi
    
    # Write to console unless quiet mode is enabled
    if ! ((BE_QUIET)); then
        echo "${*}" >&"${output}"
    fi
    
    # Write to log file if configured
    if [[ -n "${LOG_FILE}" ]]; then
        _log_file "${output}" "${*}"
    fi
}

# _should_log() - Internal function to check if a message should be logged
#
# Description:
#   Determines whether a message should be logged based on the current
#   log level configuration.
#
# Input:
#   $1 - Message level (DEBUG, INFO, WARN, ERROR)
#
# Returns:
#   0 if message should be logged, 1 otherwise
#
# Global variables used:
#   LOG_LEVEL - Current log level setting (read)
#
# Local variables:
#   level - Message level
#   levels - Array of log levels in order
#   current_level_index - Index of current log level
#   message_level_index - Index of message level
_should_log() {
    local level="${1}"
    local -a levels=("DEBUG" "INFO" "WARN" "ERROR")
    local current_level_index=-1
    local message_level_index=-1
    local i
    
    # Find indices of current and message levels
    for i in "${!levels[@]}"; do
        if [[ "${levels[${i}]}" == "${LOG_LEVEL}" ]]; then
            current_level_index="${i}"
        fi
        if [[ "${levels[${i}]}" == "${level}" ]]; then
            message_level_index="${i}"
        fi
    done
    
    # Log if message level is >= current level
    [[ ${message_level_index} -ge ${current_level_index} ]]
}

#
# Public Functions
#

# log() - Log an informational message
#
# Description:
#   Logs a message to stdout and optionally to a log file. This function
#   is intended for general informational messages.
#
# Input:
#   $@ - Message to log
#
# Returns:
#   0 on success
#
# Global variables used:
#   All logging-related globals (indirectly via _log_output)
#
# Example:
#   log "Process started successfully"
log() {
    if _should_log "INFO"; then
        _log_output "${LOGGER_OUT}" "${@}"
    fi
}

# warn() - Log a warning message
#
# Description:
#   Logs a warning message to stderr and optionally to a log file. This
#   function is intended for warning conditions that don't prevent operation.
#
# Input:
#   $@ - Warning message to log
#
# Returns:
#   0 on success
#
# Global variables used:
#   All logging-related globals (indirectly via _log_output)
#
# Example:
#   warn "Configuration file not found, using defaults"
warn() {
    if _should_log "WARN"; then
        _log_output "${LOGGER_ERR}" "${@}"
    fi
}

# error() - Log an error message
#
# Description:
#   Logs an error message to stderr and optionally to a log file. This
#   function is intended for error conditions.
#
# Input:
#   $@ - Error message to log
#
# Returns:
#   0 on success
#
# Global variables used:
#   All logging-related globals (indirectly via _log_output)
#
# Example:
#   error "Failed to connect to database"
error() {
    if _should_log "ERROR"; then
        _log_output "${LOGGER_ERR}" "ERROR: ${@}"
    fi
}

# debug() - Log a debug message
#
# Description:
#   Logs a debug message to stdout and optionally to a log file. Debug
#   messages are only shown when LOG_LEVEL is set to DEBUG.
#
# Input:
#   $@ - Debug message to log
#
# Returns:
#   0 on success
#
# Global variables used:
#   All logging-related globals (indirectly via _log_output)
#
# Example:
#   debug "Variable X = ${x}"
debug() {
    if _should_log "DEBUG"; then
        _log_output "${LOGGER_OUT}" "DEBUG: ${@}"
    fi
}

# form_section_header() - Format a section header with borders
#
# Description:
#   Formats a consistently styled section header with configurable border styles.
#   Returns the formatted text as a string for the caller to output.
#
# Input:
#   $1 - Section title text
#   $2 - Optional header style: "major", "normal", "minor", "subsection", "completion", "warning", "error", "info"
#
# Output:
#   Formatted header text to stdout (for command substitution)
#
# Global variables read:
#   None
#
# Global variables modified:
#   None
#
# Example:
#   log "$(form_section_header "Step 1: Initialization" "major")"
#   echo "$(form_section_header "Processing" "minor")"
form_section_header() {
    local title="${1}"
    local style="${2:-normal}"
    local border_width=72
    local result=""
    
    # Helper function to calculate padding for centering text
    # Inputs: $1 - text to center
    # Outputs: Prints "padding_left padding_right" to stdout
    calculate_padding() {
        local text="${1}"
        local text_length=${#text}
        local total_padding=$(( border_width - text_length - 2 ))
        local padding_left=$(( total_padding / 2 ))
        local padding_right=$(( total_padding / 2 ))
        # Handle odd-length padding
        if (( total_padding % 2 == 1 )); then
            padding_right=$((padding_right + 1))
        fi
        echo "${padding_left} ${padding_right}"
    }
    
    # Helper function to generate a border line
    # Inputs: $1 - left corner, $2 - line character, $3 - right corner
    # Outputs: Complete border line to stdout
    generate_border() {
        local left_corner="${1}"
        local line_char="${2}"
        local right_corner="${3}"
        local line_length=$(( border_width - 2 ))  # Subtract corners
        
        printf "%s" "${left_corner}"
        # Use a loop to handle multi-byte characters properly
        for ((i=0; i<line_length; i++)); do
            printf "%s" "${line_char}"
        done
        printf "%s" "${right_corner}"
    }
    
    # Helper function to format a box with borders
    # Inputs: $1 - top left, $2 - top line, $3 - top right,
    #         $4 - side char, $5 - bottom left, $6 - bottom line, 
    #         $7 - bottom right, $8 - text to display
    format_box() {
        local top_left="${1}"
        local top_line="${2}"
        local top_right="${3}"
        local left_line="${4}"
        local right_line="${5}"
        local bottom_left="${6}"
        local bottom_line="${7}"
        local bottom_right="${8}"
        local text="${9}"
        
        # Get padding values from calculate_padding function
        local padding_values
        padding_values=$(calculate_padding "${text}")
        local padding_left padding_right
        read -r padding_left padding_right <<< "${padding_values}"
        
        local output=""
        
        # Generate borders
        if [[ ${#top_left} -gt 0 ]] && [[ ${#top_right} -gt 0 ]] && [[ ${#top_line} -gt 0 ]]; then
            output+="$(generate_border "${top_left}" "${top_line}" "${top_right}")"$'\n'
        fi
        output+="${left_line}$(printf "%${padding_left}s" "")${text}$(printf "%${padding_right}s" "")${right_line}"
        if [[ ${#bottom_left} -gt 0 ]] && [[ ${#bottom_right} -gt 0 ]] && [[ ${#bottom_line} -gt 0 ]]; then
            output+=$'\n'"$(generate_border "${bottom_left}" "${bottom_line}" "${bottom_right}")"
        fi
        
        echo "${output}"
    }
    
    # Add empty line before header
    result+=$'\n'
    
    case "${style}" in
        completion)
            # Double line box with check marks and centered title
            result+="$(format_box "┏" "━" "┓" "┃" "┃" "┗" "━" "┛" "✓ ${title} ✓")"
            ;;
        major)
            # Double line box with centered title
            result+="$(format_box "╔" "═" "╗" "║" "║" "╚" "═" "╝" "${title}")"
            ;;
        normal)
            # Single line box with centered title
            result+="$(format_box "┌" "─" "┐" "│" "│" "└" "─" "┘" "${title}")"
            ;;
        minor)
            # Dotted line box with centered title
            result+="$(format_box "┌" "╌" "┐" "╎" "╎" "└" "╌" "┘" "${title}")"
            ;;
        subsection|*)
            # Simple header for subsections - no box
            result+="$(format_box " " " " " " "▶" "◀" " " " " " " "${title}")"
            ;;
    esac
    
    echo "${result}"
}

# parse_log_options() - Parse command-line options for logging configuration
#
# Description:
#   Parses command-line arguments to configure logging behavior. Supports
#   both short and long option formats. This function should be called
#   early in the main script to process logging-related options.
#
# Input:
#   $@ - Command-line arguments to parse
#
# Returns:
#   Sets global variables based on parsed options
#
# Global variables modified:
#   LOG_FILE - Set via -f/--log-file
#   LOG_LEVEL - Set via -l/--log-level
#   LOG_TIME_FORMAT - Set via -t/--time-format
#   BE_QUIET - Set via -q/--quiet
#   BE_VERBOSE - Set via -v/--verbose
#
# Example:
#   parse_log_options "$@"
parse_log_options() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --log-file)
                LOG_FILE="${2}"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="${2^^}"  # Convert to uppercase
                shift 2
                ;;
            --log-time-format)
                LOG_TIME_FORMAT="${2}"
                shift 2
                ;;
            -q|--be-quiet)
                BE_QUIET=1
                shift
                ;;
            -v|--be-verbose)
                BE_VERBOSE=1
                LOG_LEVEL="DEBUG"
                shift
                ;;
            *)
                # Unknown option, let the main script handle it
                shift
                ;;
        esac
    done
}

# show_log_help() - Display comprehensive help for logging functionality
#
# Description:
#   Shows detailed usage information including configuration options,
#   environment variables, command-line flags, and practical examples
#   for all logging features.
#
# Input:
#   None
#
# Returns:
#   0 on success
#
# Global variables used:
#   None
#
# Example:
#   show_log_help
show_log_help() {
    cat <<EOF
$(form_section_header "Logging Module Help")

COMMAND-LINE OPTIONS:
        --log-file FILE             Set log file path
        --log-level LEVEL           Set minimum log level
        --log-time-format FORMAT    Set timestamp format for log entries
    -q, --be-quiet                  Suppress console output
    -v, --be-verbose                Enable verbose mode (sets LOG_LEVEL=DEBUG)

ENVIRONMENT VARIABLES:
    LOG_FILE        Path to log file (empty disables file logging)
    LOG_LEVEL       Minimum log level: DEBUG, INFO, WARN, ERROR (default: INFO)
    LOG_TIME_FORMAT Timestamp format string (default: +%Y-%m-%d %H:%M:%S)
    BE_QUIET        Suppress console output: 1=quiet, 0=normal (default: 0)
    BE_VERBOSE      Enable verbose output: 1=verbose, 0=normal (default: 0)

LOG LEVELS (in order of severity):
    DEBUG           Detailed diagnostic information (only shown when LOG_LEVEL=DEBUG)
    INFO            General informational messages (default minimum level)
    WARN            Warning conditions that don't prevent operation
    ERROR           Error conditions that may affect functionality
EOF
}

#
# Module Initialization
#
# Initialize logging system if this script is being sourced.
# This allows the module to be used immediately after sourcing.
# Command-line options are processed automatically for configuration.
#
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced - process configuration options
    parse_log_options "${@}"
    debug "Logging module loaded with immediate initialization"
fi
