#!/usr/bin/env bash
# Logic: Debug
# Author: SAC-CP (v2.1)

# [FIX] Replaced INSTALL_ROOT with QUADCTL_HOME

execute_debug() {
    local unit="$1"
    if [[ -z "$unit" ]]; then
        echo_error "Usage: quadctl debug <unit>"
        return 1
    fi

    echo_info "Starting Debug Cycle for $unit..."
    
    # 1. Stop
    echo_info "Stopping $unit..."
    systemctl --user stop "$unit"
    
    # 2. Inspect (Config)
    echo_info "Unit Configuration:"
    systemctl --user cat "$unit" | head -n 20
    echo "..."
    
    # 3. Start
    echo_info "Starting $unit..."
    systemctl --user start "$unit"
    
    # 4. Logs
    echo_info "Fetching immediate logs..."
    # Rely on logic/logs.bash function if available, or direct call
    if command -v execute_logs &> /dev/null; then
        execute_logs "$unit"
    else
        journalctl --user -u "$unit" -n 20 --no-pager
    fi
}