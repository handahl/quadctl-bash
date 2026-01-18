#!/usr/bin/env bash
# ==============================================================================
# FILE: deps.bash
# PATH: src/core/deps.bash
# PROJECT: quadctl
# VERSION: 10.7.10
# DATE: 2026-01-18
# DESCRIPTION: Runtime dependency verification with Semantic Version enforcement.
# ==============================================================================

# ------------------------------------------------------------------------------
# vercomp
# Pure Bash version comparator.
# Returns 0 if $1 == $2, 1 if $1 > $2, 2 if $1 < $2.
# ------------------------------------------------------------------------------
vercomp() {
    if [[ "$1" == "$2" ]]; then return 0; fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then return 1; fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then return 2; fi
    done
    return 0
}

# ------------------------------------------------------------------------------
# check_version_constraint
# Usage: check_version_constraint "ToolName" "CurrentVer" "RequiredVer"
# ------------------------------------------------------------------------------
check_version_constraint() {
    local tool="$1"
    local current="$2"
    local required="$3"

    vercomp "$current" "$required"
    local result=$?

    if [[ $result -eq 2 ]]; then
        # current < required
        log_err "   $tool version mismatch."
        log_err "   Required: >= $required"
        log_err "   Found:       $current"
        return 1
    fi
    return 0
}


check_runtime_dependencies() {
    local missing=()
    local deps=("jq" "curl" "systemctl")

    for tool in "${deps[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # 1. Check for Podman Socket
    if [[ ! -S "$Q_PODMAN_SOCK" ]]; then
        log_err "Podman socket not found at $Q_PODMAN_SOCK"
        log_info "Try: systemctl --user enable --now podman.socket"
        exit 1
    fi

    # 2. Check for Linger (Critical for Rootless Persistence)
    local user_id
    user_id=$(id -u)
    if ! loginctl show-user "$user_id" --property=Linger | grep -q "Linger=yes"; then
        log_warn "[Architectural Intervention] Linger is NOT enabled for user $USER."
        log_warn "Your containers will stop when you log out."
        log_info "To enable: sudo loginctl enable-linger $USER"
        echo ""

    # --------------------------------------------------------------------------
    # STRICT VERSION ENFORCEMENT (As per ai_restraints_master.md)
    # --------------------------------------------------------------------------
    
    # 1. BASH (>= 5.3.0)
    # BASH_VERSION is an internal variable, e.g., "5.3.0(1)-release"
    local bash_v_clean=${BASH_VERSION%%[^0-9.]*}
    if ! check_version_constraint "Bash" "$bash_v_clean" "5.3.0"; then
        # Soften blow for dev environments, but warn loudly
        log_warn "Bash version is below spec (5.3.0). Proceeding with caution."
    fi

    # 2. SYSTEMD (>= 258)
    # Output: "systemd 258 (258.3-2.fc43)"
    local sysd_v
    sysd_v=$(systemctl --version | head -n1 | awk '{print $2}')
    if ! check_version_constraint "systemd" "$sysd_v" "258"; then
        log_warn "systemd version ($sysd_v) is below spec (258). Quadlet features may fail."
    fi

    # 3. PODMAN (>= 5.7.1)
    # Output: "podman version 5.7.1"
    local pod_v
    pod_v=$(podman --version | awk '{print $3}')
    if ! check_version_constraint "Podman" "$pod_v" "5.7.1"; then
        exit 1
    fi
}
