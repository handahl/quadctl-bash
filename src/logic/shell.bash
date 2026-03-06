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
source "${INSTALL_ROOT}/src/logic/tree.bash"
source "${INSTALL_ROOT}/src/logic/audit.bash"
source "${INSTALL_ROOT}/src/ui/help.bash"

execute_shell() {
    local initial_args="$*"
    
    echo "Entering quadctl interactive shell..."
    log_info "Type 'help' for commands, 'exit' to quit."
    
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
                echo "quadctl out."
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
        matrix)
            execute_matrix_view "$arg"
            ;;
        tree)
            execute_tree_view
            ;;
        audit)
            execute_audit
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
            
            # Post-Reload Generator Validation
            local validation_failed="false"
            local config_dir="$HOME/.config/containers/systemd"
            
            if [[ -d "$config_dir" ]]; then
                local service_files
                service_files=$(find "$config_dir" -name "*.service" -type f 2>/dev/null)
                
                while IFS= read -r service_file; do
                    if [[ -n "$service_file" ]]; then
                        local service_filename=$(basename "$service_file")
                        local stem="${service_filename%.service}"
                        
                        # Check for corresponding container/pod/network/volume file
                        local container_file="$config_dir/${stem}.container"
                        local pod_file="$config_dir/${stem}.pod"
                        local network_file="$config_dir/${stem}.network"
                        local volume_file="$config_dir/${stem}.volume"
                        
                        local source_file=""
                        if [[ -f "$container_file" ]]; then
                            source_file="$container_file"
                        elif [[ -f "$pod_file" ]]; then
                            source_file="$pod_file"
                        elif [[ -f "$network_file" ]]; then
                            source_file="$network_file"
                        elif [[ -f "$volume_file" ]]; then
                            source_file="$volume_file"
                        fi
                        
                        if [[ -n "$source_file" ]]; then
                            # Compare mtimes to check if generator ran but rejected the file
                            local source_mtime=$(stat -c %Y "$source_file" 2>/dev/null || stat -f %m "$source_file" 2>/dev/null)
                            local service_mtime=$(stat -c %Y "$service_file" 2>/dev/null || stat -f %m "$service_file" 2>/dev/null)
                            
                            if [[ -n "$source_mtime" && -n "$service_mtime" && "$source_mtime" -gt "$service_mtime" ]]; then
                                log_err "[GEN_FAIL] Generator ran but rejected $source_file (source file is newer than service file). Check 'journalctl --user -xe' for Quadlet generator output."
                                validation_failed="true"
                            fi
                        fi
                    fi
                done <<< "$service_files"
            fi
            
            if [[ "$validation_failed" == "true" ]]; then
                return 1
            else
                log_success "Reloaded."
            fi
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