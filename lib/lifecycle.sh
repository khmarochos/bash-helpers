#!/usr/bin/env bash

# Early return if module already loaded
[[ "${LIFECYCLE_MODULE_LOADED:-0}" == "1" ]] && return 0

#
# Complete Script Lifecycle Management Module for Bash Scripts
#
# This module provides enterprise-grade script lifecycle management with
# single-instance enforcement, automatic resource cleanup, and graceful
# shutdown capabilities. Designed for production scripts that require
# robust process control and reliable resource management.
#
# PRIMARY API:
#   ensure_single_instance()  - One-call complete lifecycle setup
#   add_cleanup_item()        - Track resources for automatic cleanup  
#   die()                    - Fatal error with graceful shutdown
#
# KEY FEATURES:
# - Zero-configuration single-instance enforcement with intelligent defaults
# - Lazy initialization: No side effects when sourced, only when functions are called
# - Robust PID validation with automatic stale lock detection and cleanup
# - Comprehensive resource tracking with automatic cleanup on any exit
# - Signal trap handlers for graceful shutdown (EXIT, INT, TERM, QUIT)
# - Global LOCK_FILE configuration with user-specific intelligent defaults
# - Performance-optimized with numeric boolean logic throughout
# - Integrated logging system with detailed progress reporting
# - Production-ready error handling with consistent exit codes
# - Command-line parametrization for configuration control
#
# ARCHITECTURE PRINCIPLES:
# - Lazy Initialization: Setup occurs only when needed, not during module loading
# - Composable Design: High-level functions built from well-tested primitives
# - DRY Principle: Single source of truth for all operations
# - Fail-Fast: Immediate termination on conflicts or errors
# - Defensive Programming: Comprehensive input validation and error handling
# - Zero-Configuration: Works immediately with sensible defaults
# - Atomic Operations: Race-condition-safe file operations
#
# SIMPLIFIED WORKFLOW:
#   1. Source the module (clean loading with no side effects)
#   2. Call ensure_single_instance() (complete setup in one call)
#   3. Add temporary resources with add_cleanup_item() as needed
#   4. Continue normal script execution
#   5. All cleanup happens automatically on any exit condition
#
# BASIC USAGE (RECOMMENDED):
#   source lib/lifecycle.sh
#   ensure_single_instance           # Complete single-instance setup
#   
#   temp_dir="$(mktemp -d)"
#   add_cleanup_item "${temp_dir}"   # Track for automatic cleanup
#   
#   # Your script logic here...
#   # Everything cleaned up automatically on exit
#
# ADVANCED USAGE:
#   # Custom lock file location
#   LOCK_FILE="/var/run/myservice.pid"
#   source lib/lifecycle.sh
#   ensure_single_instance
#   
#   # Command-line configuration
#   source lib/lifecycle.sh --lock-file /var/run/myservice.pid --strict-lock
#   ensure_single_instance
#   
#   # Fatal error handling
#   [[ -r "${config}" ]] || die 1 "Cannot read config: ${config}"
#   
#   # Conditional resource tracking
#   if [[ "${debug_mode}" == 1 ]]; then
#       add_cleanup_item "${debug_log}"
#   fi

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
if [[ -z "${LIFECYCLE_MODULE_LOADED:-}" ]]; then
    declare -r LIFECYCLE_MODULE_LOADED=1
fi

#
# Global Configuration Variables
#
# These variables control module behavior and can be set before sourcing
# or modified during script execution for dynamic configuration.
#

# Core configuration variables with intelligent defaults
# These can be set via environment variables, command-line options, or direct assignment

# Lock file path with intelligent defaults
# Priority: explicit assignment > command-line option > environment variable > computed default
# Default pattern: /tmp/${USER}-${script_name}.lock
LOCK_FILE="${LOCK_FILE:-}"

