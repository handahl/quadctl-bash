#!/usr/bin/env bash
# ==============================================================================
# FILE: debug.bash
# PATH: src/logic/debug.bash
# PROJECT: quadctl
# VERSION: 10.5.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: The "Debug Cycle" state machine.
# ==============================================================================

source "${INSTALL_ROOT}/src/logic/logs.bash"

# ------------------------------------------------------------------------------
# execute_debug
# Performs the "Stop -> Disable Restart -> Start -> Tail" cycle.
# ------------------------------------------------------------------------------
execute_debug() {
    local unit="$1"
    
    if [[ -z "$unit" ]]; then
        log_err "Usage: debug <unit>"
        return 1
    fi

    local start_ts=$(date +%s%N)

    log_warn "Entering DEBUG MODE for ${unit}..."
    
    # 1. Stop the unit to prevent restart loops while we config
    log_info "Stopping unit..."
    systemctl --user stop "$unit"

    # 2. Disable Restart Logic (Runtime Only)
    # [ARCH NOTE] We use --runtime so this change is lost on reboot/reload.
    # This prevents the "forgotten debug config" technical debt.
    log_info "Disabling automatic restarts (Runtime)..."
    if ! systemctl --user set-property --runtime "$unit" Restart=no; then
        log_warn "Could not set Restart=no. Proceeding anyway."
    fi

    # 3. Show recent errors (Context)
    echo ""
    log_info "Recent Critical Errors (Last 1h):"
    echo "----------------------------------------------------------------"
    journalctl --user -u "$unit" -p 3 --since="1 hour ago" --no-pager -n 10 || echo "  (no recent errors)"
    echo "----------------------------------------------------------------"
    echo ""

    # 4. Start Cleanly
    log_info "Starting unit manually..."
    if systemctl --user start "$unit"; then
        local end_ts=$(date +%s%N)
        local dur=$(( (end_ts - start_ts) / 1000000 ))
        log_success "Unit started in ${dur}ms."
    else
        log_err "Unit failed to start. Tailing logs immediately..."
    fi

    # 5. Transition to Logs
    log_info "Transitioning to live logs..."
    # We call the robust logger from logs.bash
    execute_logs "$unit" 25
}