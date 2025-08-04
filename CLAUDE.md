# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a bash-helpers repository focused on providing reusable Bash modules and utilities. The codebase follows modern Bash practices and emphasizes parameterization, modularity, and comprehensive logging.

## Architecture

### Module Structure
- `lib/` - Contains reusable Bash modules that can be sourced by scripts
- **`lib/log.sh`** - Enhanced logging module with support for:
  - Console output (stdout/stderr) with configurable suppression
  - File logging with timestamps and structured format
  - Log level filtering (DEBUG, INFO, WARN, ERROR)
  - Command-line and environment variable configuration
- **`lib/lifecycle.sh`** - Complete script lifecycle management:
  - Single-instance enforcement with PID-based locking
  - Automatic resource cleanup on exit/signal
  - Signal handling (EXIT, INT, TERM, QUIT)
  - Lazy initialization architecture
- **`lib/config.sh`** - Comprehensive configuration management:
  - Multi-format support (INI, JSON, YAML)
  - Priority-based loading (CLI > env > files > defaults) 
  - Environment variable mapping with custom prefixes/suffixes
  - Type conversion and validation

### Primary Module APIs

#### Lifecycle Module (lib/lifecycle.sh)
Key functions:
- `ensure_single_instance()` - Complete lifecycle setup in one call
- `add_cleanup_item()` - Add files/directories for automatic cleanup
- `remove_cleanup_item()` - Remove items from cleanup list
- `die()` - Fatal error handler with cleanup

#### Logging Module (lib/log.sh)
Key functions:
- `log()` - INFO level messages to stdout
- `warn()` - WARNING messages to stderr
- `error()` - ERROR messages to stderr with "ERROR:" prefix
- `debug()` - DEBUG messages (only shown when LOG_LEVEL=DEBUG)

#### Configuration Module (lib/config.sh)
Key functions:
- `load_config()` - Load configuration from multiple sources
- `get_config()` - Retrieve configuration value with type conversion
- `set_config()` - Set configuration value with validation
- `define_config_overrides()` - Define explicit override mappings

## Common Commands

### Testing Scripts
```bash
# Run a test script (example)
./test1.sh

# Run with different log levels
LOG_LEVEL=DEBUG ./test1.sh
LOG_LEVEL=ERROR ./test1.sh

# Log to file
LOG_FILE=/tmp/test.log ./test1.sh

# Quiet mode (no console output)
BE_QUIET=true ./test1.sh
```

### Module Usage Patterns

#### Basic Script with Lifecycle Management
```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/lifecycle.sh"

ensure_single_instance
temp_dir="$(mktemp -d)"
add_cleanup_item "${temp_dir}"

# Script logic here - cleanup automatic on exit
```

#### Configuration-Driven Script
```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/config.sh"

parse_config_options "$@"
load_config "app.conf"

host="$(get_config "database.host" "localhost")"
port="$(get_config "database.port" "5432" "int")"
```

#### All Modules Integration
```bash
#!/usr/bin/env bash

LIB_DIR="$(dirname "$(readlink -f "${0}")")/lib"
source "${LIB_DIR}/log.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/lifecycle.sh"

# Configuration and lifecycle setup
parse_config_options "$@"
load_config "app.conf"
ensure_single_instance

# Application logic with logging and cleanup
log "Application started"
# Automatic cleanup on exit
```

## Code Standards

- Use contemporary Bash syntax (`[[` instead of `[`)
- Local variables in lowercase, global variables in UPPERCASE
- Proper variable quoting with curly braces: `"${variable}"`
- Functions must have comprehensive comments describing purpose, inputs, outputs, and variables used
- Scripts should support both command-line options (short/long) and environment variables
- Logging functions direct warnings/errors to stderr (&2)