#!/usr/bin/env bash
# ==============================================================================
# FILE: systemd.bash
# PATH: src/api/systemd.bash
# PROJECT: quadctl
# VERSION: 10.3.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Wrapper for Systemd User Session interactions.
# ==============================================================================

# ------------------------------------------------------------------------------
# api_systemd_get_state_map
# Returns a JSON object keyed by unit name, containing detailed properties.
# Uses 'systemctl show' for bulk retrieval of Drift and Uptime info.
# ------------------------------------------------------------------------------
api_systemd_get_state_map() {
    local pattern="${Q_ARCH_PREFIX}*.service"
    
    # We query specific properties to keep it lightweight.
    # We use a trick with jq to convert the block output of systemctl show into JSON.
    # Input format:
    # Id=foo.service
    # ActiveState=active
    # ...
    # <newline>
    
    local raw_data
    raw_data=$(systemctl --user show "$pattern" \
        --property=Id,ActiveState,SubState,NeedDaemonReload,ActiveEnterTimestamp \
        --no-pager)

    if [[ -z "$raw_data" ]]; then
        echo "{}"
        return
    fi

    # Parsing logic:
    # 1. Read line by line.
    # 2. Accumulate key=values.
    # 3. On empty line, emit JSON object.
    # This is done in pure bash for speed/portability, outputting a stream of JSON objects
    # which jq then slurps into a map.

    {
        local id="" active="" sub="" drift="" ts=""
        while IFS='=' read -r key value; do
            # Handle block separator (empty line)
            if [[ -z "$key" ]]; then
                if [[ -n "$id" ]]; then
                    printf '{"%s": {"active": "%s", "sub": "%s", "drift": "%s", "ts": "%s"}}\n' \
                        "$id" "$active" "$sub" "$drift" "$ts"
                fi
                id="" active="" sub="" drift="" ts=""
                continue
            fi
            
            case "$key" in
                Id) id="$value" ;;
                ActiveState) active="$value" ;;
                SubState) sub="$value" ;;
                NeedDaemonReload) drift="$value" ;;
                ActiveEnterTimestamp) ts="$value" ;;
            esac
        done <<< "$raw_data"
        
        # Flush last item if no trailing newline
        if [[ -n "$id" ]]; then
             printf '{"%s": {"active": "%s", "sub": "%s", "drift": "%s", "ts": "%s"}}\n' \
                "$id" "$active" "$sub" "$drift" "$ts"
        fi
    } | jq -s 'add // {}'
}

api_systemd_reload() {
    systemctl --user daemon-reload
}

api_systemd_verify_generator() {
    local gen="/usr/lib/systemd/system-generators/podman-system-generator"
    if [[ -x "$gen" ]]; then
        "$gen" --user --dryrun 2>&1
    else
        echo "Generator binary not found at $gen"
        return 1
    fi
}
