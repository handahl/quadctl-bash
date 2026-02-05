#!/usr/bin/env bash
# ==============================================================================
# FILE: env.bash
# PATH: src/core/env.bash
# PROJECT: quadctl
# VERSION: 10.7.0
# DATE: 2026-01-18
# DESCRIPTION: Global variable definitions, Prefix Governance, and Logging.
# ==============================================================================

# 1. VERSIONING & IDENTITY
# ------------------------------------------------------------------------------
export Q_VERSION="11.0.0"

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
    export Q_ARCH_PREFIX="quadctl-"
    export Q_ENV_WARNING="true" 
else
    export Q_ARCH_PREFIX="${QUADCTL_PREFIX}"
    export Q_ENV_WARNING="false"
fi

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
    echo -e "${Q_COLOR_YELLOW}:: [quadctl} Defaulting prefix to '${Q_ARCH_PREFIX}'${Q_COLOR_RESET}" >&2
    echo -e "${Q_COLOR_YELLOW}   Set QUADCTL_PREFIX in your .bashrc to override.${Q_COLOR_RESET}" >&2
fi