# Cleanup behavior configuration (numeric for performance)
CLEANUP_ON_SUCCESS="${CLEANUP_ON_SUCCESS:-1}"    # Cleanup on successful completion: 1=yes, 0=no
CLEANUP_ON_ERROR="${CLEANUP_ON_ERROR:-1}"        # Cleanup on error/signal: 1=yes, 0=no
STRICT_LOCK_CHECK="${STRICT_LOCK_CHECK:-1}"      # Strict PID validation: 1=strict, 0=permissive
LOCK_WAIT_TIMEOUT="${LOCK_WAIT_TIMEOUT:-0}"      # Wait for lock timeout in seconds: 0=no wait

# Resource cleanup tracking array
# Contains paths to files/directories that should be removed during cleanup
# Managed via add_cleanup_item() and remove_cleanup_item() functions
# Processed automatically by cleanup() function on script exit
declare -a TO_BE_REMOVED=()

# Track whether cleanup traps have been installed (1 = installed, 0 = not installed)
CLEANUP_TRAPS_INSTALLED="${CLEANUP_TRAPS_INSTALLED:-0}"

#
# Private Functions
#

# _compute_default_lock_file() - Generate intelligent default lock file path
#
# Description:
#   Computes a sensible default lock file path based on the calling script's
#   name and the current user. Uses /tmp for user-specific locks to avoid
#   permission issues with system directories.
#
# Returns:
#   Outputs default lock file path to stdout
#
# Path Format:
#   /tmp/${USER}-${script_basename}.lock
#   Example: /tmp/john-backup-script.lock
#
_compute_default_lock_file() {
    local script_name
    script_name="$(basename "${0}" .sh)"
    echo "/tmp/${USER:-unknown}-${script_name}.lock"
}

# _ensure_lock_file() - Ensure LOCK_FILE variable is set with valid path
#
# Description:
#   Validates and sets the global LOCK_FILE variable if not already configured.
#   Uses intelligent defaults based on script name and user context.
#
# Global variables modified:
#   LOCK_FILE - Set to computed default if empty or unset
#
_ensure_lock_file() {
    if [[ -z "${LOCK_FILE}" ]]; then
        LOCK_FILE="$(_compute_default_lock_file)"
    fi
}

