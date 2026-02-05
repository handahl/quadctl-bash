#!/usr/bin/env bash
# Core: Bootloader
# Author: SAC-CP (v2.1)
# Description: Centralized dependency injection. ONE source of truth for paths.

# 1. Self-Location (The only place this math happens)
_CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve Root
# Repo: quadctl/src/core/loader.bash -> Root: quadctl (../../)
# Install: quadctl/core/loader.bash -> Root: quadctl (../)

if [[ -f "$(dirname "${_CURRENT_DIR}")/api/podman.bash" ]]; then
     if [[ -d "$(dirname "${_CURRENT_DIR}")/src" ]]; then
         QUADCTL_HOME="$(dirname "$(dirname "${_CURRENT_DIR}")")"
         _PREFIX="/src"
     else
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

# 6. Shell & Dispatch
source "${QUADCTL_HOME}${_PREFIX}/logic/shell.bash"
if [[ -f "${QUADCTL_HOME}${_PREFIX}/logic/interact.bash" ]]; then
    source "${QUADCTL_HOME}${_PREFIX}/logic/interact.bash"
fi