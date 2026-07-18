#!/usr/bin/env bash
##
### tree.bash - Hierarchical view of Pods and their constituent containers.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : podman, jq
## ==============================================================================================
#

execute_tree_view() {
    if ! command -v jq &>/dev/null; then
        log_err "'tree' requires jq."
        return 1
    fi

    printf "%-30s %-12s %-20s %s\n" "RESOURCE" "STATE" "UPTIME" "PORTS"
    printf '%0.s─' {1..80}; echo

    local pods_json containers_json
    pods_json=$(podman pod ps --format json 2>/dev/null || echo "[]")
    containers_json=$(podman ps -a --format json 2>/dev/null || echo "[]")

    if [[ "$pods_json" == "[]" && "$containers_json" == "[]" ]]; then
        echo "No resources found."
        return 0
    fi

    # --- Pods and their members ---
    local pod_ids
    # Fix: `podman pod ps --format json` returns an array; select() must iterate with .[]
    pod_ids=$(echo "$pods_json" | jq -r '.[] | .Id' 2>/dev/null)

    if [[ -n "$pod_ids" ]]; then
        while IFS= read -r pod_id; do
            [[ -z "$pod_id" ]] && continue

            local pod_name pod_status
            pod_name=$(echo   "$pods_json" | jq -r --arg id "$pod_id" '.[] | select(.Id == $id) | .Name')
            pod_status=$(echo "$pods_json" | jq -r --arg id "$pod_id" '.[] | select(.Id == $id) | .Status')

            printf "📦 %-27s ${Q_COLOR_BOLD}%-12s${Q_COLOR_RESET} %-20s %s\n" \
                "$pod_name" "$pod_status" "-" "-"

            # Fix: containers_json is an array; select() must iterate with .[]
            local pod_containers
            pod_containers=$(echo "$containers_json" | \
                jq -r --arg pid "$pod_id" '.[] | select(.Pod == $pid) | .Id' 2>/dev/null)

            if [[ -n "$pod_containers" ]]; then
                while IFS= read -r cid; do
                    [[ -z "$cid" ]] && continue
                    _render_container_row "$cid" "$containers_json" "  ├─"
                done <<< "$pod_containers"
            fi

        done <<< "$pod_ids"
    fi

    # --- Standalone containers (not in any pod) ---
    local standalone_ids
    # Fix: same array iteration pattern
    standalone_ids=$(echo "$containers_json" | \
        jq -r '.[] | select(.Pod == "" or .Pod == null) | .Id' 2>/dev/null)

    if [[ -n "$standalone_ids" ]]; then
        [[ -n "$pod_ids" ]] && echo  # visual spacer after pod section
        while IFS= read -r cid; do
            [[ -z "$cid" ]] && continue
            _render_container_row "$cid" "$containers_json" "🐳"
        done <<< "$standalone_ids"
    fi
}

_render_container_row() {
    local cid="$1"
    local json="$2"
    local prefix="$3"

    local c_name c_state c_status ports_raw ports_display uptime_str state_color

    # Reason: .[] | select() pattern — same fix as above; json is always an array here
    c_name=$(echo   "$json" | jq -r --arg id "$cid" '.[] | select(.Id == $id) | (.Names[0] // .Name)')
    c_state=$(echo  "$json" | jq -r --arg id "$cid" '.[] | select(.Id == $id) | .State')
    c_status=$(echo "$json" | jq -r --arg id "$cid" '.[] | select(.Id == $id) | .Status')
    ports_raw=$(echo "$json" | jq -r --arg id "$cid" \
        '.[] | select(.Id == $id) | .Ports // empty' 2>/dev/null)

    ports_display="-"
    if [[ -n "$ports_raw" && "$ports_raw" != "null" ]]; then
        ports_display=$(echo "$ports_raw" | \
            jq -r 'map(select(.hostPort) | "\(.hostPort):\(.containerPort)") | join(", ")' \
            2>/dev/null || echo "-")
    fi

    # Extract relative uptime from status string ("Up 3 hours" → "3 hours")
    uptime_str="$c_status"
    if [[ "$c_status" =~ ^Up[[:space:]](.+)$ ]]; then
        uptime_str="${BASH_REMATCH[1]}"
    fi
    uptime_str="${uptime_str:0:20}"

    case "$c_state" in
        running) state_color="${Q_COLOR_GREEN}"  ;;
        exited)  state_color="${Q_COLOR_RED}"    ;;
        *)       state_color="${Q_COLOR_YELLOW}" ;;
    esac

    printf "%s %-26s ${state_color}%-12s${Q_COLOR_RESET} %-20s %s\n" \
        "$prefix" "$c_name" "$c_state" "$uptime_str" "$ports_display"
}
