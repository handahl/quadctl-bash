#!/usr/bin/env bash
# Logic: Interaction Dispatcher
# Author: SAC-CP (v2.1)

interact_dispatch() {
    # Preflight check: Ensure environment is loaded
    if ! declare -f execute_matrix &> /dev/null; then
        echo "!! [FATAL] Environment Not Loaded. Bootloader failed." >&2
        exit 1
    fi

    local cmd="${1:-}"
    shift
    local args="$*"

    case "$cmd" in
        "")
            execute_matrix | sed '/^Hints:/d'
            echo "hint: use 'quadctl shell' for interactive mode"
            ;;
        matrix|m)
            execute_matrix "$args" | sed '/^Hints:/d'
            echo "hint: use 'quadctl shell' for interactive mode"
            ;;
        all|a)
            execute_matrix "all"
            ;;
        tree|t)     execute_tree ;;
        shell)      execute_shell "$args" ;;
        doctor|doc) execute_doctor ;;
        logs|l)     execute_logs "$args" ;;
        audit)      execute_audit ;;
        deploy)     execute_deploy "$args" ;;
        debug)      execute_debug "$args" ;;
        start)      execute_control "start" "$args" ;;
        stop)       execute_control "stop" "$args" ;;
        restart)    execute_control "restart" "$args" ;;
        enable)     execute_control "enable" "$args" ;;
        disable)    execute_control "disable" "$args" ;;
        dr|daemon-reload) api_systemd_reload ;;
        -h|--help|help)   ui_show_help ;;
        -v|--version)     echo "quadctl v${QUADCTL_VERSION:-2.1}" ;;
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