#!/usr/bin/env bash
# Core: Bootloader
# Author: SAC-CP (v2.1)
# Description: Centralized dependency injection. ONE source of truth for paths.

# 1. Self-Location (The only place this math happens)
#    We assume load.bash is in .../core/load.bash
_CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve Root
# If we are in .../src/core, root is ../../
if [[ -f "$(dirname "${_CURRENT_DIR}")/api/podman.bash" ]]; then
     # We are likely in .../src/core or .../core inside a flattened structure
     # Let's check parent
     if [[ -d "$(dirname "${_CURRENT_DIR}")/src" ]]; then
         # We are deep inside src/core? No, standard logic:
         # Repo: quadctl/src/core/load.bash -> Root: quadctl
         QUADCTL_HOME="$(dirname "$(dirname "${_CURRENT_DIR}")")"
         _PREFIX="/src"
     else
         # Install: quadctl/core/load.bash -> Root: quadctl
         QUADCTL_HOME="$(dirname "${_CURRENT_DIR}")"
         _PREFIX=""
     fi
else
    # Fallback/Safe Default
    QUADCTL_HOME="${HOME}/.local/share/quadctl"
    if [[ -d "${QUADCTL_HOME}/src" ]]; then _PREFIX="/src"; else _PREFIX=""; fi
fi

export QUADCTL_HOME

# 2. Source Core Primitives (Logging & Deps)
if [[ -f "${QUADCTL_HOME}${_PREFIX}/core/env.bash" ]]; then
    source "${QUADCTL_HOME}${_PREFIX}/core/env.bash"
else
    echo "!! [FATAL] Bootloader crashed. Cannot find core/env.bash at ${QUADCTL_HOME}${_PREFIX}/core/env.bash"
    exit 99
fi

source "${QUADCTL_HOME}${_PREFIX}/core/deps.bash"

# 3. Source APIs
source "${QUADCTL_HOME}${_PREFIX}/api/systemd.bash"
source "${QUADCTL_HOME}${_PREFIX}/api/podman.bash"

# 4. Source Logic Modules
#    (Order matters slightly: low-level logic first)
source "${QUADCTL_HOME}${_PREFIX}/logic/matrix.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/tree.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/logs.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/control.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/audit.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/doctor.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/debug.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/deploy.bash"
source "${QUADCTL_HOME}${_PREFIX}/logic/migrate.bash"

# 5. UI Components
source "${QUADCTL_HOME}${_PREFIX}/ui/help.bash"

# 6. Shell & Dispatch (High Level)
source "${QUADCTL_HOME}${_PREFIX}/logic/shell.bash"
# interact.bash is usually the caller, but we source it just in case
if [[ -f "${QUADCTL_HOME}${_PREFIX}/logic/interact.bash" ]]; then
    source "${QUADCTL_HOME}${_PREFIX}/logic/interact.bash"
fi

# Log success only if verbose debugging is requested, otherwise silent.
# echo_debug "Bootloader complete. Root: $QUADCTL_HOME"