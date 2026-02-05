#!/usr/bin/env bash
# Logic: Main Interaction Dispatcher
# Author: SAC-CP (v2.1)

# [ARCHITECTURAL CLEANUP]
# We assume the Bootloader (core/loader.bash) has done the work.
# If not, we try to source it defensively.

if ! command -v execute_matrix &> /dev/null; then
    _CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Try finding loader relative to us
    if [[ -f "$(dirname "${_CURRENT_DIR}")/core/loader.bash" ]]; then
         source "$(dirname "${_CURRENT_DIR}")/core/loader.bash"
    elif [[ -f "$(dirname "${_CURRENT_DIR}")/src/core/loader.bash" ]]; then
         source "$(dirname "${_CURRENT_DIR}")/src/core/loader.bash"
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
        logs|l)
            execute_logs "$args"
            ;;
        debug)
            execute_debug "$args"
            ;;
        audit)
            execute_audit
            ;;
        migrate)
            execute_migrate
            ;;
        deploy)
            execute_deploy "$args"
            ;;
        start)   execute_control "start" "$args" ;;
        stop)    execute_control "stop" "$args" ;;
        restart) execute_control "restart" "$args" ;;
        enable)  execute_control "enable" "$args" ;;
        disable) execute_control "disable" "$args" ;;
        mask)    execute_control "mask" "$args" ;;
        unmask)  execute_control "unmask" "$args" ;;
        dr|daemon-reload)
            api_systemd_reload
            ;;
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