#!/usr/bin/env bash
# Core: Bootloader (Debug Mode)
# Author: SAC-CP (v2.1)

# 1. Establish Root & Prefix
_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logic: If we are in .../src/core, parent is src.
if [[ -d "$(dirname "${_LOADER_DIR}")/api" ]]; then
    # We are inside 'src'
    QUADCTL_HOME="$(dirname "$(dirname "${_LOADER_DIR}")")"
    _SRC_PREFIX="/src"
else
    # Fallback/Flattened (e.g. core/loader.bash -> root/core -> root)
    QUADCTL_HOME="$(dirname "${_LOADER_DIR}")"
    _SRC_PREFIX=""
fi

export QUADCTL_HOME

# 2. Dependency Helper
_load_module() {
    local rel_path="$1"
    local full_path="${QUADCTL_HOME}${_SRC_PREFIX}/${rel_path}"
    
    if [[ -f "$full_path" ]]; then
        source "$full_path"
    else
        echo "!! [FATAL] Loader failed to find: $full_path" >&2
        exit 99
    fi
}

# 3. Load Core (Environment first!)
_load_module "core/env.bash"
_load_module "core/deps.bash"

# 4. Load API Layer
_load_module "api/systemd.bash"
_load_module "api/podman.bash"

# 5. Load Logic Layer
_load_module "logic/matrix.bash"
_load_module "logic/tree.bash"
_load_module "logic/logs.bash"
_load_module "logic/control.bash"
_load_module "logic/audit.bash"
_load_module "logic/doctor.bash"
_load_module "logic/debug.bash"
_load_module "logic/deploy.bash"
_load_module "logic/migrate.bash"

# 6. Load UI Layer
_load_module "ui/help.bash"

# 7. Load Shell & Interaction
_load_module "logic/shell.bash"

# Only source interact if strict path exists
if [[ -f "${QUADCTL_HOME}${_SRC_PREFIX}/logic/interact.bash" ]]; then
    source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/interact.bash"
fi