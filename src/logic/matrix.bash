#!/usr/bin/env bash
# ==============================================================================
# FILE: matrix.bash
# PATH: src/logic/matrix.bash
# PROJECT: quadctl
# VERSION: 11.4.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: High-Density Reconciliation Matrix (Union of Disk & Runtime).
# ==============================================================================

source "${INSTALL_ROOT}/src/api/podman.bash"
source "${INSTALL_ROOT}/src/api/systemd.bash"

# Helper: Relative Time Calculation
calc_uptime() {
    local ts_str="$1"
    [[ -z "$ts_str" ]] && echo "-" && return

    local ts_epoch
    ts_epoch=$(date -d "$ts_str" +%s 2>/dev/null)
    [[ -z "$ts_epoch" ]] && echo "-" && return

    local now
    now=$(date +%s)
    local diff=$((now - ts_epoch))

    if (( diff < 60 )); then echo "${diff}s"
    elif (( diff < 3600 )); then echo "$((diff / 60))m"
    elif (( diff < 86400 )); then echo "$((diff / 3600))h"
    else echo "$((diff / 86400))d"
    fi
}

execute_matrix_view() {
    local filter_type="${1:-standard}" # Default to standard (active/failed only)
    
    # Map shortcuts
    if [[ "$filter_type" =~ ^(a|all)$ ]]; then filter_type="all"; fi

    log_info "Generating Quadlet Matrix (${filter_type^} View)..."

    # 1. FETCH DATA
    local sys_map pod_map
    sys_map=$(api_systemd_get_state_map)
    pod_map=$(get_containers_map)

    # 2. DISCOVER INTENT (Files on Disk)
    local disk_units=()
    if [[ -d "$Q_CONFIG_DIR" ]]; then
        while IFS= read -r file; do
            local filename=$(basename "$file")
            local stem="${filename%.container}"
            # Only track containers/networks/volumes managed by us
            if [[ "$filename" == "$Q_ARCH_PREFIX"* ]]; then
                 disk_units+=("${stem}.service")
            fi
        done < <(find "$Q_CONFIG_DIR" -maxdepth 1 -name "*.container" -o -name "*.network" -o -name "*.volume")
    fi

    # 3. MERGE LISTS (Union: Disk + Systemd)
    local runtime_keys
    runtime_keys=$(echo "$sys_map" | jq -r 'keys[]')
    
    local all_units
    all_units=$(printf "%s\n" "${disk_units[@]}" "$runtime_keys" | sort -u)

    if [[ -z "$all_units" ]]; then
        log_warn "No units found (neither on disk nor in systemd)."
        return
    fi

    # 4. HEADER
    printf "%-30s %-8s %-10s %-10s %-8s %-10s %-12s %s\n" \
        "UNIT" "DRIFT" "STATE" "SUB" "UPTIME" "HEALTH" "VER" "ROUTING"
    printf "%s\n" "----------------------------------------------------------------------------------------------------------------"

    # Buffers for sorting
    local lines_services=()
    local lines_networks=()

    # 5. ITERATE
    for unit in $all_units; do
        if [[ "$unit" != "${Q_ARCH_PREFIX}"* ]]; then continue; fi

        # --- DATA EXTRACTION ---
        local s_active s_sub s_drift s_ts
        if echo "$sys_map" | jq -e --arg k "$unit" 'has($k)' >/dev/null; then
            s_active=$(echo "$sys_map" | jq -r --arg k "$unit" '.[$k].active')
            s_sub=$(echo "$sys_map" | jq -r --arg k "$unit" '.[$k].sub')
            s_drift=$(echo "$sys_map" | jq -r --arg k "$unit" '.[$k].drift')
            s_ts=$(echo "$sys_map" | jq -r --arg k "$unit" '.[$k].ts')
        else
            s_active="missing"
            s_sub="-"
            s_drift="-"
            s_ts=""
        fi

        # Filter Logic (Standard View hides inactive/exited unless failed/restarting)
        if [[ "$filter_type" != "all" ]]; then
            # Show if active, OR if failed, OR if auto-restart
            if [[ "$s_active" == "inactive" && "$s_sub" != "failed" && "$s_sub" != "auto-restart" ]]; then
                continue
            fi
            if [[ "$s_active" == "missing" ]]; then continue; fi
        fi

        # Clean Names
        local clean_name="${unit#$Q_ARCH_PREFIX}"
        clean_name="${clean_name%.service}"
        local unit_stem="${unit%.service}"

        # Podman Props
        local pod_json
        pod_json=$(echo "$pod_map" | jq -r --arg n1 "$unit_stem" --arg n2 "$clean_name" '.[$n1] // .[$n2] // empty')

        local p_health="-"
        local p_image="-"
        local p_ports="-"

        if [[ -n "$pod_json" ]]; then
            local raw_status
            raw_status=$(echo "$pod_json" | jq -r '.Status // ""')
            
            if [[ "$raw_status" == *"(healthy)"* ]]; then p_health="healthy"
            elif [[ "$raw_status" == *"(unhealthy)"* ]]; then p_health="unhealthy"
            elif [[ "$raw_status" == *"(starting)"* ]]; then p_health="starting"
            else p_health="-"
            fi

            local raw_image
            raw_image=$(echo "$pod_json" | jq -r '.Image // ""')
            if [[ "$raw_image" == *":"* ]]; then
                p_image="${raw_image##*:}"
                p_image="${p_image:0:12}"
            else
                p_image="latest"
            fi

            local labels
            labels=$(echo "$pod_json" | jq -r '.Labels // {}')
            local rule
            rule=$(echo "$labels" | jq -r 'to_entries[] | select(.key | contains("routers")) | .value | capture("Host\\(`(?<host>[^`]+)`\\)") | .host' | head -n1)
            
            if [[ -n "$rule" ]]; then
                p_ports="● $rule"
            else
                local ports
                ports=$(echo "$pod_json" | jq -r '.Ports // [] | .[0] // empty | "\(.hostPort):\(.containerPort)"')
                if [[ -n "$ports" ]]; then p_ports="○ $ports"; fi
            fi
        else
            # Handling Networks/Volumes or Missing
            if [[ "$unit" == *"-network.service" ]]; then
                p_ports="Network"
            elif [[ "$s_active" == "missing" ]]; then
                p_health="standby"
            else
                p_health="missing"
            fi
        fi

        # --- FORMATTING & COLORS ---
        local uptime_str
        uptime_str=$(calc_uptime "$s_ts")

        # State Coloring
        local c_state="$Q_COLOR_RESET"
        if [[ "$s_active" == "active" ]]; then c_state="$Q_COLOR_GREEN"; fi
        if [[ "$s_active" == "failed" ]]; then c_state="$Q_COLOR_RED"; fi
        if [[ "$s_active" == "standby" ]]; then c_state="$Q_COLOR_GREY"; fi
        
        # Sub-State Handling (Auto-Restart Red)
        local display_sub="$s_sub"
        local line_color=""
        
        if [[ "$s_sub" == "auto-restart" ]]; then
            display_sub="loop"
            # Visual Requirement: The whole line should be red if auto-restarting
            line_color="$Q_COLOR_RED" 
            c_state="$Q_COLOR_RED" 
        elif [[ "$s_active" == "failed" ]]; then
            line_color="$Q_COLOR_RED"
        fi

        # Drift Coloring
        local c_drift="$Q_COLOR_RESET"
        local d_val="syncy"
        if [[ "$s_drift" == "yes" ]]; then 
            d_val="drifty"
            c_drift="$Q_COLOR_YELLOW"
        fi
        if [[ "$s_active" == "missing" ]]; then
            d_val="-"
            c_drift="$Q_COLOR_GREY"
        fi

        # Health Coloring
        local c_health="$Q_COLOR_RESET"
        if [[ "$p_health" == "healthy" ]]; then c_health="$Q_COLOR_GREEN"; fi
        if [[ "$p_health" == "unhealthy" ]]; then c_health="$Q_COLOR_RED"; fi
        if [[ "$p_health" == "missing" ]]; then c_health="$Q_COLOR_YELLOW"; fi
        if [[ "$p_health" == "unrealized" ]]; then c_health="$Q_COLOR_GREY"; fi

        # Construct Line
        local line_output=""
        
        # If line_color is set (critical state), override all colors
        if [[ -n "$line_color" ]]; then
            line_output=$(printf "%b%-30s %-8s %-10s %-10s %-8s %-10s %-12s %s%b" \
                "$line_color" "$clean_name" "$d_val" "$s_active" "$display_sub" "$uptime_str" "$p_health" "$p_image" "$p_ports" "$Q_COLOR_RESET")
        else
            line_output=$(printf "%-30s %b%-8s%b %b%-10s%b %-10s %-8s %b%-10s%b %-12s %s" \
                "$clean_name" \
                "$c_drift" "$d_val" "$Q_COLOR_RESET" \
                "$c_state" "$s_active" "$Q_COLOR_RESET" \
                "$display_sub" \
                "$uptime_str" \
                "$c_health" "$p_health" "$Q_COLOR_RESET" \
                "$p_image" \
                "$p_ports")
        fi

        # Sort into Buffers
        if [[ "$p_ports" == "Network" ]]; then
            lines_networks+=("$line_output")
        else
            lines_services+=("$line_output")
        fi
    done

    # 6. PRINT BUFFERED OUTPUT
    for l in "${lines_services[@]}"; do echo "$l"; done
    if [[ "$filter_type" == "all" ]]; then
        for l in "${lines_networks[@]}"; do echo "$l"; done
    fi

    # 7. HINTS FOOTER
    echo "----------------------------------------------------------------------------------------------------------------"
    echo -e "Hints: ${Q_COLOR_YELLOW}shell/s${Q_COLOR_RESET} shell | ${Q_COLOR_YELLOW}all/a${Q_COLOR_RESET} all services | ${Q_COLOR_YELLOW}dr${Q_COLOR_RESET} daemon-reload | ${Q_COLOR_YELLOW}dry${Q_COLOR_RESET} generator dry-run"
    echo ""
}