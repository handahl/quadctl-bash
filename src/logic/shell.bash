#!/usr/bin/env bash
# Logic: Interactive Shell (REPL)
# Author: SAC-CP (v2.1)
# Description: Provides an interactive command loop for quadctl.

# Source dependencies required for the shell
# We assume core/env.bash and core/deps.bash are already loaded by the shim.
source "${QUADCTL_HOME}/src/logic/matrix.bash"
source "${QUADCTL_HOME}/src/logic/tree.bash"
source "${QUADCTL_HOME}/src/logic/audit.bash"
source "${QUADCTL_HOME}/src/logic/doctor.bash"
source "${QUADCTL_HOME}/src/logic/logs.bash"
source "${QUADCTL_HOME}/src/logic/control.bash"
source "${QUADCTL_HOME}/src/api/systemd.bash"

execute_shell() {
    local initial_arg="${1:-}"

    echo_info "Entering Quadctl Interactive Shell..."
    
    # 1. Initial View (Configurable via arguments)
    if [[ "$initial_arg" =~ ^(a|all)$ ]]; then
        execute_matrix "all"
    else
        execute_matrix
    fi

    # 2. UX: Commands Hint Block
    echo -e "\n\033[1mcommands:\033[0m \033[1ma\033[0mll services | \033[1mdr\033[0m daemon-reload | \033[1mdry\033[0m-run | \033[1maudit\033[0m | \033[1mdoc\033[0mtor | \033[1mq\033[0muit"

    # 3. Main REPL Loop
    local cmd args
    while true; do
        # Signal Handling: Trap SIGINT (Ctrl+C) to prevent killing the shell itself.
        # We print a newline and reset the prompt.
        trap 'echo -e "\n[Shell] Interrupted. Type output exit to quit."; continue' SIGINT

        # Read Input
        if ! read -r -e -p "quadctl> " cmd args; then
            echo # Newline on EOF (Ctrl+D)
            break
        fi

        # Reset trap to default for command execution (allows children to handle signals normally, 
        # or we wrap them specifically).
        trap - SIGINT

        # Dispatch
        case "$cmd" in
            # --- Observations ---
            matrix|m)
                execute_matrix "$args"
                ;;
            tree|t)
                execute_tree
                ;;
            status)
                # 's' is explicitly REMOVED as an alias to avoid conflict/confusion
                if [[ "$args" == "all" || "$args" == "a" ]]; then
                    execute_matrix "all"
                else
                    execute_matrix
                fi
                ;;
            
            # --- Inspection/Logs ---
            logs|l)
                # Signal Isolation: Run in subshell so Ctrl+C kills logs, not REPL
                (
                    trap 'exit 0' SIGINT
                    execute_logs "$args"
                )
                ;;
            
            # --- Governance ---
            audit)
                execute_audit
                ;;
            doctor|doc)
                execute_doctor
                ;;
            dry)
                 # Run the quadlet generator in dry-run mode
                 /usr/lib/systemd/system-generators/podman-system-generator --dryrun
                 ;;

            # --- Control ---
            start)   execute_control "start" "$args" ;;
            stop)    execute_control "stop" "$args" ;;
            restart) execute_control "restart" "$args" ;;
            enable)  execute_control "enable" "$args" ;;
            disable) execute_control "disable" "$args" ;;
            
            # --- System ---
            dr|daemon-reload)
                api_systemd_reload
                ;;
            
            # --- Meta ---
            help|h|?)
                # Inline help for shell
                echo "Shell Commands:"
                echo "  m, matrix [all]   : Show status matrix"
                echo "  t, tree           : Show dependency tree"
                echo "  l, logs <unit>    : View logs (Ctrl+C to exit logs)"
                echo "  audit             : Check configuration integrity"
                echo "  dr                : Daemon Reload"
                echo "  dry               : Quadlet Generator Dry Run"
                echo "  exit, quit, q     : Exit shell"
                ;;
            exit|quit|q)
                echo_info "Exiting Shell."
                break
                ;;
            "")
                # Empty enter key, just refresh prompt
                continue
                ;;
            *)
                echo_error "Unknown command: $cmd"
                echo "Type 'help' for available commands."
                ;;
        esac
    done
    
    # Clean exit
    trap - SIGINT
}