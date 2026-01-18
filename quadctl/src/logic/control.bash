#!/usr/bin/env bash
# ==============================================================================
# FILE: control.bash
# PATH: src/logic/control.bash
# PROJECT: quadctl
# VERSION: 10.6.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Unit lifecycle management with Interactive Selection (fzf).
# ==============================================================================

# ------------------------------------------------------------------------------
# resolve_unit_name
# ------------------------------------------------------------------------------
resolve_unit_name() {
    local input="$1"
    if [[ "$input" == *.* ]]; then
        echo "$input"
        return
    fi
    local prefixed="${Q_ARCH_PREFIX}${input}.service"
    local bare="${input}.service"
    if systemctl --user list-unit-files "$prefixed" &>/dev/null; then
        echo "$prefixed"
        return
    fi
    echo "$bare"
}

# ------------------------------------------------------------------------------
# select_unit_interactive
# Uses fzf to select a unit if available.
# ------------------------------------------------------------------------------
select_unit_interactive() {
    if ! command -v fzf &>/dev/null; then
        return 1
    fi

    # Fetch units matching our architectural prefix
    local units
    units=$(systemctl --user list-units "${Q_ARCH_PREFIX}*" --no-legend --plain | awk '{print $1}')
    
    if [[ -z "$units" ]]; then
        log_warn "No units found to select."
        return 1
    fi

    local selected
    selected=$(echo "$units" | fzf --height=40% --layout=reverse --border --prompt="Select Unit > ")
    
    echo "$selected"
}

# ------------------------------------------------------------------------------
# execute_control
# Router for all control actions.
# ------------------------------------------------------------------------------
execute_control() {
    local action="$1"
    local target="${2:-}"

    # 1. Handle Global Actions (No Target Required)
    case "$action" in
        rd|reload-daemon)
            local start_ts=$(date +%s%N)
            log_info "Reloading systemd user daemon..."
            api_systemd_reload
            
            local end_ts=$(date +%s%N)
            local dur=$(( (end_ts - start_ts) / 1000000 ))
            log_success "Daemon reloaded in ${dur}ms."
            return 0
            ;;
    esac

    # 2. Handle Targeted Actions (Target Required)
    if [[ -z "$target" ]]; then
        # Try interactive selection
        if [[ -t 0 ]]; then
            local selected
            selected=$(select_unit_interactive)
            if [[ -n "$selected" ]]; then
                target="$selected"
                log_info "Selected target: $target"
            else
                log_err "Target required. Usage: quadctl $action <unit>"
                return 1
            fi
        else
            log_err "Target required (Non-interactive). Usage: quadctl $action <unit>"
            return 1
        fi
    fi

    local unit
    unit=$(resolve_unit_name "$target")

    # Safety Check for destructive commands
    if [[ "$action" == "mask" ]]; then
        log_warn "Masking unit $unit. This will prevent it from starting."
    fi

    case "$action" in
        logs|log|l)
            source "${INSTALL_ROOT}/src/logic/logs.bash"
            execute_logs "$unit"
            ;;
        debug|dbg)
            source "${INSTALL_ROOT}/src/logic/debug.bash"
            execute_debug "$unit"
            ;;
        start|stop|restart|reload|enable|disable|mask|unmask)
            local start_ts=$(date +%s%N)
            log_info "Exec: systemctl --user $action $unit"
            
            if systemctl --user "$action" "$unit"; then
                local end_ts=$(date +%s%N)
                local dur=$(( (end_ts - start_ts) / 1000000 ))
                log_success "Operation '$action' on '$unit' succeeded (${dur}ms)."
            else
                log_err "Operation '$action' failed."
                return 1
            fi
            ;;
        *)
            log_err "Unsupported control action: $action"
            return 1
            ;;
    esac
}