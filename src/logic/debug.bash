#!/usr/bin/env bash
##
### debug.bash - The "Debug Cycle": stop → disable restart → start → tail.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : systemd, journalctl
## ==============================================================================================
#

source "${INSTALL_ROOT}/src/logic/logs.bash"

# ------------------------------------------------------------------------------
# execute_debug
# Performs the "Stop -> Disable Restart -> Start -> Tail" cycle.
# ------------------------------------------------------------------------------
execute_debug() {
    local unit="$1"
    
    if [[ -z "$unit" ]]; then
        log_err "usage: debug <unit>"
        return 1
    fi

    local start_ts
    start_ts=$(date +%s%N)

    log_warn "entering DEBUG MODE for ${unit}..."
    
    # 1. Stop the unit to prevent restart loops while we config
    log_info "stopping unit..."
    systemctl --user stop "$unit"

    # 2. Disable Restart Logic (Runtime Only)
    # [ARCH NOTE] We use --runtime so this change is lost on reboot/reload.
    # This prevents the "forgotten debug config" technical debt.
    log_info "disabling automatic restarts (runtime)..."
    if ! systemctl --user set-property --runtime "$unit" Restart=no; then
        log_warn "could not set Restart=no. proceeding."
    fi

    # 3. Show recent errors (Context)
    echo ""
    log_info "recent critical errors < 1h:"
    echo "----------------------------------------------------------------"
    journalctl --user -u "$unit" -p 3 --since="1 hour ago" --no-pager -n 10 || echo "  (no recent errors)"
    echo "----------------------------------------------------------------"
    echo ""

    # 4. Start Cleanly
    log_info "starting unit manually..."
    if systemctl --user start "$unit"; then
        local end_ts dur
        end_ts=$(date +%s%N)
        dur=$(( (end_ts - start_ts) / 1000000 ))
        log_success "unit started in ${dur}ms."
    else
        log_err "unit failed to start. tailing logs."
    fi

    # 5. Transition to Logs
    log_info "transitioning to live logs."
    # We call the robust logger from logs.bash
    execute_logs "$unit" 25
}