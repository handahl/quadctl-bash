#!/usr/bin/env bash
# ==============================================================================
# FILE: xdg-bootstrap.sh
# PATH: scripts/xdg-bootstrap.sh
# PROJECT: quadctl
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Enforces XDG directory structure. Converts "Intent" to "Reality".
# ==============================================================================

set -euo pipefail

# 1. DEFINE STANDARD PATHS (Canonical Truth)
# ------------------------------------------------------------------------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_BIN_HOME:=$HOME/.local/bin}"

# The "Intent" Source (Git Repo)
# You should clone your quadlet-intent repo here.
SRC_ROOT="$HOME/src/containers/intent"

# The "Runtime" Targets (Systemd)
TARGET_QUADLETS="$XDG_CONFIG_HOME/containers/systemd"
TARGET_UNITS="$XDG_CONFIG_HOME/systemd/user"

# Tool State
TOOL_STATE="$XDG_STATE_HOME/quadctl"
TOOL_DATA="$XDG_DATA_HOME/quadctl"

# 2. SCAFFOLDING EXECUTION
# ------------------------------------------------------------------------------
echo ":: [SAC-CP] Enforcing XDG Filesystem Standard..."

# Create core directories with correct permissions
mkdir -p -m 700 "$TARGET_QUADLETS"
mkdir -p -m 700 "$TARGET_UNITS"
mkdir -p -m 700 "$TOOL_STATE"
mkdir -p -m 755 "$TOOL_DATA"
mkdir -p -m 755 "$XDG_BIN_HOME"
mkdir -p -m 755 "$SRC_ROOT"

# 3. INTENT STRUCTURE
# ------------------------------------------------------------------------------
# We enforce the specific folder structure required by the 'deploy' logic
# to prevent "rsync flattening" errors.
echo ":: Structuring Source of Truth at $SRC_ROOT..."

for type in container volume network image pod user-units; do
    dir="$SRC_ROOT/$type"
    if [[ ! -d "$dir" ]]; then
        echo "   + Creating $dir"
        mkdir -p "$dir"
        # Seed with a .keep file to preserve structure in git
        touch "$dir/.keep"
    fi
done

# 4. PATH VERIFICATION
# ------------------------------------------------------------------------------
echo ":: Verifying Environment..."

# Check PATH
if [[ ":$PATH:" != *":$XDG_BIN_HOME:"* ]]; then
    echo "!! [WARN] $XDG_BIN_HOME is not in your \$PATH."
    echo "   Please add the following to your .bashrc or .zshrc:"
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
else
    echo "   + PATH includes local bin."
fi

echo ":: [SUCCESS] Filesystem is XDG Compliant."