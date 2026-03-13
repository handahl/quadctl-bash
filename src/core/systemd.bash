#!/usr/bin/env bash
# ==============================================================================
# FILE: systemd.bash
# PATH: src/core/systemd.bash
# PROJECT: quadctl
# DESCRIPTION: Systemd user session queries — state map and generator utilities.
# ==============================================================================

# ------------------------------------------------------------------------------
# api_systemd_get_state_map
# Returns a single JSON object keyed by unit name (e.g. "hanlab-foo.service"),
# containing: active, sub, drift (NeedDaemonReload), and ts (ActiveEnterTimestamp).
#
# Uses pure-bash line parsing on `systemctl show` output to avoid spawning
# one process per unit. The block separator (empty line) flushes each unit.
# Final unit is flushed explicitly to handle the no-trailing-newline case.
# ------------------------------------------------------------------------------
api_systemd_get_state_map() {
    local pattern="${Q_ARCH_PREFIX}*.service"

    local raw_data
    raw_data=$(systemctl --user show "$pattern" \
        --property=Id,ActiveState,SubState,NeedDaemonReload,ActiveEnterTimestamp \
        --no-pager 2>/dev/null)

    if [[ -z "$raw_data" ]]; then
        echo "{}"
        return
    fi

    {
        local id="" active="" sub="" drift="" ts=""
        while IFS='=' read -r key value; do
            if [[ -z "$key" ]]; then
                if [[ -n "$id" ]]; then
                    printf '{"%s":{"active":"%s","sub":"%s","drift":"%s","ts":"%s"}}\n' \
                        "$id" "$active" "$sub" "$drift" "$ts"
                fi
                id="" active="" sub="" drift="" ts=""
                continue
            fi
            case "$key" in
                Id)                   id="$value"     ;;
                ActiveState)          active="$value"  ;;
                SubState)             sub="$value"     ;;
                NeedDaemonReload)     drift="$value"   ;;
                ActiveEnterTimestamp) ts="$value"      ;;
            esac
        done <<< "$raw_data"

        # Flush final block (no trailing newline in systemctl output)
        if [[ -n "$id" ]]; then
            printf '{"%s":{"active":"%s","sub":"%s","drift":"%s","ts":"%s"}}\n' \
                "$id" "$active" "$sub" "$drift" "$ts"
        fi
    } | jq -s 'add // {}'
}

# ------------------------------------------------------------------------------
# api_systemd_reload
# Wraps daemon-reload. Called after deploy applies changes.
# ------------------------------------------------------------------------------
api_systemd_reload() {
    systemctl --user daemon-reload
}

# ------------------------------------------------------------------------------
# api_systemd_verify_generator
# Dry-runs the Quadlet generator to validate pending unit files.
# Requires discover_quadlet_generator from src/core/deps.bash (already sourced).
# ------------------------------------------------------------------------------
api_systemd_verify_generator() {
    local gen
    gen=$(discover_quadlet_generator) || {
        log_err "Quadlet generator not found."
        return 1
    }
    "$gen" --user --dryrun 2>&1
}
