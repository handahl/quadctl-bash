#!/usr/bin/env bash
# ==============================================================================
# FILE: podman.bash
# PATH: src/core/podman.bash
# PROJECT: quadctl
# DESCRIPTION: Rootless Podman socket API — version negotiation and container map.
# ==============================================================================

# Global version cache — populated once per process
_Q_API_VER=""

# ------------------------------------------------------------------------------
# get_api_version
# Queries /version from the Podman socket. Defaults to v4.0.0 if unreachable.
# Caches result in _Q_API_VER to avoid repeated socket calls.
# ------------------------------------------------------------------------------
get_api_version() {
    if [[ -n "$_Q_API_VER" ]]; then
        echo "$_Q_API_VER"
        return
    fi

    if [[ ! -S "$Q_PODMAN_SOCK" ]]; then
        _Q_API_VER="v4.0.0"
        echo "$_Q_API_VER"
        return
    fi

    local ver_json raw_ver major
    ver_json=$(curl -s --unix-socket "$Q_PODMAN_SOCK" \
        -H "Content-Type: application/json" \
        "http://d/version" 2>/dev/null || echo "{}")

    raw_ver=$(echo "$ver_json" | jq -r '.ApiVersion // "4.0.0"')
    major="${raw_ver%%.*}"

    if [[ "$major" -ge 5 ]]; then
        _Q_API_VER="v5.0.0"
    else
        _Q_API_VER="v4.0.0"
    fi

    echo "$_Q_API_VER"
}

# ------------------------------------------------------------------------------
# query_podman_socket <endpoint> [method]
# Returns raw JSON from the Podman REST API. On failure, returns "[]"
# so callers never receive empty input to jq.
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

    curl -s --unix-socket "$Q_PODMAN_SOCK" \
        -H "Content-Type: application/json" \
        -X "$method" \
        "http://d/${api_v}${endpoint}" 2>/dev/null || echo "[]"
}

# ------------------------------------------------------------------------------
# get_containers_map
# Returns a JSON object keyed by container name (leading "/" stripped).
# Guards against null Names or malformed container objects.
# Returns "{}" on any failure so callers can safely use jq without crashing.
# ------------------------------------------------------------------------------
get_containers_map() {
    local raw
    raw=$(query_podman_socket "/containers/json?all=true")

    if [[ -z "$raw" || "$raw" != \[* ]]; then
        echo "{}"
        return
    fi

    echo "$raw" | jq -r '
        map(select(.Names and (length > 0)))
        | map({ (.Names[0] | sub("^/";"")): . })
        | add // {}
    '
}
