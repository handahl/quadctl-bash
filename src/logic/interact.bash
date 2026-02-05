#!/usr/bin/env bash
# Logic: Main Interaction Dispatcher
# Author: SAC-CP (v2.1)
# Description: Routes CLI arguments to specific logic modules.

# [Architectural Correction]
# Dynamic Path Resolution for Sourcing
# (Replicated from shell.bash for consistency)

if [[ -z "${QUADCTL_HOME:-}" ]]; then
    _CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$(dirname "$(dirname "${_CURRENT_DIR}")")/src/logic/interact.bash" ]]; then
        QUADCTL_HOME="$(dirname "$(dirname "${_CURRENT_DIR}")")"
        _SRC_PREFIX="/src"
    elif [[ -f "$(dirname "${_CURRENT_DIR}")/logic/interact.bash" ]]; then
        QUADCTL_HOME="$(dirname "${_CURRENT_DIR}")"
        _SRC_PREFIX=""
    else
        QUADCTL_HOME="${HOME}/.local/share/quadctl"
        if [[ -d "${QUADCTL_HOME}/src" ]]; then _SRC_PREFIX="/src"; else _SRC_PREFIX=""; fi
    fi
else
    # QUADCTL_HOME provided by shim
    if [[ -d "${QUADCTL_HOME}/src/logic" ]]; then
        _SRC_PREFIX="/src"
    else
        _SRC_PREFIX=""
    fi
fi

# Source Logic Modules with correct prefix
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/matrix.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/tree.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/shell.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/logs.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/control.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/audit.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/deploy.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/migrate.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/doctor.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/debug.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/ui/help.bash"

interact_dispatch() {
    local cmd="${1:-}"
    shift
    local args="$*"

    case "$cmd" in
        # Default behavior (no command)
        "")
            execute_matrix | sed '/^Hints:/d'
            echo "hint: use 'quadctl shell' for interactive mode"
            ;;
        
        # --- Observation ---
        matrix|m)
            execute_matrix "$args" | sed '/^Hints:/d'
            echo "hint: use 'quadctl shell' for interactive mode"
            ;;
        
        # FIX: Added 'all' / 'a' handler
        all|a)
            execute_matrix "all" | sed '/^Hints:/d'
            echo "hint: use 'quadctl shell' for interactive mode"
            ;;

        tree|t)
            execute_tree
            ;;
        shell)
            execute_shell "$args"
            ;;
        doctor|doc)
            execute_doctor
            ;;
        
        # --- Logs & Debug ---
        logs|l)
            execute_logs "$args"
            ;;
        debug)
            execute_debug "$args"
            ;;
            
        # --- Governance ---
        audit)
            execute_audit
            ;;
        migrate)
            execute_migrate
            ;;
        deploy)
            execute_deploy "$args"
            ;;
            
        # --- Units Control ---
        start)   execute_control "start" "$args" ;;
        stop)    execute_control "stop" "$args" ;;
        restart) execute_control "restart" "$args" ;;
        enable)  execute_control "enable" "$args" ;;
        disable) execute_control "disable" "$args" ;;
        mask)    execute_control "mask" "$args" ;;
        unmask)  execute_control "unmask" "$args" ;;
        
        # --- Inspection ---
        cat)
            if [[ -z "$args" ]]; then
                # Fallback primitive if echo_error not loaded yet (unlikely here but safe)
                echo "Usage: quadctl cat <unit>" >&2
                exit 1
            fi
            systemctl --user cat "$args"
            ;;
        
        # --- System ---
        dr|daemon-reload)
            api_systemd_reload
            ;;
            
        # --- Help/Version ---
        -h|--help|help)
            ui_show_help
            ;;
        -v|--version)
            echo "quadctl v${QUADCTL_VERSION:-2.1}"
            ;;
            
        *)
            # Check if command is a valid unit to try implicit "status" or "logs"? 
            # No, strictly follow commands.
            if command -v echo_error &> /dev/null; then
                echo_error "Unknown command: $cmd"
            else
                echo "Unknown command: $cmd" >&2
            fi
            ui_show_help
            exit 1
            ;;
    esac
}