#!/usr/bin/env bash
# Installer: Quadctl
# Author: SAC-CP (v2.1)

set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/quadctl"
BIN_DIR="${HOME}/.local/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ":: [SAC-CP] Initializing Quadctl Deployment..."

# 1. Prepare Directory
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 2. Deploy Artifacts
echo ":: Deploying artifacts to $INSTALL_DIR..."
# Copy everything including src/ structure
cp -r "${SOURCE_DIR}/src" "${INSTALL_DIR}/"
cp "${SOURCE_DIR}/ai.restraints.master.md" "${INSTALL_DIR}/" 2>/dev/null || true
cp "${SOURCE_DIR}/README.md" "${INSTALL_DIR}/" 2>/dev/null || true

# 3. Install Shim
echo ":: Installing Shim..."
if [[ -f "${SOURCE_DIR}/quadctl_shim" ]]; then
    cp "${SOURCE_DIR}/quadctl_shim" "${BIN_DIR}/quadctl"
    chmod +x "${BIN_DIR}/quadctl"
else
    echo "!! [FATAL] quadctl_shim not found in source directory."
    exit 1
fi

echo ":: [SUCCESS] Quadctl installed to ${BIN_DIR}/quadctl"