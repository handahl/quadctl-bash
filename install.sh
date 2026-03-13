#!/usr/bin/env bash
# ==============================================================================
# FILE: install.sh
# PATH: install.sh
# PROJECT: quadctl
# DESCRIPTION: Deploys quadctl to ~/.local/share/quadctl and symlinks the shim.
#
# The shim lives at src/quadctl_shim inside the install directory.
# ~/.local/bin/quadctl is a symlink to that path — NOT a copy.
# This allows the shim's BASH_SOURCE[0] symlink-resolution loop to find
# INSTALL_ROOT correctly: readlink resolves to the src/ path, dirname gives
# src/, and ../src check then resolves to the install root.
# ==============================================================================

set -euo pipefail

readonly INSTALL_DIR="${HOME}/.local/share/quadctl"
readonly BIN_DIR="${HOME}/.local/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR

echo ":: Initializing quadctl deployment..."

# Safety: refuse to install from inside the target directory
if [[ "$SOURCE_DIR" == "$INSTALL_DIR" ]]; then
    echo "[ERR] Running install.sh from inside the target directory: ${INSTALL_DIR}" >&2
    echo "      Clone the repo elsewhere and run from there." >&2
    exit 1
fi

# Validate source layout before touching anything
if [[ ! -d "${SOURCE_DIR}/src" ]]; then
    echo "[ERR] 'src' directory not found in ${SOURCE_DIR}" >&2
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/src/quadctl_shim" ]]; then
    echo "[ERR] src/quadctl_shim not found in ${SOURCE_DIR}" >&2
    exit 1
fi

# 1. Clean and prepare install directory
echo ":: Deploying artifacts to ${INSTALL_DIR}..."
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 2. Deploy src tree (all modules, no root-level shim copy)
cp -r "${SOURCE_DIR}/src" "${INSTALL_DIR}/"

# Copy docs if present (non-fatal)
cp "${SOURCE_DIR}/"*.md "${INSTALL_DIR}/" 2>/dev/null || true

# 3. Mark shim executable in-place
chmod +x "${INSTALL_DIR}/src/quadctl_shim"

# 4. Symlink — not copy — so BASH_SOURCE[0] resolution works correctly
echo ":: Linking shim: ${BIN_DIR}/quadctl → ${INSTALL_DIR}/src/quadctl_shim"
ln -sf "${INSTALL_DIR}/src/quadctl_shim" "${BIN_DIR}/quadctl"

echo ":: quadctl installed."
echo "   Run 'quadctl --help' to verify."
