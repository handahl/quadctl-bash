#!/usr/bin/env bash
##
### logs.bash - Journal log viewer. Delegates to journalctl with clean filters.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : journalctl (systemd)
## ==============================================================================================
#
# Design note: quadctl does not reimplement journalctl's output formatting.
# It calls journalctl with the right flags to remove noise, then gets out of the way.
# Noise sources suppressed:
#   -T podman     — drops container lifecycle events (create/init/start/stop with OCI labels)
#   No -x flag    — suppresses systemd catalog explanations (the ░░ blocks)
#   --output=short-precise — human-readable with millisecond timestamps

# ------------------------------------------------------------------------------
# execute_logs
# Usage: execute_logs <unit> [lines] [follow|no-follow]
# Called from: shim (quadctl logs), debug.bash (execute_debug)
# ------------------------------------------------------------------------------
execute_logs() {
    local unit="${1:-}"
    local nlines="${2:-50}"
    local follow_mode="${3:-follow}"

    if [[ -z "$unit" ]]; then
        log_err "usage: quadctl logs <unit> [lines]"
        return 1
    fi

    log_debug "execute_logs: unit=${unit} lines=${nlines} mode=${follow_mode}"

    local follow_flag="--follow"
    [[ "$follow_mode" == "no-follow" ]] && follow_flag=""

    log_verbose "journalctl --user -u ${unit} --lines=${nlines} --output=short-precise -T podman ${follow_flag}"

    # Reason: --output=short-precise gives human-readable timestamps with microseconds.
    # -T podman drops container lifecycle lines (create/init/start) which carry the full
    # OCI label blob and drown application output in noise.
    # No -x: catalog explanations (░░ blocks) are useful in a manual diagnostic session
    # but add no information in a log tail context.
    # shellcheck disable=SC2086
    journalctl --user \
        -u "${unit}" \
        --lines="${nlines}" \
        --output=short-precise \
        -T podman \
        ${follow_flag}
}

# ------------------------------------------------------------------------------
# execute_logs_from_cursor
# Follows journal output starting from a specific cursor position.
# Used by restart --follow to show only post-restart entries.
# Usage: execute_logs_from_cursor <unit> <cursor>
# ------------------------------------------------------------------------------
execute_logs_from_cursor() {
    local unit="${1:-}"
    local cursor="${2:-}"

    if [[ -z "$unit" ]]; then
        log_err "usage: execute_logs_from_cursor <unit> <cursor>"
        return 1
    fi

    log_debug "execute_logs_from_cursor: unit=${unit} cursor=${cursor:0:20}..."

    if [[ -z "$cursor" ]]; then
        # Fallback: no cursor captured, follow from now
        log_verbose "journalctl --user -u ${unit} --follow --output=short-precise -T podman"
        journalctl --user \
            -u "${unit}" \
            --follow \
            --output=short-precise \
            -T podman
    else
        log_verbose "journalctl --user -u ${unit} --after-cursor=<cursor> --follow --output=short-precise -T podman"
        journalctl --user \
            -u "${unit}" \
            --after-cursor="${cursor}" \
            --follow \
            --output=short-precise \
            -T podman
    fi
}

# ------------------------------------------------------------------------------
# capture_journal_cursor
# Captures the current journal cursor for a unit (the position of the last
# existing entry). Used before a restart to define the "from" boundary.
# Usage: cursor=$(capture_journal_cursor <unit>)
# ------------------------------------------------------------------------------
capture_journal_cursor() {
    local unit="${1:-}"
    # --lines=0 fetches no entries; --show-cursor prints the current position.
    # -q suppresses the "-- No entries --" info message.
    journalctl --user \
        -u "${unit}" \
        --lines=0 \
        --show-cursor \
        --quiet \
        2>/dev/null \
        | awk '/^-- cursor:/{print $NF; exit} /^-- Cursor:/{print $NF; exit}'
}
