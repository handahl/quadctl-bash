#!/usr/bin/env bash
# Logic: Interactive Shell (REPL)
# Author: SAC-CP (v2.1)
# Description: Provides an interactive command loop for quadctl.

# [ARCHITECTURAL CLEANUP]
# No sourcing. No path calculation. 
# We assume the Bootloader (core/load.bash) has done the work.

execute_shell() {
    local initial_arg="${1:-}"
    
    # Safety Check: Did the loader work?
    if ! command -v execute_matrix &> /dev/null; then
        echo "!! [FATAL] Shell loaded without dependencies. Bootloader failed."
        echo "   Debug: QUADCTL_HOME=${QUADCTL_HOME:-unset}"
        return 1
    fi

    echo_info "Entering Quadctl Interactive Shell..."

    # 1. Initial View
    if [[ "$initial_arg" =~ ^(a|all)$ ]]; then
        execute_matrix "all" | sed '/^Hints:/d'
    else
        execute_matrix | sed '/^Hints:/d'
    fi

    # 2. UX: Commands Hint Block
    echo -e "commands: \033[1ms\033[0mtatus | \033[1ma\033[0mll services | \033[1mdr\033[0m daemon-reload | \033[1mdry\033[0m-run quadlet generator | audit | doctor | deploy"

    # 3. Main REPL Loop
    local cmd args
    while true; do
        trap 'echo -e "\n[Shell] Interrupted. Type exit to quit."; continue' SIGINT

        if ! read -r -e -p "quadctl> " cmd args; then
            echo 
            break
        fi

        trap - SIGINT

        case "$cmd" in
            matrix|m|s|status)
                if [[ "$args" == "all" || "$args" == "a" ]]; then
                    execute_matrix "all" | sed '/^Hints:/d'
                else
                    execute_matrix | sed '/^Hints:/d'
                fi
                ;;
            tree|t)
                execute_tree
                ;;
            logs|l)
                (
                    trap 'exit 0' SIGINT
                    execute_logs "$args"
                )
                ;;
            audit)
                execute_audit
                ;;
            doctor|doc)
                execute_doctor
                ;;
            dry)
                 /usr/lib/systemd/system-generators/podman-system-generator --dryrun
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
            help|h|?)
                # Simplified shell help
                echo "Shell Commands:"
                echo "  s, matrix [a]     : Show status matrix"
                echo "  t, tree           : Show dependency tree"
                echo "  l, logs <unit>    : View logs"
                echo "  audit             : Check configuration integrity"
                echo "  dry               : Quadlet Generator Dry Run"
                echo "  deploy            : Deploy changes"
                echo "  dr                : Daemon Reload"
                echo "  exit, quit, q     : Exit shell"
                ;;
            exit|quit|q)
                echo_info "Exiting Shell."
                break
                ;;
            "")
                continue
                ;;
            *)
                echo_error "Unknown command: $cmd"
                ;;
        esac
    done
    trap - SIGINT
}