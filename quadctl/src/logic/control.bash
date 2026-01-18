#!/usr/bin/env bash
# ==============================================================================
# FILE: control.bash
# PATH: src/logic/control.bash
# PROJECT: quadctl
# VERSION: 11.6.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Unit management with Dependency Intelligence & Interactive Selection.
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
    
    # Try prefixed first as it's the architectural standard
    if systemctl --user list-unit-files "$prefixed" &>/dev/null; then
        echo "$prefixed"
        return
    fi
    # Fallback to bare name
    echo "$bare"
}

# ------------------------------------------------------------------------------
# select_unit_interactive
# ------------------------------------------------------------------------------
select_unit_interactive() {
    if ! command -v fzf &>/dev/null; then
        return 1
    fi

    local units
    units=$(systemctl --user list-units "${Q_ARCH_PREFIX}*" --no-legend --plain | awk '{print $1}')
    
    if [[ -z "$units" ]]; then
        log_warn "No units found."
        return 1
    fi

    echo "$units" | fzf --height=40% --layout=reverse --border --prompt="Select Unit > "
}

# ------------------------------------------------------------------------------
# analyze_start_failure
# Heuristic analysis when 'start' fails.
# ------------------------------------------------------------------------------
analyze_start_failure() {
    local unit="$1"
    echo ""
    log_warn "Analyzing failure for $unit..."

    # 1. Check Dependencies (Reverse)
    # What does this unit need that might be broken?
    echo ":: Checking dependencies..."
    local deps
    # List dependencies, filter for our prefix to reduce noise
    deps=$(systemctl --user list-dependencies "$unit" --plain --no-legend | grep "$Q_ARCH_PREFIX")
    
    if [[ -n "$deps" ]]; then
        echo "$deps" | while read -r dep; do
            # Check status of each dependency
            local dep_state
            dep_state=$(systemctl --user is-active "$dep" 2>/dev/null || echo "unknown")
            if [[ "$dep_state" != "active" ]]; then
                echo -e "   - ${Q_COLOR_RED}[FAILED]${Q_COLOR_RESET} $dep (State: $dep_state)"
            else
                echo -e "   - ${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}     $dep"
            fi
        done
    else
        echo "   (No explicit architecture dependencies found)"
    fi

    # 2. Check Journal (Recent)
    echo ""
    echo ":: Recent Logs (Last 10 lines):"
    journalctl --user -u "$unit" -n 10 --no-pager -o cat | sed 's/^/   | /'
}

# ------------------------------------------------------------------------------
# execute_control
# ------------------------------------------------------------------------------
execute_control() {
    local action="$1"
    local target="${2:-}"

    # 0. Handle Dependency Queries (New v11.6)
    if [[ "$action" == "depends-on" ]]; then
         local u=$(resolve_unit_name "$target")
         log_info "Units required by $u:"
         systemctl --user list-dependencies "$u" | grep "$Q_ARCH_PREFIX"
         return
    elif [[ "$action" == "depended-by" ]]; then
         local u=$(resolve_unit_name "$target")
         log_info "Units that require $u:"
         systemctl --user list-dependencies --reverse "$u" | grep "$Q_ARCH_PREFIX"
         return
    fi

    # 1. Handle Global Actions
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

    # 2. Resolve Target
    if [[ -z "$target" ]]; then
        if [[ -t 0 ]]; then
            target=$(select_unit_interactive)
            [[ -z "$target" ]] && return 1
        else
            log_err "Target required. Usage: quadctl $action <unit>"
            return 1
        fi
    fi

    local unit
    unit=$(resolve_unit_name "$target")

    # Safety Check for destructive commands
    if [[ "$action" == "mask" ]]; then
        log_warn "Masking unit $unit. This will prevent it from starting."
    fi

    # 3. Handle Actions
    case "$action" in
        logs|log|l)
            # Route to logs module if present, else journalctl
            if [[ -f "${INSTALL_ROOT}/src/logic/logs.bash" ]]; then
                source "${INSTALL_ROOT}/src/logic/logs.bash"
                execute_logs "$unit"
            else
                journalctl --user -u "$unit" -f -n 50 -o cat
            fi
            ;;
        status)
             systemctl --user status "$unit"
             ;;
        debug|dbg)
             if [[ -f "${INSTALL_ROOT}/src/logic/debug.bash" ]]; then
                source "${INSTALL_ROOT}/src/logic/debug.bash"
                execute_debug "$unit"
             else
                log_err "Debug module missing."
             fi
             ;;
        start)
            local start_ts=$(date +%s%N)
            log_info "Starting $unit..."
            
            # Show dependencies that are being activated (Informational)
            local implies
            implies=$(systemctl --user list-dependencies "$unit" --plain --no-legend | grep "$Q_ARCH_PREFIX" | grep -v "$unit")
            if [[ -n "$implies" ]]; then
                echo ":: Also activating dependencies:"
                echo "$implies" | sed 's/^/   + /'
            fi

            if systemctl --user start "$unit"; then
                 local end_ts=$(date +%s%N)
                 log_success "Started $unit ($(( (end_ts - start_ts) / 1000000 ))ms)."
            else
                 log_err "Failed to start $unit."
                 analyze_start_failure "$unit"
                 return 1
            fi
            ;;
        stop|restart|reload|enable|disable|mask|unmask)
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