#!/usr/bin/env bash
# Core: Bootloader
# Author: SAC-CP (v2.1)
# Description: The ONLY file allowed to calculate paths and source dependencies.

# 1. Establish Root & Prefix
_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# We need to find the project root relative to this file.
# If we are in /src/core/loader.bash -> Root is ../../
if [[ -d "$(dirname "${_LOADER_DIR}")/api" ]]; then
    # We are inside 'src'
    QUADCTL_HOME="$(dirname "$(dirname "${_LOADER_DIR}")")"
    _SRC_PREFIX="/src"
else
    # Fallback/Flattened
    QUADCTL_HOME="$(dirname "${_LOADER_DIR}")"
    _SRC_PREFIX=""
fi

export QUADCTL_HOME

# 2. Load Environment Primitives
if [[ -f "${QUADCTL_HOME}${_SRC_PREFIX}/core/env.bash" ]]; then
    source "${QUADCTL_HOME}${_SRC_PREFIX}/core/env.bash"
else
    echo "!! [FATAL] Bootloader: Missing core/env.bash at ${QUADCTL_HOME}${_SRC_PREFIX}/core/env.bash"
    exit 99
fi

source "${QUADCTL_HOME}${_SRC_PREFIX}/core/deps.bash"

# 3. Load API Layer
source "${QUADCTL_HOME}${_SRC_PREFIX}/api/systemd.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/api/podman.bash"

# 4. Load Logic Layer (Functions Only)
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/matrix.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/tree.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/logs.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/control.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/audit.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/doctor.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/debug.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/deploy.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/migrate.bash"

# 5. Load UI Layer
source "${QUADCTL_HOME}${_SRC_PREFIX}/ui/help.bash"

# 6. Load Shell & Interaction
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/shell.bash"

# Only source interact if strictly needed (usually it's the caller)
if [[ -f "${QUADCTL_HOME}${_SRC_PREFIX}/logic/interact.bash" ]]; then
    source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/interact.bash"
fi