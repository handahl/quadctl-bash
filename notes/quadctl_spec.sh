#!/usr/bin/env bash
#
# quadctl MVP - Epistemic Observer Tool
# Normative Version: 0.1.0 (Ref: Reichsarchivierungskommission)
#
# GOVERNANCE NOTE:
# Any reimplementation (Go/Python/etc) MUST preserve:
# - Stateless execution
# - No implicit actuation during read paths
# - Deterministic identity resolution (ambiguity = failure)
# - No image, secret, or network lifecycle control
#
# Constraints:
# - Intent: Filesystem (~/.config/containers/systemd)
# - Runtime: Podman Libpod API (Unix Socket)
# - Systemd: D-Bus (via systemctl show)
#

set -euo pipefail

# ---[ Configuration ]----------------------------------------------------------

QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
SERVICE_PREFIX="" # Optional: Falls ein globaler Präfix erzwungen wird
API_VERSION="v5.0.0"

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_RED='\033[31m'
C_BLUE='\033[34m'
C_GRAY='\033[90m'

# ---[ Internal Helpers ]-------------------------------------------------------

_die() { printf "${C_RED}ERR:${C_RESET} %s\n" "$1" >&2; exit 1; }

_find_socket() {
    local uid
    uid=$(id -u)
    local sock="${XDG_RUNTIME_DIR:-/run/user/$uid}/podman/podman.sock"
    [[ -S "$sock" ]] && echo "$sock"
}

_ensure_socket() {
    _find_socket || {
        systemctl --user start podman.socket >/dev/null 2>&1 || return 1
        _find_socket
    }
}

_api() {
    local method="${1:-GET}"
    local endpoint="$2"
    local socket
    socket=$(_find_socket) || _die "Podman socket not found. (Observation path: no actuation permitted)"

    curl --silent --unix-socket "$socket" \
         -X "$method" \
         "http://d/${API_VERSION}/libpod${endpoint}"
}

_get_unit_prop() {
    local unit="$1"
    local prop="$2"
    systemctl --user show "$unit" --property="$prop" --value 2>/dev/null || echo "unknown"
}

# ---[ Core Capabilities ]------------------------------------------------------

_reconcile() {
    # Assertion: No actuation during reconciliation
    _find_socket >/dev/null || _die "Podman socket unreachable. (Observation path: no actuation permitted)"

    # 1. Fetch Runtime State (The Truth from the Engine)
    local rt_containers rt_pods
    rt_containers=$(_api GET "/containers/json?all=true")
    rt_pods=$(_api GET "/pods/json")

    echo -e "${C_BOLD}NAME|TYPE|INTENT|SYSTEMD|RUNTIME|HEALTH${C_RESET}"
    echo -e "${C_GRAY}----|----|------|-------|-------|------${C_RESET}"

    # 2. Iterate over Intent (The Files)
    find "$QUADLET_DIR" -maxdepth 1 -type f \( -name "*.container" -o -name "*.pod" -o -name "*.network" \) 2>/dev/null | sort | while read -r file; do
        local filename=$(basename "$file")
        local stem="${filename%.*}"
        local ext="${filename##*.}"
        local unit="${stem}.service"
        
        # Intent Check
        local intent="${C_GREEN}FILE${C_RESET}"
        
        # Systemd Check (via DBus properties)
        local sys_active=$(_get_unit_prop "$unit" "ActiveState")
        local disp_sys="${sys_active}"
        [[ "$sys_active" == "active" ]] && disp_sys="${C_GREEN}${sys_active}${C_RESET}"
        [[ "$sys_active" == "failed" ]] && disp_sys="${C_RED}${sys_active}${C_RESET}"

        # Runtime Check (via API lookup)
        local rt_state="${C_GRAY}-${C_RESET}"
        local rt_health="${C_GRAY}-${C_RESET}"
        
        if [[ "$ext" == "container" ]]; then
            # Deterministic Identity Resolution (Ambiguity = Failure)
            local c_info
            set +e
            c_info=$(echo "$rt_containers" | jq -r --arg name "$stem" '
              [.[] | select(.Names[] == "/"+$name or .Names[] == $name)] |
              if length == 1
              then .[0] | "\(.State)|\(.Health // "none")"
              elif length == 0
              then empty
              else error("Ambiguous container identity for " + $name)
              end
            ' 2>/dev/null)
            local jq_status=$?
            set -e

            if [[ $jq_status -ne 0 ]]; then
                rt_state="${C_RED}ambiguous${C_RESET}"
            elif [[ -n "$c_info" ]]; then
                IFS='|' read -r c_state c_health <<< "$c_info"
                rt_state="$c_state"
                [[ "$c_state" == "running" ]] && rt_state="${C_GREEN}${c_state}${C_RESET}"
                rt_health="$c_health"
            else
                rt_state="${C_RED}missing${C_RESET}"
            fi
        elif [[ "$ext" == "pod" ]]; then
            local p_info
            p_info=$(echo "$rt_pods" | jq -r --arg name "$stem" '.[] | select(.Name == $name) | .Status')
            rt_state="${p_info:-"${C_RED}missing${C_RESET}"}"
        fi

        echo -e "$stem|$ext|$intent|$disp_sys|$rt_state|$rt_health"
    done | column -t -s '|'
}

_audit() {
    echo -e "${C_BOLD}Statische Intent-Analyse (ZT-03)${C_RESET}"
    find "$QUADLET_DIR" -maxdepth 1 -type f -name "*.container" 2>/dev/null | while read -r file; do
        local name=$(basename "$file")
        local issues=()
        
        # Regel: Hardcoding von Secrets verbieten
        grep -qiE "Environment=.*(PASS|SECRET|KEY|TOKEN)=" "$file" && issues+=("Potential hardcoded secret in Env")
        
        # Regel: Hardening flags empfehlen
        grep -q "ReadOnly=true" "$file" || issues+=("ReadOnly=true missing")
        
        if [[ ${#issues[@]} -gt 0 ]]; then
            echo -e "${C_RED}✖${C_RESET} $name:"
            for issue in "${issues[@]}"; do echo -e "  - $issue"; done
        else
            echo -e "${C_GREEN}✔${C_RESET} $name: Compliant"
        fi
    done
}

# ---[ Interface ]--------------------------------------------------------------

_usage() {
    cat <<EOF
quadctl MVP - Epistemic System Observer

USAGE:
  quadctl <command> [args]

COMMANDS:
  status, q     Reconciliation Matrix (Intent vs Runtime)
  audit         Static security audit of Quadlet files
  logs <svc>    Follow clean logs for a service
  reload        Trigger systemd daemon-reload (Actuation)
  start <svc>   Actuate: Start service
  stop <svc>    Actuate: Stop service

EOF
}

main() {
    [[ $# -eq 0 ]] && { _usage; exit 0; }
    local cmd="$1"; shift

    case "$cmd" in
        status|q) _reconcile ;;
        audit)    _audit ;;
        reload)   
            _ensure_socket >/dev/null || _die "Could not actuate podman.socket"
            systemctl --user daemon-reload 
            ;;
        start|stop|restart)
            [[ $# -eq 0 ]] && _die "Service name required."
            _ensure_socket >/dev/null || _die "Could not actuate podman.socket"
            systemctl --user "$cmd" "$1"
            ;;
        logs|l)
            [[ $# -eq 0 ]] && _die "Service name required."
            journalctl --user -u "$1" -f -o json | jq -r '.MESSAGE // empty'
            ;;
        *) _usage ;;
    esac
}

main "$@"