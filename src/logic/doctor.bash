#!/usr/bin/env bash
##
### doctor.bash - System health diagnostics with prerequisite chain validation.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : systemd
## ==============================================================================================
#

set -euo pipefail

# ------------------------------------------------------------------------------
# check_systemd_linkage
# Verify user systemd instance is correctly linked to D-Bus session.
# Returns 0 if valid, 1 if broken.
# ------------------------------------------------------------------------------
check_systemd_linkage() {
    local dbus_addr="${XDG_RUNTIME_DIR}/bus"

    if [[ ! -S "$dbus_addr" ]]; then
        return 1
    fi

    # Verify systemctl can communicate via D-Bus
    if systemctl --user show systemd.unit -p UnitFileState &>/dev/null; then
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# check_generator_status
# Verify Podman Quadlet generator binary exists and is executable.
# Uses discover_quadlet_generator() — no hardcoded paths.
# Returns 0 if found, 1 if missing.
# ------------------------------------------------------------------------------
check_generator_status() {
    discover_quadlet_generator &>/dev/null
}

execute_doctor() {
    log_info "Running System Diagnostics..."

    # 1. SYSTEMD D-BUS LINKAGE
    # --------------------------------------------------------------------------
    echo -n ":: Systemd D-Bus Link...  "
    if check_systemd_linkage; then
        echo "${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}"
    else
        echo "${Q_COLOR_RED}[FAIL]${Q_COLOR_RESET} - Session bus not found at ${XDG_RUNTIME_DIR}/bus"
    fi

    # 2. QUADLET GENERATOR
    # --------------------------------------------------------------------------
    echo -n ":: Quadlet Generator...   "
    local gen_path
    if gen_path=$(discover_quadlet_generator 2>/dev/null); then
        echo "${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}   $gen_path"
    else
        echo "${Q_COLOR_RED}[FAIL]${Q_COLOR_RESET} - Generator not found. Install podman-quadlet or equivalent for this distribution."
    fi

    # 3. JOB QUEUE
    # --------------------------------------------------------------------------
    local jobs
    jobs=$(systemctl --user list-jobs 2>/dev/null | wc -l || echo "0")

    echo -n ":: Systemd Job Queue...   "
    if (( jobs > 5 )); then
        echo "${Q_COLOR_YELLOW}[BUSY]${Q_COLOR_RESET} ($jobs jobs pending)"
        systemctl --user list-jobs | head -n 3
    else
        echo "${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}"
    fi

    # 4. D-BUS LATENCY
    # --------------------------------------------------------------------------
    echo -n ":: D-Bus Latency...       "
    local start_ts
    start_ts=$(date +%s%N 2>/dev/null)

    if systemctl --user show systemd.unit -p UnitFileState &>/dev/null; then
        local end_ts
        end_ts=$(date +%s%N 2>/dev/null)
        local diff=$(( (end_ts - start_ts) / 1000000 ))

        if (( diff > 1000 )); then
            echo "${Q_COLOR_YELLOW}[SLOW]${Q_COLOR_RESET} ${diff}ms"
        else
            echo "${Q_COLOR_GREEN}[OK]${Q_COLOR_RESET}   ${diff}ms"
        fi
    else
        echo "${Q_COLOR_RED}[FAIL]${Q_COLOR_RESET}"
    fi

    # 5. FAILED UNITS
    # --------------------------------------------------------------------------
    echo ""
    echo ":: Failed Units:"
    systemctl --user list-units --state=failed --no-pager || echo "   (No failed units)"
}