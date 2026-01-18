#!/usr/bin/env bash
# ==============================================================================
# FILE: tree.bash
# PATH: src/logic/tree.bash
# PROJECT: quadctl
# VERSION: 10.6.5
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Hierarchical visualization of system state (Scoped).
# ==============================================================================

source "${INSTALL_ROOT}/src/api/podman.bash"

execute_tree_view() {
    log_info "Generating Topology Tree..."

    local raw_json
    # We need the raw list, not the map, to group efficiently with jq
    raw_json=$(query_podman_socket "/containers/json?all=true")

    if [[ -z "$raw_json" || "$raw_json" == "[]" ]]; then
        echo "No containers found."
        return
    fi

    # [ARCH-FIX] Filter by Q_ARCH_PREFIX
    # We only want to show containers that match our governance prefix.
    # We use jq 'select' to filter first, then group.
    
    echo "$raw_json" | jq -r --arg prefix "$Q_ARCH_PREFIX" '
        map(select(.Names[0] | sub("^/";"") | startswith($prefix))) |
        group_by(.PodName)[] | 
        { 
            pod: (.[0].PodName // "standalone"), 
            items: . 
        } | @base64' | \
    while read -r pod_group_b64; do
        
        # Decode the group
        local pod_group
        pod_group=$(echo "$pod_group_b64" | base64 -d)
        
        local pod_name
        pod_name=$(echo "$pod_group" | jq -r '.pod')
        
        # --- RENDER POD HEADER ---
        if [[ "$pod_name" == "standalone" || -z "$pod_name" ]]; then
            echo -e "\n${Q_COLOR_BLUE}[Standalone Containers]${Q_COLOR_RESET}"
        else
            # Strip prefix for display cleanliness if it exists
            local display_name="${pod_name#$Q_ARCH_PREFIX}"
            echo -e "\n${Q_COLOR_PURP}[POD] ${display_name}${Q_COLOR_RESET}"
        fi

        # --- RENDER CONTAINERS ---
        echo "$pod_group" | jq -c '.items[]' | while read -r ctr; do
            local name state status image networks mounts
            name=$(echo "$ctr" | jq -r '.Names[0] | sub("^/";"")')
            
            # Strip prefix for display
            local display_name="${name#$Q_ARCH_PREFIX}"

            state=$(echo "$ctr" | jq -r '.State')
            status=$(echo "$ctr" | jq -r '.Status')
            image=$(echo "$ctr" | jq -r '.Image')
            
            # Extract Image Tag
            if [[ "$image" == *":"* ]]; then image="${image##*:}"; else image="latest"; fi
            
            # Extract Networks (Keys of NetworkSettings.Networks)
            networks=$(echo "$ctr" | jq -r '.NetworkSettings.Networks | keys | join(", ")')
            
            # Extract Mounts (Volumes) - Types: volume, bind
            mounts=$(echo "$ctr" | jq -r '.Mounts[]? | select(.Type=="volume") | .Name')

            # Colorize State
            local c_icon="${Q_COLOR_RED}●${Q_COLOR_RESET}"
            [[ "$state" == "running" ]] && c_icon="${Q_COLOR_GREEN}●${Q_COLOR_RESET}"
            [[ "$state" == "exited" ]] && c_icon="${Q_COLOR_GREY}○${Q_COLOR_RESET}"

            # Print Container Node
            echo -e "  ├── ${c_icon} ${Q_COLOR_BOLD}${display_name}${Q_COLOR_RESET} (${status})"
            
            # Print Details (Image, Network, Volume)
            echo -e "  │    ├── ${Q_COLOR_YELLOW}img${Q_COLOR_RESET} : ${image}"
            if [[ -n "$networks" ]]; then
                echo -e "  │    ├── ${Q_COLOR_BLUE}net${Q_COLOR_RESET} : ${networks}"
            fi
            if [[ -n "$mounts" ]]; then
                # Loop over mounts if multiple
                while read -r mnt; do
                    [[ -n "$mnt" ]] && echo -e "  │    ├── ${Q_COLOR_GREEN}vol${Q_COLOR_RESET} : ${mnt}"
                done <<< "$mounts"
            fi
            # Visual padding for next item
            echo -e "  │"
        done
    done
    echo ""
}