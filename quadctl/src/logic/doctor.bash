#!/usr/bin/env bash
# ==============================================================================
# FILE: doctor.bash
# PATH: src/logic/doctor.bash
# PROJECT: quadctl
# VERSION: 10.0.0
# DATE: 2026-01-16
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: System health diagnostics.
# ==============================================================================

execute_doctor() {
    log_info "Running System Diagnostics..."

    # 1. JOB QUEUE
    # --------------------------------------------------------------------------
    local jobs
    jobs=$(systemctl --user list-jobs | wc -l)
    # wc -l counts header/footer sometimes, strictly speaking list-jobs returns lines.
    # We treat < 5 as nominal.
    
    echo -n ":: Systemd Job Queue... "
    if (( jobs > 5 )); then
        echo "${Q_COLOR_YELLOW}BUSY ($jobs jobs pending)${Q_COLOR_RESET}"
        systemctl --user list-jobs | head -n 3
    else
        echo "${Q_COLOR_GREEN}OK${Q_COLOR_RESET}"
    fi

    # 2. DBUS LATENCY
    # --------------------------------------------------------------------------
    echo -n ":: D-Bus Latency...     "
    local start_ts
    start_ts=$(date +%s%N 2>/dev/null) # Nanoseconds
    
    # Simple query to systemd
    if systemctl --user show systemd-dbus-daemon.service -p Id >/dev/null; then
        local end_ts
        end_ts=$(date +%s%N 2>/dev/null)
        local diff=$(( (end_ts - start_ts) / 1000000 )) # Milliseconds
        
        if (( diff > 1000 )); then
            echo "${Q_COLOR_YELLOW}${diff}ms (Slow)${Q_COLOR_RESET}"
        else
            echo "${Q_COLOR_GREEN}${diff}ms${Q_COLOR_RESET}"
        fi
    else
        echo "${Q_COLOR_RED}FAILED${Q_COLOR_RESET}"
    fi

    # 3. FAILED UNITS
    # --------------------------------------------------------------------------
    echo ":: Failed Units:"
    systemctl --user list-units --state=failed --no-pager
}