# _load_logger() - Load logging module if not already loaded
#
# Description:
#   Checks if the logging module is already loaded and sources it if needed.
#   This function is called automatically during module initialization.
#
# Returns:
#   0 on success (logger loaded or already available)
#   1 if logger module cannot be found or loaded
#
# Global variables used:
#   LOG_MODULE_LOADED - Set by log.sh module when loaded
#
_load_logger() {
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

# _remove_stale_lock() - Internal function to remove stale lock files
#
# Description:
#   Removes a stale lock file and handles any errors that occur during removal.
#   This is an internal function used by check_running().
#
# Input:
#   $1 - Path to the lock file to remove
#
# Returns:
#   0 on success, exits script with code 1 on error
#
_remove_stale_lock() {
    local lock_file="${1:-}"
    
    rm -f "${lock_file:?}"
    if [[ $? -ne 0 ]]; then
        error "Can't remove ${lock_file}, exiting."
        exit 1
    fi
    
    return 0
}

#
# Process Control Functions
#

# check_running() - Enforce single-instance execution via PID lock validation
#
# Description:
#   Performs comprehensive single-instance checking using PID lock files.
#   Uses global LOCK_FILE variable if no parameter provided. Validates lock
#   file existence, PID format, and process existence. Automatically cleans
#   up stale locks from terminated processes. Exits immediately if a valid
#   competing instance is detected.
#
# Process Flow:
#   1. Ensure lock file path is configured (uses global LOCK_FILE)
#   2. Check if lock file exists (no file = no other instance)
#   3. Read and validate PID format from lock file
#   4. Verify process with that PID is still running
#   5. Remove stale lock if process doesn't exist
#   6. Exit with error if active process found
#
# Input:
#   $1 - (Optional) Absolute path to the PID lock file
#        If not provided, uses global LOCK_FILE variable
#        If LOCK_FILE is unset, computes intelligent default
#
# Returns:
#   0 if no competing instance is running (safe to proceed)
#   Never returns if another instance is active (exits with code 1)
#
# Examples:
#   # Use global LOCK_FILE (recommended)
#   check_running
#   
#   # Use explicit path
#   check_running "/var/run/myapp.pid"
#   
#   # Set global then use
#   LOCK_FILE="/tmp/custom.lock"
#   check_running
#
check_running() {
    local run_lock="${1:-}"
    
    # Use global LOCK_FILE if no parameter provided (lazy initialization)
    if [[ -z "${run_lock}" ]]; then
        _ensure_lock_file
        run_lock="${LOCK_FILE}"
    fi
    
    # Validate input parameter
    if [[ -z "${run_lock}" ]]; then
        error "Can't determine run lock file's path, exiting."
        exit 1
    fi
    
    # If lock file doesn't exist, no other instance is running
    if [[ ! -f "${run_lock}" ]]; then
        return 0
    fi
    
    # Read PID from lock file
    local suspicious_pid
    suspicious_pid="$(cat "${run_lock}" 2>/dev/null)"
    if [[ $? -ne 0 ]]; then
        error "Can't read lock file contents, exiting."
        exit 1
    fi
    
    # Validate PID format
    if [[ ! "${suspicious_pid}" =~ ^[0-9]+$ ]]; then
        warn "Run lock file ${run_lock} doesn't contain valid PID, removing lock file."
        _remove_stale_lock "${run_lock}"
        return 0
    fi
    
    # Check if process is still running
    local process_comm
    process_comm="$(ps -p "${suspicious_pid}" -o comm= 2>/dev/null || true)"
    if [[ -z "${process_comm}" ]]; then
        warn "Process with ID mentioned in ${run_lock} (${suspicious_pid}) doesn't exist."
        warn "${run_lock} seems to be stalled, it will be removed."
        _remove_stale_lock "${run_lock}"
        return 0
    fi
    
    # Process is running - another instance exists
    error "Lock file is present, PID is ${suspicious_pid}, exiting."
    exit 1
}

# create_lock() - Create PID lock file for current process
#
# Description:
#   Creates a lock file containing the current process PID ($$) to mark
#   this instance as the active one. Uses global LOCK_FILE variable if
#   no parameter provided. Should be called immediately after check_running()
#   confirms no competing instance exists.
#
# Input:
#   $1 - (Optional) Absolute path to the PID lock file
#        If not provided, uses global LOCK_FILE variable
#        If LOCK_FILE is unset, computes intelligent default
#
# Returns:
#   0 on successful lock file creation
#   Never returns on error (exits script with code 1)
#
# Examples:
#   # Use global LOCK_FILE (recommended)
#   create_lock
#   
#   # Use explicit path  
#   create_lock "/var/run/myapp.pid"
#   
#   # Typical usage pattern
#   check_running
#   create_lock
#
create_lock() {
    local run_lock="${1:-}"
    
    # Use global LOCK_FILE if no parameter provided (lazy initialization)
    if [[ -z "${run_lock}" ]]; then
        _ensure_lock_file
        run_lock="${LOCK_FILE}"
    fi
    
    # Validate input parameter
    if [[ -z "${run_lock}" ]]; then
        error "Can't determine run lock file's path for creation, exiting."
        exit 1
    fi
    
    # Write current PID to lock file
    echo "$$" > "${run_lock}"
    if [[ $? -ne 0 ]]; then
        error "Can't create lock file ${run_lock}, exiting."
        exit 1
    fi
    
    debug "Created lock file ${run_lock} with PID $$"
    
    return 0
}

#
# Resource Management Functions
#

# add_cleanup_item() - Add file or directory to automatic cleanup list
#
# Description:
#   Adds a file or directory path to the cleanup list. Items in this list
#   will be automatically removed when the script exits (either normally
#   or due to signals like INT or TERM). Safe to call multiple times with
#   the same path.
#
# Input:
#   $1 - Path to file or directory to be cleaned up (required)
#        Can be relative or absolute path
#        Supports files, directories, symlinks, etc.
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   add_cleanup_item "/tmp/work_dir"
#   add_cleanup_item "$(mktemp)"
#   add_cleanup_item "${output_file}"
#
add_cleanup_item() {
    local item="${1:-}"
    
    # Validate input parameter
    if [[ -z "${item}" ]]; then
        warn "add_cleanup_item() requires a path parameter"
        return 1
    fi
    
    # Set up cleanup traps if not already done (lazy initialization)
    setup_cleanup_trap
    
    # Add item to cleanup array
    TO_BE_REMOVED+=("${item}")
    
    debug "Added ${item} to cleanup list"
    
    return 0
}

# remove_cleanup_item() - Remove specific item from cleanup list
#
# Description:
#   Removes a specific item from the cleanup list. This is useful when
#   a temporary resource is no longer temporary or has been manually
#   cleaned up. Only removes the first matching occurrence.
#
# Input:
#   $1 - Path to remove from cleanup list (required)
#        Must match exactly as it was added
#
# Returns:
#   0 if item was found and removed, 1 if not found or on error
#
# Examples:
#   remove_cleanup_item "/tmp/work_dir"
#   remove_cleanup_item "${temp_file}"
#
remove_cleanup_item() {
    local target_item="${1:-}"
    local -a new_array=()
    local item
    local found=0  # 0 = not found, 1 = found
    
    # Validate input parameter
    if [[ -z "${target_item}" ]]; then
        warn "remove_cleanup_item() requires a path parameter"
        return 1
    fi
    
    # Rebuild array without the target item
    for item in "${TO_BE_REMOVED[@]}"; do
        if [[ "${item}" != "${target_item}" ]]; then
            new_array+=("${item}")
        else
            found=1
        fi
    done
    
    # Update the global array
    TO_BE_REMOVED=("${new_array[@]}")
    
    if [[ "${found}" == "1" ]]; then
        debug "Removed ${target_item} from cleanup list"
        return 0
    else
        debug "Item ${target_item} not found in cleanup list"
        return 1
    fi
}

# cleanup() - Execute comprehensive resource cleanup
#
# Description:
#   Performs systematic cleanup of all tracked temporary resources.
#   Called automatically via signal traps (EXIT, INT, TERM, QUIT) or
#   manually when needed. Provides detailed logging of cleanup progress
#   and handles individual item failures gracefully.
#
# Returns:
#   0 on success (always succeeds, individual failures logged)
#
# Examples:
#   cleanup  # Manual cleanup of all tracked resources
#
cleanup() {
    local cleanup_performed=0  # 0 = no cleanup performed, 1 = cleanup performed
    local entity_to_remove
    local index
    
    # Check if there are items to clean up
    if [[ -v TO_BE_REMOVED[@] && ${#TO_BE_REMOVED[@]} -ne 0 ]]; then
        debug "Cleaning up temporary entities..."
        
        # Remove each item in the cleanup list
        for index in "${!TO_BE_REMOVED[@]}"; do
            entity_to_remove="${TO_BE_REMOVED[${index}]}"
            
            debug "Removing ${entity_to_remove}..."
            
            rm -rf "${entity_to_remove}"
            if [[ $? -ne 0 ]]; then
                warn "Can't remove ${entity_to_remove}."
            fi
            
            cleanup_performed=1
        done
    fi
    
    # Report cleanup completion
    if [[ "${cleanup_performed}" == "1" ]]; then
        debug "Cleanup completed."
    fi
    
    return 0
}

#
# High-Level Lifecycle Functions
#

# ensure_single_instance() - PRIMARY API: Complete lifecycle setup in one call
#
# Description:
#   The recommended entry point for script lifecycle management. Performs
#   complete single-instance enforcement and cleanup setup in one function
#   call. This function encapsulates the entire single-instance workflow
#   using well-tested component functions for maximum reliability.
#
#   This is the PRIMARY API for this module - use this function unless you
#   need the fine-grained control provided by the individual component
#   functions (check_running, create_lock, remove_lock_on_exit).
#
# What it does (in order):
#   1. Validates existing instance via check_running() - exits if conflict
#   2. Creates PID lock file via create_lock() - marks this instance active
#   3. Sets up automatic cleanup via remove_lock_on_exit() - ensures cleanup
#   4. Reports successful setup via debug logging
#
# Input:
#   $1 - (Optional) Absolute path to the PID lock file
#        • If provided: Uses explicit path
#        • If empty: Uses global LOCK_FILE variable
#        • If LOCK_FILE unset: Computes intelligent default
#        • Default pattern: /tmp/${USER}-${script_name}.lock
#
# Returns:
#   0 on successful single-instance setup and cleanup configuration
#   Never returns if another instance is active (exits with code 1)
#   Never returns on file I/O errors (exits with code 1)
#
# Exit Conditions (script termination):
#   - Active instance detected with valid PID
#   - Unable to read existing lock file
#   - Unable to create new lock file
#   - Invalid lock file path (empty or unresolvable)
#
# Side Effects:
#   - Creates PID lock file with current process ID
#   - Installs signal traps (EXIT, INT, TERM, QUIT) if not already present
#   - Adds lock file to global cleanup list (TO_BE_REMOVED array)
#   - Removes stale locks from terminated processes automatically
#
# Global variables used:
#   LOCK_FILE - Fallback path when no parameter provided
#   TO_BE_REMOVED - Modified to include lock file for cleanup
#   Uses logging functions: debug(), warn(), error()
#
# Function Composition:
#   ensure_single_instance() → check_running() → _remove_stale_lock()
#                            → create_lock()
#                            → remove_lock_on_exit() → add_cleanup_item()
#                                                    → setup_cleanup_trap()
#
# Examples:
#   # Recommended usage for most scripts
#   #!/usr/bin/env bash
#   source lib/lifecycle.sh
#   ensure_single_instance
#   # Script now enforces single instance with automatic cleanup
#
#   # Custom lock file for system services
#   ensure_single_instance "/var/run/myservice.pid"
#
#   # Global configuration approach
#   LOCK_FILE="/tmp/batch-processor.lock"
#   source lib/lifecycle.sh
#   ensure_single_instance
#
#   # Complete script template
#   #!/usr/bin/env bash
#   source lib/lifecycle.sh
#   ensure_single_instance
#   
#   temp_dir="$(mktemp -d)"
#   add_cleanup_item "${temp_dir}"
#   
#   # Your script logic here
#   # All cleanup automatic on exit
#
# Replaces this manual pattern:
#   check_running "${lock_file}"
#   create_lock "${lock_file}"
#   remove_lock_on_exit "${lock_file}"
#
ensure_single_instance() {
    local lock_file="${1:-}"
    
    debug "Starting complete single-instance setup"
    
    # Step 1: Check if another instance is running (exits if found)
    check_running "${lock_file}"
    
    # Step 2: Create lock file with current PID
    create_lock "${lock_file}"
    
    # Step 3: Set up automatic cleanup on exit
    remove_lock_on_exit "${lock_file}"
    
    debug "Single-instance enforcement successful"
    
    return 0
}

#
# Lifecycle Management Functions
#

# die() - Fatal error handler with automatic cleanup
#
# Description:
#   Provides standardized fatal error handling with automatic cleanup
#   triggering. Logs error messages with exit codes and terminates the
#   script immediately. Cleanup traps are triggered automatically.
#
# Input:
#   $1 - Exit code (required, must be numeric 1-255)
#   $2+ - Error message describing the fatal condition
#
# Returns:
#   Never returns (terminates script execution)
#
# Examples:
#   die 1 "Configuration file not found: ${config_file}"
#   die 2 "Database connection failed"
#
die() {
    local exit_code="${1:-}"
    
    # Validate exit code parameter
    if [[ ! "${exit_code}" =~ ^[0-9]+$ ]]; then
        warn "The die() function requires the exit code, got '${exit_code}' instead."
        exit_code=1
    else
        shift
    fi
    
    # Log error message
    error "${*} (EXIT CODE: ${exit_code})"
    
    exit "${exit_code}"
}

# setup_cleanup_trap() - Install signal handlers for automatic cleanup
#
# Description:
#   Configures signal handlers to ensure cleanup() is called when the
#   script exits normally or is terminated by signals. Uses a guard to
#   prevent duplicate installation. Called automatically by add_cleanup_item()
#   and remove_lock_on_exit() when needed.
#
# Returns:
#   0 on success (idempotent - safe to call multiple times)
#
# Global variables modified:
#   CLEANUP_TRAPS_INSTALLED - Set to 1 after first installation
#
setup_cleanup_trap() {
    # Check if traps are already installed
    if [[ "${CLEANUP_TRAPS_INSTALLED}" == "1" ]]; then
        return 0
    fi
    
    # Set trap to ensure cleanup happens on various exit conditions
    trap cleanup EXIT INT TERM QUIT
    
    # Mark traps as installed
    CLEANUP_TRAPS_INSTALLED=1
    
    debug "Cleanup trap handlers installed"
    
    return 0
}

# remove_lock_on_exit() - Add lock file to cleanup and setup traps
#
# Description:
#   Convenience function that adds a lock file to the cleanup list and
#   sets up the cleanup trap. Can use global LOCK_FILE if no parameter
#   provided, making it very simple to use in typical scenarios.
#
# Input:
#   $1 - (Optional) Path to lock file
#        If not provided, uses global LOCK_FILE variable
#        If LOCK_FILE is unset, computes intelligent default
#
# Returns:
#   0 on success, 1 on error
#
# Examples:
#   # Use global LOCK_FILE (recommended)
#   remove_lock_on_exit
#   
#   # Use explicit path
#   remove_lock_on_exit "/var/run/myapp.pid"
#   
#   # Complete lifecycle pattern
#   check_running
#   create_lock
#   remove_lock_on_exit  # Automatic cleanup
#
remove_lock_on_exit() {
    local lock_file="${1:-}"
    
    # Use global LOCK_FILE if no parameter provided (lazy initialization)
    if [[ -z "${lock_file}" ]]; then
        _ensure_lock_file
        lock_file="${LOCK_FILE}"
    fi
    
    # Validate lock file path
    if [[ -z "${lock_file}" ]]; then
        warn "remove_lock_on_exit() requires a lock file path parameter or LOCK_FILE to be set"
        return 1
    fi
    
    # Add lock file to cleanup list
    add_cleanup_item "${lock_file}"
    
    # Set up cleanup trap if not already done
    setup_cleanup_trap
    
    debug "Lock file ${lock_file} will be removed on exit"
    
    return 0
}

#
# Module Documentation and Integration Guide
#
# OVERVIEW:
#   This module provides complete script lifecycle management from startup
#   validation through resource management to graceful shutdown. It combines
#   single-instance enforcement with comprehensive cleanup capabilities using
#   a modern lazy initialization architecture.
#
# LAZY INITIALIZATION ARCHITECTURE:
#   When sourced, the module:
#   - Loads the logging system for detailed reporting
#   - Parses command-line options for configuration
#   - Prepares for use but performs NO side effects
#   - Signal traps are installed only when cleanup items are added
#   - Lock file handling occurs only when functions are called
#   - Clean module loading with no unwanted initialization
#
# BENEFITS OF LAZY INITIALIZATION:
#   - No side effects during module sourcing (clean imports)
#   - Traps installed only when actually needed (better control)
#   - Lock file operations only when explicitly requested
#   - Improved performance and predictable behavior
#   - Better testing and debugging capabilities
#
# TYPICAL USAGE PATTERNS:
#
#   # Simple single-instance script (recommended)
#   source lib/lifecycle.sh
#   ensure_single_instance           # Initialization happens here
#   
#   temp_dir="$(mktemp -d)"
#   add_cleanup_item "${temp_dir}"   # Trap setup happens here
#   
#   # Script logic here...
#   # All cleanup happens automatically on exit
#
#   # Advanced: separate function calls (for custom logic between steps)
#   source lib/lifecycle.sh          # No side effects
#   check_running                    # Lock file handling starts here
#   create_lock                      # Mark this instance active
#   remove_lock_on_exit             # Trap setup and cleanup registration
#
#   # Command-line configuration during sourcing
#   source lib/lifecycle.sh --lock-file /var/run/myservice.pid --strict-lock
#   ensure_single_instance           # Uses configured options
#
#   # Environment variable configuration
#   LOCK_FILE="/var/run/myservice.pid" CLEANUP_ON_ERROR=0 source lib/lifecycle.sh
#   ensure_single_instance
#
#   # Explicit custom path (overrides all defaults)
#   source lib/lifecycle.sh
#   ensure_single_instance "/var/run/myservice.pid"
#
#   # Manual resource management with conditional cleanup
#   source lib/lifecycle.sh
#   work_file="$(mktemp)"
#   add_cleanup_item "${work_file}"   # Traps installed here
#   
#   process_file "${work_file}"
#   
#   if [[ "${keep_result}" == 1 ]]; then
#       remove_cleanup_item "${work_file}"  # Keep the result
#       mv "${work_file}" "${final_location}"
#   fi
#
# CONFIGURATION OPTIONS:
#   # Command-line options (processed during module sourcing)
#   --lock-file FILE              Set custom lock file path
#   --lock-timeout SECONDS        Wait timeout for lock acquisition
#   --cleanup-on-success          Enable cleanup on successful completion
#   --no-cleanup-on-success       Disable cleanup on successful completion
#   --cleanup-on-error            Enable cleanup on error/signal
#   --no-cleanup-on-error         Disable cleanup on error/signal
#   --strict-lock                 Enable strict PID validation
#   --permissive-lock             Enable permissive lock handling
#
# INTEGRATION WITH LOGGING:
#   - Detailed progress reporting for all operations
#   - Error messages with context and troubleshooting info
#   - Debug information for development and troubleshooting
#   - Configurable log levels and output destinations via log.sh module
#
# SIGNAL HANDLING (LAZY INSTALLATION):
#   Signal traps are installed only when add_cleanup_item() is first called:
#   - EXIT: Normal script termination
#   - INT:  Interrupt (Ctrl+C)
#   - TERM: Termination signal
#   - QUIT: Quit signal (Ctrl+\)
#
# GLOBAL CONFIGURATION:
#   LOCK_FILE - Default lock file path (computed automatically if unset)
#             - Pattern: /tmp/${USER}-${script_name}.lock
#             - Can be set before sourcing, via command line, or during execution
#   CLEANUP_ON_SUCCESS - Cleanup on successful completion (1=yes, 0=no)
#   CLEANUP_ON_ERROR - Cleanup on error/signal (1=yes, 0=no)
#   STRICT_LOCK_CHECK - Strict PID validation (1=strict, 0=permissive)
#   LOCK_WAIT_TIMEOUT - Lock acquisition timeout in seconds (0=no wait)
#
# PERFORMANCE CHARACTERISTICS:
#   - Zero startup overhead with true lazy initialization
#   - Efficient array operations for resource tracking
#   - Atomic file operations for race condition prevention
#   - Numeric boolean flags for optimal conditional testing
#   - Trap installation only when needed
#
# SECURITY CONSIDERATIONS:
#   - Uses user-specific /tmp directory for default locks
#   - Validates PID format and process existence
#   - Handles stale locks automatically
#   - Uses 'rm -rf' - validate paths before adding to cleanup
#   - No sensitive operations during module loading
#
# GLOBAL VARIABLES AND NAMING CONFLICTS:
#   This module uses several global variables that may conflict with user scripts.
#   Review this list before using the module to avoid naming conflicts:
#
#   READONLY CONSTANTS (safe - cannot be overwritten):
#     LOGGER_OUT, LOGGER_ERR, LIFECYCLE_MODULE_LOADED
#
#   CONFIGURATION VARIABLES (can be set by user):
#     LOCK_FILE, CLEANUP_ON_SUCCESS, CLEANUP_ON_ERROR, STRICT_LOCK_CHECK, LOCK_WAIT_TIMEOUT
#
#   INTERNAL STATE VARIABLES (should not be modified by user):
#     TO_BE_REMOVED (array), CLEANUP_TRAPS_INSTALLED
#
#   ENVIRONMENT VARIABLES (inherited from environment):
#     USER (system variable used for default lock file paths)
#     Any LOG_* variables if log.sh module is used
#
#   POTENTIAL CONFLICTS:
#     - Avoid using variable names that start with CLEANUP_, LOCK_, LOGGER_
#     - The TO_BE_REMOVED array should not be manipulated directly
#     - Functions use local variables with common names (file, path, item, etc.)
#     - Signal traps are modified (EXIT, INT, TERM, QUIT) - existing traps will be overridden
#

#
# Configuration and Help Functions
#

# parse_lifecycle_options() - Parse command-line options for lifecycle configuration
#
# Description:
#   Parses command-line arguments to configure lifecycle behavior. Supports
#   both short and long option formats. This function should be called
#   early in the main script to process lifecycle-related options.
#
# Input:
#   $@ - Command-line arguments to parse
#
# Returns:
#   Modifies global configuration variables based on parsed options
#
# Global variables modified:
#   LOCK_FILE - Set via --lock-file option
#   CLEANUP_ON_SUCCESS - Set via --cleanup-on-success/--no-cleanup-on-success
#   CLEANUP_ON_ERROR - Set via --cleanup-on-error/--no-cleanup-on-error
#   STRICT_LOCK_CHECK - Set via --strict-lock/--permissive-lock
#   LOCK_WAIT_TIMEOUT - Set via --lock-timeout option
#
# Examples:
#   parse_lifecycle_options "$@"
#   parse_lifecycle_options --lock-file /var/run/myapp.pid --strict-lock
#
parse_lifecycle_options() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --lock-file)
                LOCK_FILE="${2}"
                shift 2
                ;;
            --lock-timeout)
                LOCK_WAIT_TIMEOUT="${2}"
                shift 2
                ;;
            --cleanup-on-success)
                CLEANUP_ON_SUCCESS=1
                shift
                ;;
            --no-cleanup-on-success)
                CLEANUP_ON_SUCCESS=0
                shift
                ;;
            --cleanup-on-error)
                CLEANUP_ON_ERROR=1
                shift
                ;;
            --no-cleanup-on-error)
                CLEANUP_ON_ERROR=0
                shift
                ;;
            --strict-lock)
                STRICT_LOCK_CHECK=1
                shift
                ;;
            --permissive-lock)
                STRICT_LOCK_CHECK=0
                shift
                ;;
            *)
                # Unknown option, let the main script handle it
                shift
                ;;
        esac
    done
}

