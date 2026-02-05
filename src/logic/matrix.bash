#!/usr/bin/env bash
# Logic: Matrix
# Author: SAC-CP (v2.1)

# [ARCHITECTURAL NOTE]
# No 'source' commands here. Handled by loader.bash.
# Use QUADCTL_HOME, not INSTALL_ROOT.

execute_matrix() {
    local filter="${1:-}"
    
    echo_info "Generating Quadlet Matrix..."
    printf "%-30s %-8s %-10s %-10s %-10s %-10s %-10s %s\n" "UNIT" "DRIFT" "STATE" "SUB" "UPTIME" "HEALTH" "VER" "ROUTING"
    echo "----------------------------------------------------------------------------------------------------------------"

    local unit_pattern="${QUADCTL_ARCH_PREFIX}*.service"
    local units
    units=$(systemctl --user list-unit-files "$unit_pattern" --no-legend | awk '{print $1}')
    
    if [[ -z "$units" ]]; then
        echo "No units found matching prefix: $QUADCTL_ARCH_PREFIX"
        return 0
    fi

    while IFS= read -r unit; do
        local simple_name="${unit%.service}"
        # simple_name="${simple_name#$QUADCTL_ARCH_PREFIX}" # Optional: Strip prefix
        
        local active_state sub_state load_state
        read -r active_state sub_state load_state <<< "$(systemctl --user show -p ActiveState,SubState,LoadState "$unit" | cut -d= -f2 | tr '\n' ' ')"
        
        local drift="syncy"
        local uptime="-"
        if [[ "$active_state" == "active" ]]; then uptime="up"; fi
        
        printf "%-30s %-8s %-10s %-10s %-10s %-10s %-10s %s\n" \
            "${simple_name}" "$drift" "$active_state" "$sub_state" "$uptime" "-" "-" "-"
            
    done <<< "$units"
}