#!/usr/bin/env bash
# ==============================================================================
# FILE: tree.bash
# PATH: src/logic/tree.bash
# PROJECT: quadctl
# VERSION: 11.6.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Hierarchical view of Pods and Containers with advanced coloring.
# ==============================================================================

execute_tree_view() {
    log_info "Generating Topology Tree..."
    echo ""

    # 1. FETCH DATA (Pods & Containers)
    # Get JSON output from podman for rich metadata
    local pod_data
    pod_data=$(podman pod ps --format json)
    local ctr_data
    ctr_data=$(podman ps -a --format json)

    # 2. HELPER: COLORIZE IMAGE TAGS
    colorize_image() {
        local img_str="$1"
        # Extract tag (everything after last colon, or 'latest' if none)
        local tag="latest"
        if [[ "$img_str" == *":"* ]]; then
            tag="${img_str##*:}"
        fi

        local color="$Q_COLOR_RESET"

        if [[ "$tag" == "latest" ]]; then
            color="$Q_COLOR_GREEN"
        elif [[ "$tag" =~ ^v[0-9] ]] || [[ "$tag" =~ ^[0-9]+(\.[0-9]+)+ ]]; then
            # "v3.6", "2.0.22" -> Purple (Semantic / Specific)
            color="\033[0;35m" # Purple
        elif [[ "$tag" =~ ^[0-9]+-[a-zA-Z]+ ]] || [[ "$tag" =~ ^v[0-9]+$ ]]; then
             # "18-bookworm", "v3" -> Blue (Major/Stable)
             color="$Q_COLOR_BLUE"
        elif [[ "$tag" =~ ^sha256: ]] || [[ "$tag" =~ ^@sha ]]; then
             # SHA hashes -> Orange
             color="\033[0;33m" # Orange/Yellow
             # Abbreviate SHA for display
             tag="${tag:0:12}..."
        else
             # Fallback -> Blue? Or Reset?
             color="$Q_COLOR_BLUE"
        fi

        echo -e "${color}${tag}${Q_COLOR_RESET}"
    }

    # 3. HELPER: NETWORK EXTRACTION
    get_networks() {
        local ctr_name="$1"
        # Parse JSON for Networks
        echo "$ctr_data" | jq -r --arg name "$ctr_name" '.[] | select(.Names[] | contains($name)) | .Networks // "host"'
    }

    # 4. RENDER STANDALONE CONTAINERS
    echo "[Standalone Containers]"
    
    # Filter containers that do NOT belong to a pod
    # (Podman JSON has "Pod" field, empty if standalone)
    echo "$ctr_data" | jq -c '.[] | select(.Pod == "" or .Pod == null)' | while read -r ctr; do
        local name=$(echo "$ctr" | jq -r '.Names[0]')
        local status=$(echo "$ctr" | jq -r '.Status')
        local image=$(echo "$ctr" | jq -r '.Image')
        
        # Calculate Uptime string
        local uptime_str="-"
        if [[ "$status" =~ Up\ ([^)]+) ]]; then
            uptime_str="${BASH_REMATCH[1]}"
        fi

        # Colorize Image
        local pretty_tag
        pretty_tag=$(colorize_image "$image")
        
        # Networks
        local nets
        nets=$(echo "$ctr" | jq -r '.Networks // "host"')

        echo -e "  ├── ● ${Q_COLOR_RESET}${name} (${uptime_str})"
        echo -e "  │    ├── img : ${pretty_tag}"
        echo -e "  │    ├── net : ${nets}"
        echo -e "  │"
    done
    
    echo ""
}