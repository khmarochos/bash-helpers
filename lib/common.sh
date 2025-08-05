#!/usr/bin/env bash

# Early return if module already loaded
[[ "${COMMON_HELPERS_LOADED:-0}" == "1" ]] && return 0

# Marker to indicate this module has been loaded (1 = loaded, 0 = not loaded)
if [[ -z "${COMMON_HELPERS_LOADED:-}" ]]; then
    declare -r COMMON_HELPERS_LOADED=1
fi

# _load_config_module() - Load config.sh module if available
#
# Description:
#   Attempts to load the config.sh module for configuration integration.
#   Intended to be used by other modules that need configuration support.
#
# Returns:
#   0 if config module is loaded or already available
#   1 if config module cannot be found
#
# Global variables used:
#   CONFIG_MODULE_LOADED - Set by config.sh module when loaded
#
_load_config_module() {
    # Check if config module is already loaded
    if [[ "${CONFIG_MODULE_LOADED:-0}" == "1" ]]; then
        return 0
    fi

    # Determine library directory relative to the calling script
    local lib_dir
    lib_dir="$(dirname "$(readlink -f "${BASH_SOURCE[1]}")")"

    # Path to the config module
    local config_module_path="${lib_dir}/config.sh"

    # Check if config module exists and source it
    if [[ -f "${config_module_path}" ]]; then
        source "${config_module_path}"
        return 0
    else
        # Config module not available, continue without it
        return 1
    fi
}

