#!/usr/bin/env bash
# ==============================================================================
# FILE: install.sh
# PATH: ./install.sh
# PROJECT: quadctl
# VERSION: 10.5.0
# DATE: 2026-01-17
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Rootless user-space deployment script.
# ==============================================================================

set -euo pipefail

# 1. CONSTANTS (XDG Compliance)
# ------------------------------------------------------------------------------
readonly XDG_BIN_HOME="${HOME}/.local/bin"
readonly XDG_DATA_HOME="${HOME}/.local/share"
readonly INSTALL_DIR="${XDG_DATA_HOME}/quadctl"
readonly BIN_LINK="${XDG_BIN_HOME}/quadctl"

# 2. PRE-FLIGHT CHECKS
# ------------------------------------------------------------------------------
echo ":: [SAC-CP] Initializing Quadctl v10.5 Deployment..."

for cmd in git rsync mkdir ln chmod; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "!! [CRITICAL] Missing dependency: $cmd"
        exit 1
    fi
done

# 3. DIRECTORY SCAFFOLDING
# ------------------------------------------------------------------------------
echo ":: Creating directory structure..."
mkdir -p "${INSTALL_DIR}/src/core"
mkdir -p "${INSTALL_DIR}/src/api"
mkdir -p "${INSTALL_DIR}/src/logic"
mkdir -p "${INSTALL_DIR}/src/ui"
mkdir -p "${XDG_BIN_HOME}"

# 4. DEPLOYMENT
# ------------------------------------------------------------------------------
echo ":: Deploying artifacts to ${INSTALL_DIR}..."

if [[ -d "./src" ]]; then
    # We use rsync to ensure all new files (including logs.bash/debug.bash) are transferred
    rsync -avh --delete ./src/ "${INSTALL_DIR}/src/"
    
    # Check if bin/quadctl exists before copying
    if [[ -f "./bin/quadctl" ]]; then
        rsync -avh ./bin/quadctl "${INSTALL_DIR}/quadctl_shim"
    else
        echo "!! [WARN] ./bin/quadctl not found. Creating shim..."
    fi
else
    echo "!! [WARN] Source directory './src' not found. Assuming manual placement."
fi

# 5. SHIM CREATION (If missing)
# ------------------------------------------------------------------------------
# If the user doesn't have a binary shim yet, we create a robust one that
# sets up the environment and sources the entry point.
if [[ ! -f "${INSTALL_DIR}/quadctl_shim" ]] || [[ ! -f "./bin/quadctl" ]]; then
    echo ":: Generating Shim..."
    cat <<EOF > "${INSTALL_DIR}/quadctl_shim"
#!/usr/bin/env bash
export INSTALL_ROOT="${INSTALL_DIR}"

# Source Core
source "\${INSTALL_ROOT}/src/core/env.bash"
source "\${INSTALL_ROOT}/src/core/deps.bash"

# Check Deps
check_runtime_dependencies

# Route Command
# (Simple routing for shim - ideally this is in a src/main.bash, but inline for now)
# Load Logic
source "\${INSTALL_ROOT}/src/logic/matrix.bash"
source "\${INSTALL_ROOT}/src/logic/control.bash"
source "\${INSTALL_ROOT}/src/logic/deploy.bash"
source "\${INSTALL_ROOT}/src/logic/doctor.bash"
source "\${INSTALL_ROOT}/src/logic/shell.bash"
source "\${INSTALL_ROOT}/src/ui/help.bash"

if [[ \$# -eq 0 ]]; then
    execute_matrix_view
    exit 0
fi

case "\$1" in
    status|matrix) execute_matrix_view ;;
    deploy)       execute_deploy "\${2:-}" ;;
    doctor)       execute_doctor ;;
    shell)        execute_shell ;;
    help|--help|-h) show_help ;;
    version|--version|-v) show_version ;;
    *)            execute_control "\$1" "\${2:-}" ;;
esac
EOF
fi

# 6. LINKING
# ------------------------------------------------------------------------------
echo ":: Linking executable..."
chmod +x "${INSTALL_DIR}/quadctl_shim"
ln -sf "${INSTALL_DIR}/quadctl_shim" "${BIN_LINK}"

echo ":: [SUCCESS] Quadctl installed to ${BIN_LINK}"
echo ":: Ensure ${XDG_BIN_HOME} is in your \$PATH."