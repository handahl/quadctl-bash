#!/usr/bin/env bash
# Core: Environment & Logging
# Author: SAC-CP (v2.1)

# Export variables
export QUADCTL_VERSION="2.1"
export QUADCTL_ARCH_PREFIX="${QUADCTL_ARCH_PREFIX:-hanlab-}"

# Logging Primitives
# We export these functions to ensure they are available in subshells/pipes.

# ANSI Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}:: [INFO]${NC} $*"
}
export -f echo_info

echo_success() {
    echo -e "${GREEN}:: [OK]${NC}   $*"
}
export -f echo_success

echo_warn() {
    echo -e "${YELLOW}!! [WARN]${NC} $*"
}
export -f echo_warn

echo_error() {
    echo -e "${RED}!! [ERR]${NC}  $*" >&2
}
export -f echo_error

echo_debug() {
    if [[ "${QUADCTL_DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}__ [DBG]${NC}  $*" >&2
    fi
}
export -f echo_debug