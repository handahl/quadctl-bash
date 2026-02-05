#!/usr/bin/env bash
# Installer: Quadctl
# Author: SAC-CP (v2.1)

set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/quadctl"
BIN_DIR="${HOME}/.local/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ":: [SAC-CP] Initializing Quadctl Deployment..."

# 0. CRITICAL SAFETY CHECK
if [[ "$SOURCE_DIR" == "$INSTALL_DIR" ]]; then
    echo "!! [FATAL] Deployment Error"
    echo "   You are running install.sh from inside the target directory: $INSTALL_DIR"
    exit 1
fi

# 1. Clean & Prepare Target
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 2. Deploy Artifacts
echo ":: Deploying artifacts..."
if [[ -d "${SOURCE_DIR}/src" ]]; then
    cp -r "${SOURCE_DIR}/src" "${INSTALL_DIR}/"
else
    echo "!! [FATAL] 'src' directory missing in source."
    exit 1
fi
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