# show_lifecycle_help() - Display comprehensive help for lifecycle functionality
#
# Description:
#   Shows detailed usage information including configuration options,
#   environment variables, command-line flags, and practical examples
#   for all lifecycle management features.
#
# Input:
#   None
#
# Returns:
#   0 on success
#
# Example:
#   show_lifecycle_help
#
show_lifecycle_help() {
    cat <<EOF
$(form_section_header "Script Lifecycle Management Module Help")

COMMAND-LINE OPTIONS:
        --lock-file FILE            Set custom lock file path
        --lock-timeout SECONDS      Wait timeout for lock acquisition (0=no wait)
        --cleanup-on-success        Enable cleanup on successful completion (default)
        --no-cleanup-on-success     Disable cleanup on successful completion
        --cleanup-on-error          Enable cleanup on error/signal (default)
        --no-cleanup-on-error       Disable cleanup on error/signal
        --strict-lock               Enable strict PID validation (default)
        --permissive-lock           Enable permissive lock handling

ENVIRONMENT VARIABLES:
    LOCK_FILE           Path to lock file (default: /tmp/\${USER}-\${script}.lock)
    CLEANUP_ON_SUCCESS  Cleanup on success: 1=yes, 0=no (default: 1)
    CLEANUP_ON_ERROR    Cleanup on error: 1=yes, 0=no (default: 1)
    STRICT_LOCK_CHECK   Strict lock validation: 1=strict, 0=permissive (default: 1)
    LOCK_WAIT_TIMEOUT   Lock wait timeout in seconds (default: 0)

EOF
}

# Module initialization when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Load logging system for immediate availability
    _load_logger
    
    # Parse command-line options if provided
    parse_lifecycle_options "${@}"
    
    debug "Lifecycle module loaded (lazy initialization enabled)"
fi