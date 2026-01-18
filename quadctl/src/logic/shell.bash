#!/usr/bin/env bash
# ==============================================================================
# FILE: shell.bash
# PATH: src/logic/shell.bash
# PROJECT: quadctl
# VERSION: 11.5.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Interactive REPL for Quadctl.
# ==============================================================================

source "${INSTALL_ROOT}/src/logic/matrix.bash"
source "${INSTALL_ROOT}/src/logic/control.bash"
source "${INSTALL_ROOT}/src/logic/doctor.bash"
source "${INSTALL_ROOT}/src/ui/help.bash"

execute_shell() {
    local initial_args="$*"
    
    log_info "Entering Quadctl Interactive Shell..."
    echo "Type 'help' for commands, 'exit' to quit."
    
    if [[ -n "$initial_args" ]]; then
        run_repl_cmd $initial_args
    else
        execute_matrix_view "standard"
    fi

    trap 'echo -e "\n${Q_COLOR_YELLOW}[Shell] Use exit/quit to leave.${Q_COLOR_RESET}";' SIGINT

    local history_file="${XDG_STATE_HOME:-$HOME/.local/state}/quadctl_history"
    touch "$history_file"

    while true; do
        local prompt="${Q_COLOR_BLUE}quadctl>${Q_COLOR_RESET} "
        read -e -p "$(echo -e "$prompt")" -r input || break
        
        [[ -z "$input" ]] && continue
        echo "$input" >> "$history_file"

        run_repl_cmd $input
    done
    
    trap - SIGINT
}

run_repl_cmd() {
    local input_str="$*"
    local cmd_arr
    IFS=' ' read -r -a cmd_arr <<< "$input_str"
    local cmd="${cmd_arr[0]:-}"
    local arg="${cmd_arr[1]:-}"

    case "$cmd" in
        exit|quit|q)
            if [[ "${#cmd_arr[@]}" -eq 1 ]]; then
                echo "Bye."
                exit 0
            fi
            execute_matrix_view "all"
            ;;
        help)
            show_help
            ;;
        status|qs|s)
            # BIFURCATION: 's' -> Matrix. 's foo' -> Systemctl Status.
            if [[ -z "$arg" ]]; then
                execute_matrix_view "standard"
            elif [[ "$arg" =~ ^(a|all)$ ]]; then
                execute_matrix_view "all"
            else
                execute_control "status" "$arg"
            fi
            ;;
        a|all)
            execute_matrix_view "all"
            ;;
        doctor)
            execute_doctor
            ;;
        deploy)
            source "${INSTALL_ROOT}/src/logic/deploy.bash"
            execute_deploy "$arg"
            ;;
        dry)
            source "${INSTALL_ROOT}/src/logic/deploy.bash"
            execute_deploy "dry-run"
            ;;
        dr)
            log_info "Reloading systemd..."
            systemctl --user daemon-reload
            log_success "Reloaded."
            ;;
        start|stop|restart|reload|logs|enable|disable|mask|unmask)
            execute_control "$cmd" "$arg"
            ;;
        cat|edit)
             source "${INSTALL_ROOT}/src/logic/interact.bash"
             if [[ "$cmd" == "cat" ]]; then execute_cat "${arg:-missing}" "${cmd_arr[2]:-}"; fi
             if [[ "$cmd" == "edit" ]]; then execute_edit "${arg:-missing}" "${cmd_arr[2]:-}"; fi
             ;;
        clear)
            clear
            ;;
        *)
            log_err "Unknown command: $cmd"
            ;;
    esac
}