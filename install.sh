#!/usr/bin/env bash
# Installer: Quadctl
# Author: SAC-CP (v2.1)

set -euo pipefail

# Standard XDG paths
INSTALL_DIR="${HOME}/.local/share/quadctl"
BIN_DIR="${HOME}/.local/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ":: [SAC-CP] Initializing Quadctl Deployment..."

# 0. CRITICAL SAFETY CHECK
# Prevent the script from deleting itself if run from the install dir.
if [[ "$SOURCE_DIR" == "$INSTALL_DIR" ]]; then
    echo "!! [FATAL] Deployment Error"
    echo "   You are running install.sh from inside the target directory: $INSTALL_DIR"
    echo "   This would cause the script to delete itself during cleanup."
    echo ""
    echo "   [CORRECTION]"
    echo "   1. Move your source code to a staging area (e.g., ~/quadctl-source)"
    echo "   2. Run install.sh from there."
    exit 1
fi

# 1. Clean & Prepare Target
if [[ -d "$INSTALL_DIR" ]]; then
    echo ":: Cleaning previous installation..."
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 2. Deploy Artifacts
echo ":: Deploying artifacts..."
if [[ -d "${SOURCE_DIR}/src" ]]; then
    # We copy the 'src' folder structure intact
    cp -r "${SOURCE_DIR}/src" "${INSTALL_DIR}/"
else
    echo "!! [FATAL] 'src' directory missing in source."
    exit 1
fi

# Copy docs if they exist
cp "${SOURCE_DIR}/"*.md "${INSTALL_DIR}/" 2>/dev/null || true

# 3. Install Shim
echo ":: Linking Shim..."
if [[ -f "${SOURCE_DIR}/quadctl_shim" ]]; then
    cp "${SOURCE_DIR}/quadctl_shim" "${BIN_DIR}/quadctl"
    chmod +x "${BIN_DIR}/quadctl"
else
    echo "!! [FATAL] quadctl_shim not found."
    exit 1
fi

echo ":: [SUCCESS] Quadctl installed."
echo "   Binary: ${BIN_DIR}/quadctl"
echo "   Data:   ${INSTALL_DIR}"