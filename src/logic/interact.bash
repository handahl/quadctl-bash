#!/usr/bin/env bash
# Logic: Main Interaction Dispatcher
# Author: SAC-CP (v2.1)
# Description: Routes CLI arguments to specific logic modules.

# [ARCHITECTURAL CLEANUP]
# We do NOT source logic files here. We assume the caller (shim) ran the loader.
# OR, we source the loader ourselves if we are the entry point (defensive).

if ! command -v execute_matrix &> /dev/null; then
    # If matrix isn't loaded, try to find and run the loader.
    _CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Try finding loader relative to us
    # If we are in logic/, loader is in ../core/load.bash
    if [[ -f "$(dirname "${_CURRENT_DIR}")/core/load.bash" ]]; then
         source "$(dirname "${_CURRENT_DIR}")/core/load.bash"
    elif [[ -f "$(dirname "${_CURRENT_DIR}")/src/core/load.bash" ]]; then
         # Deep dev structure mismatch fallback
         source "$(dirname "${_CURRENT_DIR}")/src/core/load.bash"
    fi
fi

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