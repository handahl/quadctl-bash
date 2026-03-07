#!/usr/bin/env bash
# ==============================================================================
# FILE: env.bash
# PATH: src/core/env.bash
# PROJECT: quadctl
# VERSION: 11.1.0
# DATE: 2026-03-04
# DESCRIPTION: Global variable definitions, Prefix Governance, and Logging.
# ==============================================================================

# 1. VERSIONING & IDENTITY
# ------------------------------------------------------------------------------
export Q_VERSION="11.1.0"

# 2. XDG STANDARDS & DEFAULTS
# ------------------------------------------------------------------------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"

# 3. PREFIX GOVERNANCE
# ------------------------------------------------------------------------------
# The default is "quadctl-".
# If the user has not explicitly set their preference, we warn them (once)
# but proceed with the safe default.

if [[ -z "${QUADCTL_PREFIX:-}" ]]; then
    export Q_ARCH_PREFIX="homelab-"
    export Q_ENV_WARNING="true" 
else
    export Q_ARCH_PREFIX="${QUADCTL_PREFIX}"
    export Q_ENV_WARNING="false"
fi

# 3b. PLATFORM DETECTION (informational — not a gate)
# ------------------------------------------------------------------------------
# Q_PLATFORM: fedora-atomic | fedora | rocky | rhel | rhel-like | fedora-like | unknown
# Q_NODE_TIER: preferred | compat | unknown
# Consumed by deps.bash for tiered version warnings; available to all modules.
# ------------------------------------------------------------------------------
_detect_platform() {
    local os_id="" os_like=""
    if [[ -r /etc/os-release ]]; then
        os_id=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
        os_like=$(. /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}")
    fi
    case "$os_id" in
        fedora)
            if [[ -f /run/ostree-booted || -f /ostree/repo/config ]]; then
                echo "fedora-atomic"
            else
                echo "fedora"
            fi ;;
        rocky)  echo "rocky" ;;
        rhel)   echo "rhel"  ;;
        *)
            case "$os_like" in
                *rhel*|*centos*) echo "rhel-like"    ;;
                *fedora*)        echo "fedora-like"  ;;
                *)               echo "unknown"      ;;
            esac ;;
    esac
}

export Q_PLATFORM
Q_PLATFORM=$(_detect_platform)
unset -f _detect_platform

case "$Q_PLATFORM" in
    fedora-atomic|fedora|fedora-like) export Q_NODE_TIER="preferred" ;;
    rocky|rhel|rhel-like)             export Q_NODE_TIER="compat"    ;;
    *)                                export Q_NODE_TIER="unknown"   ;;
esac

# 4. PATH DEFINITIONS
# ------------------------------------------------------------------------------
export Q_CONFIG_DIR="${XDG_CONFIG_HOME}/containers/systemd"
export Q_USER_UNIT_DIR="${XDG_CONFIG_HOME}/systemd/user"
# The "Source of Intent" - defaulting to the standard SAC-CP structure
export Q_SRC_DIR="${QUADCTL_SRC:-$HOME/src/containers/intent}"
export Q_DATA_DIR="${XDG_DATA_HOME}/quadctl"
export Q_PODMAN_SOCK="${XDG_RUNTIME_DIR}/podman/podman.sock"

# 4. DISPLAY SETTINGS
# ------------------------------------------------------------------------------
# These are required by deps.bash and other modules.

if [[ -t 1 ]]; then
    export Q_COLOR_RED=$'\033[0;31m' 
    export Q_COLOR_GREEN=$'\033[0;32m'
    export Q_COLOR_YELLOW=$'\033[0;33m' 
    export Q_COLOR_BLUE=$'\033[0;34m'
    export Q_COLOR_PURP=$'\033[0;35m'
    export Q_COLOR_GREY=$'\033[0;30m'
    export Q_COLOR_BOLD=$'\033[1m'
    export Q_COLOR_RESET=$'\033[0m'
else
    export Q_COLOR_RED=""
    export Q_COLOR_GREEN=""
    export Q_COLOR_YELLOW=""
    export Q_COLOR_BLUE=""
    export Q_COLOR_PURP=""
    export Q_COLOR_GREY=""
    export Q_COLOR_BOLD=""
    export Q_COLOR_RESET=""
    fi

# 5. LOGGING PRIMITIVES
# ------------------------------------------------------------------------------
log_info()    { echo "${Q_COLOR_BLUE}[INFO]${Q_COLOR_RESET} $1" >&2; }
log_success() { echo "${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}   $1" >&2; }
log_warn()    { echo "${Q_COLOR_YELLOW}[WARN]${Q_COLOR_RESET} $1" >&2; }
log_err()     { echo "${Q_COLOR_RED}[ERR]${Q_COLOR_RESET}  $1" >&2; }

# 6. INITIALIZATION WARNING
# ------------------------------------------------------------------------------
# If we detected an unset prefix in interactive mode, warn the user now.
if [[ "$Q_ENV_WARNING" == "true" && -t 1 && "${Q_SILENT_ENV:-0}" == "0" ]]; then
    # We use a distinct format to separate it from standard logs
    log_info -e "${Q_COLOR_YELLOW}:: Defaulting prefix to '${Q_ARCH_PREFIX}'${Q_COLOR_RESET}" >&2
    echo -e "${Q_COLOR_YELLOW}   Set QUADCTL_PREFIX in your .bashrc to override.${Q_COLOR_RESET}" >&2
fi

#!/usr/bin/env bash
# src/core/utils.bash

# Portable search function
search_pattern() {
    local pattern="$1"
    local input="${2:-$(cat)}" # If $2 is empty, read from stdin (pipe)

    if command -v rg &>/dev/null; then
        echo "$input" | rg "$pattern"
    else
        echo "$input" | grep -E "$pattern"
    fi
}

# Systemd Specifier Expander
# Usage: expand_specifiers "%h/config" -> "/var/home/core/config"
expand_specifiers() {
    local path="$1"
    path="${path//%h/$HOME}"
    path="${path//%u/$USER}"
    path="${path/#\~/$HOME}"
    echo "$path"
}

# Append to the bottom of src/core/env.bash
source "$(dirname "${BASH_SOURCE[0]}")/utils.bash"