#!/usr/bin/env bash
# ==============================================================================
# FILE: control.bash
# PATH: src/logic/control.bash
# PROJECT: quadctl
# VERSION: 11.7.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Unit management with Strict State Governance & Pre-Flight Validation.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# verify_unit_exists
# Strict existence check using systemctl load state.
# Returns 0 if unit exists, 1 otherwise (with error to stderr).
# ------------------------------------------------------------------------------
verify_unit_exists() {
    local unit="$1"

    # Query the LoadState property directly
    local load_state
    load_state=$(systemctl --user show "$unit" --property=LoadState --value 2>/dev/null || echo "not-found")

    if [[ "$load_state" == "not-found" ]] || [[ "$load_state" == "masked" && "$load_state" != "loaded" ]]; then
        log_err "Unit '$unit' does not exist or is not loaded." >&2
        if [[ "$unit" == "${Q_ARCH_PREFIX}"* ]]; then
            log_info "try: systemctl --user list-unit-files '${unit}*'" >&2
        else
            log_info "try: systemctl --user list-unit-files '${Q_ARCH_PREFIX}${unit}*'" >&2
        fi
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# check_dependencies
# Validates all required dependencies exist before starting a unit.
# Returns 0 if all dependencies exist, 1 if any are missing (with breakdown).
# ------------------------------------------------------------------------------
check_dependencies() {
    local unit="$1"
    local missing_deps=()

    # Parse dependencies (only direct requirements, not full tree)
    local deps
    deps=$(systemctl --user list-dependencies "$unit" --plain --no-legend --no-pager 2>/dev/null | grep -E "\.service$" || true)

    if [[ -z "$deps" ]]; then
        return 0
    fi

    # Verify each dependency exists
    while IFS= read -r dep; do
        # Skip special systemd targets that are always present
         if [[ ! "$dep" =~ ^${Q_ARCH_PREFIX} ]]; then
            continue
        fi

        local dep_load_state
        dep_load_state=$(systemctl --user show "$dep" --property=LoadState --value 2>/dev/null || echo "not-found")

        if [[ "$dep_load_state" == "not-found" ]]; then
            missing_deps+=("$dep")
        fi
    done <<< "$deps"

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_err "missing dependencies for '$unit':" >&2
        for missing in "${missing_deps[@]}"; do
            echo "   - $missing" >&2
        done
        log_info "run 'quadctl deploy' to synchronize state" >&2
        return 1
    fi

    return 0
}

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
        log_warn "no units found."
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
    log_warn "analyzing failure for $unit..."

    # 1. Check Dependencies (Reverse)
    # What does this unit need that might be broken?
    echo ":: checking dependencies..."
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
        echo "   (no explicit architecture dependencies found)"
    fi

    # 2. Check Journal (Recent)
    echo ""
    echo ":: recent logs (last 10 lines):"
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
            log_info "reloading systemd --user daemon..."
            api_systemd_reload
            local end_ts=$(date +%s%N)
            local dur=$(( (end_ts - start_ts) / 1000000 ))
            log_success "daemon reloaded in ${dur}ms."
            return 0
            ;;
    esac

    # 2. Resolve Target
    if [[ -z "$target" ]]; then
        if [[ -t 0 ]]; then
            target=$(select_unit_interactive)
            [[ -z "$target" ]] && return 1
        else
            log_err "target required. usage: quadctl $action <unit>"
            return 1
        fi
    fi

    local unit
    unit=$(resolve_unit_name "$target")

    # Safety Check for destructive commands
    if [[ "$action" == "mask" ]]; then
        log_warn "masking unit $unit to prevent it from starting."
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
        debug)
             if [[ -f "${INSTALL_ROOT}/src/logic/debug.bash" ]]; then
                source "${INSTALL_ROOT}/src/logic/debug.bash"
                execute_debug "$unit"
             else
                log_err "debug module missing."
             fi
             ;;
        start)
            # PRE-FLIGHT VALIDATION
            verify_unit_exists "$unit" || return 1
            check_dependencies "$unit" || return 1

            # IDEMPOTENCY CHECK
            if systemctl --user is-active --quiet "$unit"; then
                log_info "Unit '$unit' is already active, no action taken."
                return 0
            fi

            local start_ts=$(date +%s%N)
            log_info "starting $unit..."

            # Show dependencies that are being activated (Informational)
            local implies
            implies=$(systemctl --user list-dependencies "$unit" --plain --no-legend 2>/dev/null | grep "$Q_ARCH_PREFIX" | grep -v "$unit" || true)
            if [[ -n "$implies" ]]; then
                echo ":: also activating the following dependencies:"
                echo "$implies" | sed 's/^/   + /'
            fi

            if systemctl --user start "$unit"; then
                 local end_ts=$(date +%s%N)
                 log_success "started $unit ($(( (end_ts - start_ts) / 1000000 ))ms)."
            else
                 log_err "failed to start $unit."
                 analyze_start_failure "$unit"
                 return 1
            fi
            ;;
        restart)
            # PRE-FLIGHT VALIDATION (Same as start)
            verify_unit_exists "$unit" || return 1
            check_dependencies "$unit" || return 1

            local start_ts=$(date +%s%N)
            log_info "restarting $unit..."

            if systemctl --user restart "$unit"; then
                local end_ts=$(date +%s%N)
                local dur=$(( (end_ts - start_ts) / 1000000 ))
                log_success "restarted $unit (${dur}ms)."
            else
                log_err "failed to restart $unit."
                analyze_start_failure "$unit"
                return 1
            fi
            ;;
        stop|reload|enable|disable|mask|unmask)
            local start_ts=$(date +%s%N)
            log_info "executing 'systemctl --user $action $unit'"

            if systemctl --user "$action" "$unit"; then
                local end_ts=$(date +%s%N)
                local dur=$(( (end_ts - start_ts) / 1000000 ))
                log_success "action succeeded in ${dur}ms."
            else
                log_err "action failed."
                return 1
            fi
            ;;
        *)
            log_err "unsupported action: $action"
            return 1
            ;;
    esac
}