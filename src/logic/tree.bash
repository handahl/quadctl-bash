#!/usr/bin/env bash
# Logic: Tree View
# Author: SAC-CP (v2.1)
# Description: Renders a hierarchical view of Pods and Containers.

execute_tree() {
    echo_info "Generating Quadlet Tree..."
    
    # Header
    printf "%-30s %-12s %-20s %s\n" "RESOURCE" "STATE" "UPTIME" "PORTS"
    echo "--------------------------------------------------------------------------------"

    # Check for jq
    if ! command -v jq &> /dev/null; then
        echo_error "The 'tree' command requires 'jq' to parse hierarchy."
        return 1
    fi

    local pods_json
    pods_json=$(podman pod ps --format json)
    
    local containers_json
    containers_json=$(podman ps -a --format json)

    # If no pods/containers, plain exit
    if [[ "$pods_json" == "[]" && "$containers_json" == "[]" ]]; then
        echo "No resources found."
        return 0
    fi

    # --- Process Pods ---
    local pod_ids
    pod_ids=$(echo "$pods_json" | jq -r '.[]? | .Id')
    
    if [[ -n "$pod_ids" ]]; then
        while IFS= read -r pod_id; do
            local pod_name pod_status pod_obj
            
            pod_obj=$(echo "$pods_json" | jq -r --arg id "$pod_id" 'select(.Id == $id)')
            pod_name=$(echo "$pod_obj" | jq -r '.Name')
            pod_status=$(echo "$pod_obj" | jq -r '.Status')
            
            # Pod Output
            printf "📦 %-27s \033[1m%-12s\033[0m %-20s %s\n" "$pod_name" "$pod_status" "-" "-"

            # Find containers in this pod
            local pod_containers
            pod_containers=$(echo "$containers_json" | jq -r --arg pid "$pod_id" 'select(.Pod == $pid) | .Id')
            
            if [[ -n "$pod_containers" ]]; then
                while IFS= read -r cid; do
                    _render_container_row "$cid" "$containers_json" "  ├─"
                done <<< "$pod_containers"
            fi
            
        done <<< "$pod_ids"
    fi

    # --- Process Standalone Containers ---
    local standalone_ids
    standalone_ids=$(echo "$containers_json" | jq -r 'select(.Pod == "" or .Pod == null) | .Id')
    
    if [[ -n "$standalone_ids" ]]; then
        if [[ -n "$pod_ids" ]]; then echo; fi # Spacer
        while IFS= read -r cid; do
             _render_container_row "$cid" "$containers_json" "🐳"
        done <<< "$standalone_ids"
    fi
}

_render_container_row() {
    local cid="$1"
    local json="$2"
    local prefix="$3"
    
    local c_obj c_name c_state c_status c_ports
    c_obj=$(echo "$json" | jq -r --arg id "$cid" 'select(.Id == $id)')
    c_name=$(echo "$c_obj" | jq -r '.Names[0] // .Name')
    c_state=$(echo "$c_obj" | jq -r '.State')
    c_status=$(echo "$c_obj" | jq -r '.Status')
    
    # Parse Ports
    local ports_raw
    ports_raw=$(echo "$c_obj" | jq -r '.Ports // empty')
    local ports_display="-"
    if [[ -n "$ports_raw" && "$ports_raw" != "null" ]]; then
        ports_display=$(echo "$ports_raw" | jq -r 'map(select(.hostPort) | "\(.hostPort):\(.containerPort)") | join(", ")')
    fi
    
    # Calculate Uptime string
    local uptime_str="-"
    local uptime_re="Up ([^)]+)"
    
    if [[ "$c_status" =~ $uptime_re ]]; then
        uptime_str="${BASH_REMATCH[1]}"
    else
        uptime_str="$c_status"
    fi
    
    # Truncate
    uptime_str=$(echo "$uptime_str" | xargs)
    if [[ ${#uptime_str} -gt 20 ]]; then
        uptime_str="${uptime_str:0:17}..."
    fi

    # Colorize State
    local state_color=""
    case "$c_state" in
        running) state_color="\033[32m" ;; # Green
        exited)  state_color="\033[31m" ;; # Red
        *)       state_color="\033[33m" ;; # Yellow
    esac
    
    printf "%s %-26s ${state_color}%-12s\033[0m %-20s %s\n" "$prefix" "$c_name" "$c_state" "$uptime_str" "$ports_display"
}