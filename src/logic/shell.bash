#!/usr/bin/env bash
# Logic: Interactive Shell (REPL)
# Author: SAC-CP (v2.1)
# Description: Provides an interactive command loop for quadctl.

# [Architectural Correction]
# Dynamic Path Resolution (Layout Agnostic)
# We must determine if we are in a 'src/' structure (Repo) or flat structure (Install).

if [[ -z "${QUADCTL_HOME:-}" ]]; then
    # Resolve absolute path of the directory containing this script
    _CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Heuristic 1: Development (Repo) -> .../src/logic -> Root is ../../
    if [[ -f "$(dirname "$(dirname "${_CURRENT_DIR}")")/src/logic/shell.bash" ]]; then
        QUADCTL_HOME="$(dirname "$(dirname "${_CURRENT_DIR}")")"
        _SRC_PREFIX="/src"
    
    # Heuristic 2: Production (Install) -> .../logic -> Root is ../
    elif [[ -f "$(dirname "${_CURRENT_DIR}")/logic/shell.bash" ]]; then
        QUADCTL_HOME="$(dirname "${_CURRENT_DIR}")"
        _SRC_PREFIX=""
        
    else
        # Fallback to standard install path
        QUADCTL_HOME="${HOME}/.local/share/quadctl"
        if [[ -d "${QUADCTL_HOME}/src" ]]; then _SRC_PREFIX="/src"; else _SRC_PREFIX=""; fi
    fi
else
    # QUADCTL_HOME provided by shim. Detect layout inside it.
    if [[ -d "${QUADCTL_HOME}/src/logic" ]]; then
        _SRC_PREFIX="/src"
    else
        _SRC_PREFIX=""
    fi
fi

# 1. Dependency Safety & Fallbacks
#    Try to load env.bash with correct prefix
if [[ -f "${QUADCTL_HOME}${_SRC_PREFIX}/core/env.bash" ]]; then
    source "${QUADCTL_HOME}${_SRC_PREFIX}/core/env.bash"
fi

# [RESILIENCE] Fallback Logging Primitives
if ! command -v echo_info &> /dev/null; then
    echo_info() { echo -e ":: [INFO] $*"; }
fi
if ! command -v echo_error &> /dev/null; then
    echo_error() { echo -e "!! [ERR]  $*"; } >&2
fi

# 2. Source Dependencies (Dynamic Paths)
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/matrix.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/tree.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/audit.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/doctor.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/logs.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/control.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/logic/deploy.bash"
source "${QUADCTL_HOME}${_SRC_PREFIX}/api/systemd.bash"

execute_shell() {
    local initial_arg="${1:-}"

    echo_info "Entering Quadctl Interactive Shell..."
    
    # 1. Initial View
    # Use sed to clean up hint noise from matrix
    if [[ "$initial_arg" =~ ^(a|all)$ ]]; then
        if command -v execute_matrix &> /dev/null; then
            execute_matrix "all" | sed '/^Hints:/d'
        else
            echo_error "Matrix logic not loaded."
        fi
    else
        if command -v execute_matrix &> /dev/null; then
            execute_matrix | sed '/^Hints:/d'
        else
            echo_error "Matrix logic not loaded."
        fi
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
            dr|daemon-reload)
                api_systemd_reload
                ;;
            help|h|?)
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