# Bash Helpers Package Features

This document describes the packaging and distribution features provided by the GitHub Actions workflows.

## Automated Package Building

### Trigger Conditions

The package workflow runs automatically on:

- **Git tags starting with 'release-'** (e.g., `release-1.0.0`, `release-2.1.3`) - Creates official releases
- **Pull requests** to main/master branches - Tests package building
- **Manual trigger** via GitHub Actions UI - On-demand builds

### Build Process

1. **Testing Phase**
   - Tests log module functionality
   - Tests lifecycle module functionality  
   - Tests integration between modules
   - Validates shell syntax with `bash -n`
   - Tests single-instance enforcement

2. **Package Creation**
   - Creates versioned package directory structure
   - Copies library files (`lib/*.sh`)
   - Includes documentation (`README.md`, `CLAUDE.md`)
   - Generates automated installation script
   - Creates usage examples
   - Adds package metadata and version information

3. **Release Creation** (tags only)
   - Creates GitHub release with generated notes
   - Uploads tarball with SHA256 checksum
   - Provides installation instructions

## Package Contents

When you download a release package, you get:

```
bash-helpers-release-1.0.0/
├── lib/                          # Core library modules
│   ├── lifecycle.sh             # Complete script lifecycle management
│   └── log.sh                   # Enhanced logging system
├── examples/                     # Ready-to-use examples
│   ├── simple-script.sh         # Basic lifecycle example
│   └── service-script.sh        # Service daemon example
├── install.sh                   # Automated installer
├── README.md                    # Complete documentation
├── CLAUDE.md                    # Development guidelines
├── PACKAGE_INFO.md              # Package-specific information
└── VERSION                      # Build metadata
```

## Installation Options

### 1. Automated Installation (Recommended)

```bash
# Download and extract
wget https://github.com/your-username/bash-helpers/releases/latest/download/bash-helpers-latest.tar.gz
tar -xzf bash-helpers-latest.tar.gz
cd bash-helpers-*/

# Install to default location (~/.local/lib/bash-helpers)
./install.sh

# Or install to custom location
./install.sh /opt/bash-helpers
```

### 2. Manual Installation

```bash
# Extract and copy manually
tar -xzf bash-helpers-release-1.0.0.tar.gz
cp -r bash-helpers-release-1.0.0/lib ~/.local/lib/bash-helpers
```

### 3. Development Installation

```bash
# Clone repository for latest development version
git clone https://github.com/your-username/bash-helpers.git
cd bash-helpers
cp -r lib ~/.local/lib/bash-helpers
```

## Usage After Installation

### Standard Usage

```bash
# In your scripts
LIB_DIR="${HOME}/.local/lib/bash-helpers"
source "${LIB_DIR}/log.sh" --log-level DEBUG
source "${LIB_DIR}/lifecycle.sh"

ensure_single_instance
log "Script started"
```

### Using Setup Helper

The installer creates a setup helper script for convenience:

```bash
# Source the setup helper
source ~/.local/lib/bash-helpers/setup.sh

# Load modules with helper function
load_bash_helper log --log-level DEBUG
load_bash_helper lifecycle --lock-file /tmp/myapp.pid

ensure_single_instance
log "Script started with helper"
```

## Package Verification

Each release includes SHA256 checksums for security:

```bash
# Download both files
wget https://github.com/your-username/bash-helpers/releases/download/release-1.0.0/bash-helpers-release-1.0.0.tar.gz
wget https://github.com/your-username/bash-helpers/releases/download/release-1.0.0/bash-helpers-release-1.0.0.tar.gz.sha256

# Verify integrity
sha256sum -c bash-helpers-release-1.0.0.tar.gz.sha256
```

## Continuous Integration

### Test Matrix

- **Operating Systems**: Ubuntu Latest, Ubuntu 20.04
- **Shell Compatibility**: Bash 4.0+ (standard on modern systems)
- **Syntax Validation**: ShellCheck linting
- **Functionality Tests**: All core features tested

### Quality Checks

- ✅ Module loading and initialization
- ✅ Single-instance enforcement
- ✅ Resource cleanup functionality
- ✅ Logging system integration
- ✅ Configuration option parsing
- ✅ Shell syntax validation
- ✅ Cross-platform compatibility

## Release Workflow

### For Maintainers

To create a new release:

```bash
# 1. Update version and tag
git tag release-1.2.0
git push origin release-1.2.0

# 2. GitHub Actions automatically:
#    - Runs full test suite  
#    - Builds package
#    - Creates GitHub release
#    - Uploads artifacts with checksums
```

### For Users

To stay updated:

```bash
# Check for new releases
curl -s https://api.github.com/repos/your-username/bash-helpers/releases/latest | jq -r '.tag_name'

# Download latest
curl -L https://github.com/your-username/bash-helpers/releases/latest/download/bash-helpers-latest.tar.gz | tar -xz

# Reinstall 
cd bash-helpers-*/
./install.sh
```

## Advanced Features

### Environment Variables

The package respects these environment variables during installation:

- `BASH_HELPERS_INSTALL_DIR` - Override default installation directory
- `BASH_HELPERS_NO_SETUP` - Skip creating setup.sh helper script

### Integration Testing

Example integration test with installed package:

```bash
#!/usr/bin/env bash

# Test installed package
source ~/.local/lib/bash-helpers/lifecycle.sh --log-level DEBUG

# Test functionality
ensure_single_instance /tmp/integration-test.lock

temp_dir="$(mktemp -d)"
add_cleanup_item "${temp_dir}"

log "Integration test started"
echo "test data" > "${temp_dir}/test.txt"

# Verify file exists
[[ -f "${temp_dir}/test.txt" ]] || die 1 "Test file not created"

log "Integration test completed successfully"
# Cleanup happens automatically
```

## Support and Compatibility

### Supported Platforms

- ✅ Ubuntu 18.04+
- ✅ CentOS 7+
- ✅ macOS 10.14+
- ✅ Any system with Bash 4.0+

### Dependencies

**Runtime Dependencies:**
- Bash 4.0 or later
- Standard POSIX utilities (`mkdir`, `rm`, `ps`, `date`, etc.)

**Development Dependencies (for contributors):**
- Git
- ShellCheck (for linting)
- GNU tar (for package creation)

### Compatibility Notes

- Uses contemporary Bash features (arrays, `[[` conditions)
- Avoids non-portable constructs
- Tested on multiple Linux distributions
- Compatible with both GNU and BSD utilities where possible