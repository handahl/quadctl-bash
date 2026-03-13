#!/usr/bin/env bash
##
### control.bash - Unit lifecycle management with pre-flight validation.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : systemd, podman, fzf (optional — interactive selection only)
## ==============================================================================================
#
set -euo pipefail

# ------------------------------------------------------------------------------
# verify_unit_exists
# Strict existence check via systemctl LoadState.
# Returns 0 if unit is loaded, 1 otherwise.
# ------------------------------------------------------------------------------
verify_unit_exists() {
    local unit="$1"
    local load_state
    load_state=$(systemctl --user show "$unit" --property=LoadState --value 2>/dev/null \
        || echo "not-found")

    if [[ "$load_state" == "not-found" ]]; then
        log_err "unit '${unit}' not found."
        if [[ "$unit" != "${Q_ARCH_PREFIX}"* ]]; then
            log_err "  (did you mean '${Q_ARCH_PREFIX}${unit}'?)"
        fi
        return 1
    fi

    log_debug "verify_unit_exists: ${unit} LoadState=${load_state}"
    return 0
}

# ------------------------------------------------------------------------------
# check_dependencies
# Validates all prefixed dependencies of a unit exist before start/restart.
# ------------------------------------------------------------------------------
check_dependencies() {
    local unit="$1"
    local missing_deps=()

    local deps
    deps=$(systemctl --user list-dependencies "$unit" --plain --no-legend --no-pager \
        2>/dev/null | grep -E "\.service$" || true)

    [[ -z "$deps" ]] && return 0

    while IFS= read -r dep; do
        [[ "$dep" =~ ^${Q_ARCH_PREFIX} ]] || continue
        local state
        state=$(systemctl --user show "$dep" --property=LoadState --value 2>/dev/null \
            || echo "not-found")
        [[ "$state" == "not-found" ]] && missing_deps+=("$dep")
    done <<< "$deps"

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_err "missing dependencies for '${unit}':"
        for missing in "${missing_deps[@]}"; do
            printf "   - %s\n" "$missing" >&2
        done
        log_err "  run 'quadctl deploy' to synchronize."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# resolve_unit_name
# Resolves a short name (e.g. 'traefik') to a full unit name
# (e.g. 'hanlab-traefik.service'). Prefixed form is tried first.
# ------------------------------------------------------------------------------
resolve_unit_name() {
    local input="$1"

    # Already fully qualified (has an extension)
    if [[ "$input" == *.* ]]; then
        log_debug "resolve_unit_name: '${input}' already qualified"
        echo "$input"
        return
    fi

    local prefixed="${Q_ARCH_PREFIX}${input}.service"
    local bare="${input}.service"

    # Prefer prefixed — it is the architectural standard
    if systemctl --user list-unit-files "$prefixed" --no-legend &>/dev/null 2>&1; then
        log_debug "resolve_unit_name: '${input}' → '${prefixed}'"
        echo "$prefixed"
        return
    fi

    log_debug "resolve_unit_name: '${input}' → '${bare}' (prefix not found)"
    echo "$bare"
}

# ------------------------------------------------------------------------------
# select_unit_interactive
# Opens an fzf picker for units matching the architecture prefix.
# Returns the selected unit name, or empty string if cancelled.
# ------------------------------------------------------------------------------
select_unit_interactive() {
    if ! command -v fzf &>/dev/null; then
        log_err "fzf is required for interactive unit selection. Pass a unit name directly."
        return 1
    fi

    local units
    units=$(systemctl --user list-units "${Q_ARCH_PREFIX}*" --no-legend --plain \
        | awk '{print $1}')

    if [[ -z "$units" ]]; then
        log_warn "no active units found with prefix '${Q_ARCH_PREFIX}'."
        return 1
    fi

    echo "$units" | fzf \
        --height=40% --layout=reverse --border \
        --prompt="Select unit > " \
        --info=inline
}

# ------------------------------------------------------------------------------
# analyze_start_failure
# Heuristic post-mortem when a start/restart fails.
# Checks dependency states and tails recent journal entries.
# ------------------------------------------------------------------------------
analyze_start_failure() {
    local unit="$1"
    printf "\n" >&2
    log_warn "analyzing failure for ${unit}..."

    # Dependency state check
    printf "   checking dependencies...\n" >&2
    local deps
    deps=$(systemctl --user list-dependencies "$unit" --plain --no-legend 2>/dev/null \
        | grep "${Q_ARCH_PREFIX}" || true)

    if [[ -n "$deps" ]]; then
        while IFS= read -r dep; do
            local dep_state
            dep_state=$(systemctl --user is-active "$dep" 2>/dev/null || echo "unknown")
            if [[ "$dep_state" != "active" ]]; then
                printf "   %s✗%s %s  (state: %s)\n" \
                    "${Q_COLOR_RED}" "${Q_COLOR_RESET}" "$dep" "$dep_state" >&2
            else
                printf "   %s✓%s %s\n" "${Q_COLOR_GREEN}" "${Q_COLOR_RESET}" "$dep" >&2
            fi
        done <<< "$deps"
    else
        printf "   (no prefixed dependencies found)\n" >&2
    fi

    # Recent journal tail
    printf "\n   recent log entries:\n" >&2
    journalctl --user -u "$unit" -n 15 --no-pager \
        --output=short-precise -T podman 2>/dev/null \
        | sed 's/^/   | /' >&2
}

# ------------------------------------------------------------------------------
# execute_control
# Entry point for all unit lifecycle actions.
# $1: action  (start|stop|restart|reload|enable|disable|mask|unmask|
#              status|depends-on|depended-by)
# $2: target  (short name, full name, or empty for interactive selection)
# $3: follow  ("true"|"false") — tail logs after a state-changing command
# ------------------------------------------------------------------------------
execute_control() {
    local action="$1"
    local target="${2:-}"
    local follow="${3:-false}"

    log_debug "execute_control: action=${action} target=${target} follow=${follow}"

    # --- Dependency graph queries ---
    if [[ "$action" == "depends-on" || "$action" == "depended-by" ]]; then
        [[ -z "$target" ]] && { log_err "usage: quadctl ${action} <unit>"; return 1; }
        local u
        u=$(resolve_unit_name "$target")
        if [[ "$action" == "depends-on" ]]; then
            log_verbose "systemctl --user list-dependencies ${u}"
            systemctl --user list-dependencies "$u" | grep "${Q_ARCH_PREFIX}" || true
        else
            log_verbose "systemctl --user list-dependencies --reverse ${u}"
            systemctl --user list-dependencies --reverse "$u" | grep "${Q_ARCH_PREFIX}" || true
        fi
        return 0
    fi

    # --- Resolve target (interactive fallback if TTY) ---
    if [[ -z "$target" ]]; then
        if [[ -t 0 ]]; then
            target=$(select_unit_interactive) || return 1
            [[ -z "$target" ]] && return 1
        else
            log_err "target required. usage: quadctl ${action} <unit>"
            return 1
        fi
    fi

    local unit
    unit=$(resolve_unit_name "$target")

    # --- Dispatch by action ---
    case "$action" in

        status)
            log_verbose "systemctl --user status ${unit}"
            systemctl --user status "$unit"
            ;;

        start)
            verify_unit_exists "$unit" || return 1
            check_dependencies "$unit" || return 1

            if systemctl --user is-active --quiet "$unit"; then
                log_info "${unit} is already active."
                return 0
            fi

            # Capture cursor before start if follow requested
            local cursor=""
            if [[ "$follow" == "true" ]]; then
                source "${INSTALL_ROOT}/src/logic/logs.bash"
                cursor=$(capture_journal_cursor "$unit")
                log_debug "captured cursor before start: ${cursor:0:20}..."
            fi

            # Show co-activated dependencies at verbose level
            local implies
            implies=$(systemctl --user list-dependencies "$unit" --plain --no-legend \
                2>/dev/null | grep "${Q_ARCH_PREFIX}" | grep -v "$unit" || true)
            if [[ -n "$implies" ]]; then
                log_verbose "co-activating dependencies:"
                while IFS= read -r dep; do
                    log_verbose "  + ${dep}"
                done <<< "$implies"
            fi

            local ts_start
            ts_start=$(date +%s%N)
            log_info "starting ${unit}..."
            log_verbose "systemctl --user start ${unit}"

            if systemctl --user start "$unit"; then
                local dur=$(( ($(date +%s%N) - ts_start) / 1000000 ))
                log_success "started ${unit} (${dur}ms)."
                if [[ "$follow" == "true" ]]; then
                    source "${INSTALL_ROOT}/src/logic/logs.bash"
                    execute_logs_from_cursor "$unit" "$cursor"
                fi
            else
                log_err "failed to start ${unit}."
                analyze_start_failure "$unit"
                return 1
            fi
            ;;

        restart)
            verify_unit_exists "$unit" || return 1
            check_dependencies "$unit" || return 1

            # Capture cursor before restart if follow requested
            local cursor=""
            if [[ "$follow" == "true" ]]; then
                source "${INSTALL_ROOT}/src/logic/logs.bash"
                cursor=$(capture_journal_cursor "$unit")
                log_debug "captured cursor before restart: ${cursor:0:20}..."
            fi

            local ts_start
            ts_start=$(date +%s%N)
            log_info "restarting ${unit}..."
            log_verbose "systemctl --user restart ${unit}"

            if systemctl --user restart "$unit"; then
                local dur=$(( ($(date +%s%N) - ts_start) / 1000000 ))
                log_success "restarted ${unit} (${dur}ms)."
                if [[ "$follow" == "true" ]]; then
                    source "${INSTALL_ROOT}/src/logic/logs.bash"
                    execute_logs_from_cursor "$unit" "$cursor"
                fi
            else
                log_err "failed to restart ${unit}."
                analyze_start_failure "$unit"
                return 1
            fi
            ;;

        stop)
            local ts_start
            ts_start=$(date +%s%N)
            log_info "stopping ${unit}..."
            log_verbose "systemctl --user stop ${unit}"
            if systemctl --user stop "$unit"; then
                local dur=$(( ($(date +%s%N) - ts_start) / 1000000 ))
                log_success "stopped ${unit} (${dur}ms)."
            else
                log_err "failed to stop ${unit}."
                return 1
            fi
            ;;

        reload)
            log_info "reloading ${unit}..."
            log_verbose "systemctl --user reload ${unit}"
            if systemctl --user reload "$unit"; then
                log_success "reloaded ${unit}."
            else
                log_err "reload failed for ${unit}. Unit may not support reload."
                log_err "  try: quadctl restart ${target}"
                return 1
            fi
            ;;

        enable)
            log_verbose "systemctl --user enable ${unit}"
            systemctl --user enable "$unit" && log_success "enabled ${unit}."
            ;;

        disable)
            log_verbose "systemctl --user disable ${unit}"
            systemctl --user disable "$unit" && log_success "disabled ${unit}."
            ;;

        mask)
            log_warn "masking ${unit} — it cannot be started until unmasked."
            log_verbose "systemctl --user mask ${unit}"
            systemctl --user mask "$unit" && log_success "masked ${unit}."
            ;;

        unmask)
            log_verbose "systemctl --user unmask ${unit}"
            systemctl --user unmask "$unit" && log_success "unmasked ${unit}."
            ;;

        *)
            log_err "unsupported action: ${action}"
            return 1
            ;;

    esac
}
