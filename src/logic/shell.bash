#!/usr/bin/env bash
# Logic: Interactive Shell
# Author: SAC-CP (v2.1)

# [ARCHITECTURAL NOTE]
# No sourcing. No path calculations.

execute_shell() {
    local initial_arg="${1:-}"
    
    echo_info "Entering Quadctl Interactive Shell..."

    if [[ "$initial_arg" =~ ^(a|all)$ ]]; then
        execute_matrix "all" | sed '/^Hints:/d'
    else
        execute_matrix | sed '/^Hints:/d'
    fi

    echo -e "commands: \033[1ms\033[0mtatus | \033[1ma\033[0mll services | \033[1mdr\033[0m daemon-reload | \033[1mdry\033[0m-run quadlet generator | audit | doctor | deploy"

    local cmd args
    while true; do
        trap 'echo -e "\n[Shell] Interrupted. Type exit to quit."; continue' SIGINT
        
        if ! read -r -e -p "quadctl> " cmd args; then
            echo; break
        fi
        
        trap - SIGINT

        case "$cmd" in
            matrix|m|s|status)
                if [[ "$args" =~ ^(a|all)$ ]]; then
                    execute_matrix "all" | sed '/^Hints:/d'
                else
                    execute_matrix | sed '/^Hints:/d'
                fi
                ;;
            tree|t) execute_tree ;;
            logs|l) ( trap 'exit 0' SIGINT; execute_logs "$args" ) ;;
            audit)  execute_audit ;;
            doctor|doc) execute_doctor ;;
            dry)    /usr/lib/systemd/system-generators/podman-system-generator --dryrun ;;
            deploy) execute_deploy "$args" ;;
            start)  execute_control "start" "$args" ;;
            stop)   execute_control "stop" "$args" ;;
            restart) execute_control "restart" "$args" ;;
            dr|daemon-reload) api_systemd_reload ;;
            exit|quit|q) echo_info "Exiting Shell."; break ;;
            help|h|?) 
                echo "Shell Commands: status, tree, logs, audit, deploy, doctor, exit" 
                ;;
            "") continue ;;
            *) echo_error "Unknown command: $cmd" ;;
        esac
    done
    trap - SIGINT
}