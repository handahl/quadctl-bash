#!/usr/bin/env bash
# ==============================================================================
# FILE: logs.bash
# PATH: src/logic/logs.bash
# PROJECT: quadctl
# VERSION: 11.1.0
# DESCRIPTION: Log rendering via journalctl JSON pipeline.
# ==============================================================================

# ------------------------------------------------------------------------------
# execute_logs
# $1: Unit Name
# $2: Line Count (default 50)
# ------------------------------------------------------------------------------
execute_logs() {
    local unit="$1"
    local nlines="${2:-50}"

    if [[ -z "$unit" ]]; then
        log_err "Usage: logs <unit> [lines]"
        return 1
    fi

    log_info "Fetching logs for ${unit} (${nlines} lines)..."
    log_info "Press Ctrl+C to exit follow mode."

    # Pipeline:
    #   a. journalctl JSON output
    #   b. jq extracts MESSAGE field
    #   c. select(type == "string") guards against binary blob entries
    local jq_filter='.MESSAGE | select(type == "string") // empty'

    journalctl --user -u "$unit" -f -n "$nlines" -o json 2>/dev/null | \
        jq -r --unbuffered "$jq_filter"
}
