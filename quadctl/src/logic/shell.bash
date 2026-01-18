#!/usr/bin/env bash
# ==============================================================================
# FILE: shell.bash
# PATH: src/logic/shell.bash
# PROJECT: quadctl
# VERSION: 10.1.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Interactive REPL for Quadctl.
# ==============================================================================

# Source dependencies if not already loaded
source "${INSTALL_ROOT}/src/logic/matrix.bash"
source "${INSTALL_ROOT}/src/logic/control.bash"
source "${INSTALL_ROOT}/src/logic/doctor.bash"
source "${INSTALL_ROOT}/src/ui/help.bash"

execute_shell() {
    log_info "Entering Quadctl Interactive Shell..."
    echo "Type 'help' for commands, 'exit' to quit."
    
    # Show status on entry
    execute_matrix_view

    # Trap SIGINT (Ctrl+C) to prevent accidental exit of the shell
    trap 'echo -e "\n${Q_COLOR_YELLOW}[Shell] Use exit/quit to leave.${Q_COLOR_RESET}";' SIGINT

    local history_file="${XDG_STATE_HOME:-$HOME/.local/state}/quadctl_history"
    touch "$history_file"

    while true; do
        # Use readline (-e) if available for better UX
        local prompt="${Q_COLOR_BLUE}quadctl>${Q_COLOR_RESET} "
        read -e -p "$(echo -e "$prompt")" -r input || break
        
        [[ -z "$input" ]] && continue
        
        # Simple history appending
        echo "$input" >> "$history_file"

        # Tokenize input
        local cmd_arr
        IFS=' ' read -r -a cmd_arr <<< "$input"
        local cmd="${cmd_arr[0]:-}"
        local arg="${cmd_arr[1]:-}"

        case "$cmd" in
            exit|quit|q)
                echo "Bye."
                break
                ;;
            help)
                show_help
                ;;
            status|matrix)
                execute_matrix_view
                ;;
            doctor)
                execute_doctor
                ;;
            deploy)
                # We do not allow 'deploy force' easily in shell without confirmation
                # for now, we just pass args
                source "${INSTALL_ROOT}/src/logic/deploy.bash"
                execute_deploy "$arg"
                ;;
            start|stop|restart|reload|logs|enable|disable|mask|unmask)
                execute_control "$cmd" "$arg"
                ;;
            clear)
                clear
                ;;
            *)
                log_err "Unknown command: $cmd"
                ;;
        esac
    done
    
    trap - SIGINT
}