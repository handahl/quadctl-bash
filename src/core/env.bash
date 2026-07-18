#!/usr/bin/env bash
##
### env.bash - Global environment, prefix governance, logging, verbosity.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : (none — this is the bootstrap layer)
## ==============================================================================================
#
set -euo pipefail

# --- 1. XDG BASE DIRECTORIES ---
# Reason: use ':=' to set-if-unset without overwriting a caller-provided value.
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"

# --- 2. VERBOSITY ---
# Reason: env var allows caller to pre-set verbosity (e.g. in a script);
# the shim's flag parsing will override via export before any module sources this.
# -1 = quiet (errors only), 0 = default, 1 = verbose, 2 = debug
export Q_VERBOSITY="${Q_VERBOSITY:-0}"

# --- 3. COLOR / TTY DETECTION ---
# Reason: check stderr (fd 2) because all log output goes to stderr.
# Checking stdout (fd 1) breaks color when the user pipes stdout to a file.
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    export Q_COLOR_RED=$'\033[0;31m'
    export Q_COLOR_GREEN=$'\033[0;32m'
    export Q_COLOR_YELLOW=$'\033[0;33m'
    export Q_COLOR_BLUE=$'\033[0;34m'
    export Q_COLOR_PURP=$'\033[0;35m'
    export Q_COLOR_GREY=$'\033[0;90m'
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

# --- 4. LOGGING PRIMITIVES ---
# All output goes to stderr. stdout is reserved for data (matrix, cat, etc).
#
# Default output (Q_VERBOSITY >= 0):
#   log_info    — plain message; no prefix. For state changes the operator cares about.
#   log_success — ✓ prefix; green. For successful completions.
#   log_warn    — [WARN] prefix; yellow. For advisory conditions.
#   log_err     — [ERR] prefix; red. For failures.
#
# Verbose output (Q_VERBOSITY >= 1):
#   log_verbose — → prefix; shows resolved commands and actions before they run.
#
# Debug output (Q_VERBOSITY >= 2):
#   log_debug   — [debug] prefix; resolution trace, raw data.

log_info() {
    (( Q_VERBOSITY >= 0 )) && printf "%s\n" "$1" >&2 || true
}

log_success() {
    (( Q_VERBOSITY >= 0 )) && \
        printf "%s✓%s %s\n" "${Q_COLOR_GREEN}" "${Q_COLOR_RESET}" "$1" >&2 || true
}

log_warn() {
    printf "%s[WARN]%s %s\n" "${Q_COLOR_YELLOW}" "${Q_COLOR_RESET}" "$1" >&2
}

log_err() {
    printf "%s[ERR]%s  %s\n" "${Q_COLOR_RED}" "${Q_COLOR_RESET}" "$1" >&2
}

log_verbose() {
    (( Q_VERBOSITY >= 1 )) && \
        printf "%s→%s %s\n" "${Q_COLOR_BLUE}" "${Q_COLOR_RESET}" "$1" >&2 || true
}

log_debug() {
    (( Q_VERBOSITY >= 2 )) && \
        printf "%s[debug]%s %s\n" "${Q_COLOR_GREY}" "${Q_COLOR_RESET}" "$1" >&2 || true
}

# --- 5. PREFIX GOVERNANCE ---
# Reason: env var is the right mechanism — it varies per node (han1 vs han3).
# Config file is loaded next (step 7) and can supply a default without shell profile changes.
if [[ -z "${QUADCTL_PREFIX:-}" ]]; then
    export Q_ARCH_PREFIX="homelab-"
    export Q_ENV_WARNING="true"
else
    export Q_ARCH_PREFIX="${QUADCTL_PREFIX}"
    export Q_ENV_WARNING="false"
fi

# --- 6. PATH DEFINITIONS ---
export Q_CONFIG_DIR="${XDG_CONFIG_HOME}/containers/systemd"
export Q_USER_UNIT_DIR="${XDG_CONFIG_HOME}/systemd/user"
export Q_SRC_DIR="${QUADCTL_SRC:-$HOME/src/containers/intent}"
export Q_DATA_DIR="${XDG_DATA_HOME}/quadctl"
export Q_PODMAN_SOCK="${XDG_RUNTIME_DIR}/podman/podman.sock"

# --- 7. CONFIG FILE ---
# Loaded after defaults so config can supply values only if env vars are unset.
# Precedence: flags (shim) > env vars > config file > defaults above.
_load_config() {
    local cfg="${XDG_CONFIG_HOME}/quadctl/config"
    [[ -f "$cfg" ]] || return 0

    while IFS='= ' read -r key value; do
        # Skip blank lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        # Strip inline comments
        value="${value%%#*}"
        # Strip surrounding whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        case "$key" in
            prefix)
                # Only apply if not already set by environment
                if [[ "$Q_ENV_WARNING" == "true" ]]; then
                    export QUADCTL_PREFIX="$value"
                    export Q_ARCH_PREFIX="$value"
                    export Q_ENV_WARNING="false"
                fi
                ;;
            src_dir)
                [[ -z "${QUADCTL_SRC:-}" ]] && export Q_SRC_DIR="$value" ;;
            verbosity)
                # Only apply if Q_VERBOSITY was not set by the caller
                [[ "${Q_VERBOSITY}" == "0" ]] && export Q_VERBOSITY="$value" ;;
        esac
    done < "$cfg"
}
_load_config
unset -f _load_config

# --- 8. PLATFORM DETECTION ---
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
        rocky) echo "rocky" ;;
        rhel)  echo "rhel"  ;;
        *)
            case "$os_like" in
                *rhel*|*centos*) echo "rhel-like"   ;;
                *fedora*)        echo "fedora-like" ;;
                *)               echo "unknown"     ;;
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

# --- 9. INITIALIZATION WARNING ---
# Only warn when interactive and warning has not been suppressed.
if [[ "$Q_ENV_WARNING" == "true" && -t 2 && "${Q_SILENT_ENV:-0}" == "0" ]]; then
    log_warn "QUADCTL_PREFIX not set. Defaulting to '${Q_ARCH_PREFIX}'."
    printf "         Set 'prefix = hanlab-' in %s/quadctl/config or export QUADCTL_PREFIX.\n" \
        "${XDG_CONFIG_HOME}" >&2
fi
