#!/usr/bin/env bash
# ==============================================================================
# FILE: podman.bash
# PATH: src/api/podman.bash
# PROJECT: quadctl
# VERSION: 10.5.1
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Socket-based Podman API interaction with Dynamic Versioning.
# ==============================================================================

# Global cache for API version
_Q_API_VER=""

# ------------------------------------------------------------------------------
# get_api_version
# Dynamically determines the Libpod API version from the socket.
# Defaults to 4.0.0 if unreachable, to allow graceful degradation.
# ------------------------------------------------------------------------------
get_api_version() {
    if [[ -n "$_Q_API_VER" ]]; then
        echo "$_Q_API_VER"
        return
    fi

    if [[ ! -S "$Q_PODMAN_SOCK" ]]; then
        echo "4.0.0"
        return
    fi

    # Query /version endpoint
    local ver_json
    ver_json=$(curl -s --unix-socket "$Q_PODMAN_SOCK" -H "Content-Type: application/json" "http://d/version" || echo "{}")
    
    # Extract ApiVersion (e.g., "5.7.1"). 
    # Libpod often requires the major version in the URL, e.g., v5.0.0.
    # Safe default logic: if > 5, use v5.0.0, else v4.0.0
    local raw_ver
    raw_ver=$(echo "$ver_json" | jq -r '.ApiVersion // "4.0.0"')
    
    local major="${raw_ver%%.*}"
    if [[ "$major" -ge 5 ]]; then
        _Q_API_VER="v5.0.0"
    else
        _Q_API_VER="v4.0.0"
    fi
    
    echo "$_Q_API_VER"
}

# ------------------------------------------------------------------------------
# query_podman_socket
# ------------------------------------------------------------------------------
query_podman_socket() {
    local endpoint="$1"
    local method="${2:-GET}"

    if [[ ! -S "$Q_PODMAN_SOCK" ]]; then
        echo "[]"
        return 1
    fi

    local api_v
    api_v=$(get_api_version)

    # Retrieve data. On failure, output empty array [] to prevent jq crashes downstream.
    curl -s --unix-socket "$Q_PODMAN_SOCK" \
        -H "Content-Type: application/json" \
        -X "$method" \
        "http://d/${api_v}${endpoint}" || echo "[]"
}

# ------------------------------------------------------------------------------
# get_containers_map
# Returns a JSON object keyed by Container Name.
# Includes guards against null Names or malformed container objects.
# ------------------------------------------------------------------------------
get_containers_map() {
    local raw
    raw=$(query_podman_socket "/containers/json?all=true")
    
    if [[ -z "$raw" || "$raw" != \[* ]]; then
        echo "{}"
        return
    fi

    echo "$raw" | jq -r 'map(select(.Names and length > 0) | { (.Names[0] | sub("^/";"")): . } ) | add // {}'
}