#!/usr/bin/env bash
# ==============================================================================
# FILE: logs.bash
# PATH: src/logic/logs.bash
# PROJECT: quadctl
# VERSION: 10.5.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Advanced log rendering with JSON processing and cleaning.
# ==============================================================================

# ------------------------------------------------------------------------------
# render_clean_logs
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

    log_info "Fetching clean logs for ${unit} (${nlines} lines)..."
    log_info "Press Ctrl+C to exit follow mode."

    # We use a temporary file to buffer the initial tail so we can use 'bat' 
    # for the static part if desired, but for 'follow' (-f), we pipe directly.
    # The 'svc' logic followed (-f).
    
    # 1. Pipeline Construction
    # We construct a pipeline that:
    #   a. Gets JSON output from journalctl
    #   b. Filters with jq to extract MESSAGE
    #   c. [FIX] Ensures MESSAGE is a string to avoid "row of numbers" (binary blobs)
    #   d. Applies unit-specific cleaning (sed)
    
    local jq_filter='.MESSAGE | select(type == "string") // empty'
    
    # Fcitx/C++ Cleaning Pattern (Legacy from svc)
    # Matches: "2023-01-01 12:00:00.123 ..." -> "12:00:00"
    # Matches: "I1200 12:00:00 ..." -> "INFO"
    local fcitx_sed_cmd="sed -E \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2} ([0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+/\1/g' \
        -e 's/[^ ]+\.cpp:[0-9]+\] //g' \
        -e 's/^I([0-9:-]+) /INFO  /' \
        -e 's/^W([0-9:-]+) /WARN  /' \
        -e 's/^E([0-9:-]+) /ERROR /'"

    # 2. Execution
    # We pipe into a subshell to handle the logic
    if [[ "$unit" == *"fcitx"* ]]; then
        journalctl --user -u "$unit" -f -n "$nlines" -o json 2>/dev/null | \
            jq -r --unbuffered "$jq_filter" | \
            eval "$fcitx_sed_cmd"
    else
        journalctl --user -u "$unit" -f -n "$nlines" -o json 2>/dev/null | \
            jq -r --unbuffered "$jq_filter"
    fi
}