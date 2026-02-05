#!/usr/bin/env bash
# Core: Environment & Logging
# Author: SAC-CP (v2.1)

# Export variables
export QUADCTL_VERSION="2.1"
export QUADCTL_ARCH_PREFIX="${QUADCTL_ARCH_PREFIX:-hanlab-}"

# Logging Primitives
# We export these functions to ensure they are available in subshells/pipes.

echo_info() {
    echo -e ":: [INFO] $*"
}
export -f echo_info

echo_success() {
    echo -e ":: [OK]   $*"
}
export -f echo_success

echo_warn() {
    echo -e "!! [WARN] $*"
}
export -f echo_warn

echo_error() {
    echo -e "!! [ERR]  $*" >&2
}
export -f echo_error

echo_debug() {
    if [[ "${QUADCTL_DEBUG:-0}" == "1" ]]; then
        echo -e "__ [DBG]  $*" >&2
    fi
}
export -f echo_debug