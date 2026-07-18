#!/usr/bin/env bash
##
### deps.bash - Runtime dependency verification with tiered version floors.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : systemctl, podman, loginctl
## ==============================================================================================
#
# Two-tier model per ai.restraints.md:
#   preferred: full feature set (Fedora Atomic / han3, han1)
#   compat:    minimum viable (Rocky 9 / han3-vps) — warn, do not fail

# ------------------------------------------------------------------------------
# vercomp
# Pure Bash version comparator.
# Returns 0 if $1 == $2, 1 if $1 > $2, 2 if $1 < $2.
# ------------------------------------------------------------------------------
vercomp() {
    if [[ "$1" == "$2" ]]; then return 0; fi
    local IFS=.
    local i ver1 ver2
    read -ra ver1 <<< "$1"
    read -ra ver2 <<< "$2"
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then ver2[i]=0; fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then return 1; fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then return 2; fi
    done
    return 0
}

# ------------------------------------------------------------------------------
# check_version_tiered
# Usage: check_version_tiered "ToolName" "CurrentVer" "MinimumVer" "PreferredVer"
# Returns: 0 = ok, 1 = below preferred (warn), 2 = below minimum (fail)
# ------------------------------------------------------------------------------
check_version_tiered() {
    local tool="$1"
    local current="$2"
    local minimum="$3"
    local preferred="$4"

    vercomp "$current" "$minimum" && local _r=$? || local _r=$?
    if [[ $_r -eq 2 ]]; then
        log_err "$tool $current is below minimum viable floor ($minimum). Cannot continue."
        return 2
    fi

    vercomp "$current" "$preferred" && local _r=$? || local _r=$?
    if [[ $_r -eq 2 ]]; then
        log_warn "$tool $current is below preferred version ($preferred). Running on compat tier."
        log_warn "  Full feature set available at $preferred+. Proceeding."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# check_version_constraint
# Legacy single-floor check. Used only for hard-required tools (jq, curl, etc.)
# Usage: check_version_constraint "ToolName" "CurrentVer" "RequiredVer"
# ------------------------------------------------------------------------------
check_version_constraint() {
    local tool="$1"
    local current="$2"
    local required="$3"

    vercomp "$current" "$required" && local _r=$? || local _r=$?
    if [[ $_r -eq 2 ]]; then
        log_err "$tool version mismatch."
        log_err "  Required: >= $required"
        log_err "  Found:       $current"
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
    fi

    # --------------------------------------------------------------------------
    # TIERED VERSION ENFORCEMENT  (ai.restraints.md)
    # Minimum = fail below, Preferred = warn below (compat tier)
    # --------------------------------------------------------------------------

    # 1. BASH
    # BASH_VERSION is an internal variable, e.g., "5.3.0(1)-release"
    local bash_v_clean=${BASH_VERSION%%[^0-9.]*}
    local bash_rc
    check_version_tiered "Bash" "$bash_v_clean" "5.0.0" "5.2.0"
    bash_rc=$?
    [[ $bash_rc -eq 2 ]] && exit 1

    # 2. SYSTEMD
    # Output: "systemd 258 (258.3-2.fc43)"
    local sysd_v
    sysd_v=$(systemctl --version | head -n1 | awk '{print $2}')
    local sysd_rc
    check_version_tiered "systemd" "$sysd_v" "252" "255"
    sysd_rc=$?
    [[ $sysd_rc -eq 2 ]] && exit 1

    # 3. PODMAN
    # Output: "podman version 5.7.1"
    local pod_v
    pod_v=$(podman --version | awk '{print $3}')
    local pod_rc
    check_version_tiered "Podman" "$pod_v" "4.4.0" "5.0.0"
    pod_rc=$?
    [[ $pod_rc -eq 2 ]] && exit 1
    return 0
}