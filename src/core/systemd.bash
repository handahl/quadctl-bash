#!/usr/bin/env bash
##
### systemd.bash - Systemd user session queries: state map and generator utilities.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : systemd, jq
## ==============================================================================================
#

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
# api_systemd_check_generator_freshness
# Scans the transient generator directory for prefixed services whose quadlet
# source file is newer than the generated unit — the signature of a Quadlet
# rejection (generator ran but refused the file) or a missed daemon-reload.
# Warns per stale unit. Returns 0 when consistent, 1 when stale output found.
# Shared by 'quadctl dr' and deploy stage 4 — do not duplicate this scan.
# ------------------------------------------------------------------------------
api_systemd_check_generator_freshness() {
    local generator_dir="${XDG_RUNTIME_DIR}/systemd/generator"
    [[ -d "$generator_dir" ]] || return 0

    local stale=0
    local svc_file stem bare src_name src src_mt svc_mt
    while IFS= read -r svc_file; do
        stem="${svc_file%.service}"
        stem="${stem##*/}"
        bare="${stem#"${Q_ARCH_PREFIX}"}"

        # Inverse of the generator's naming: foo-network.service ← foo.network etc.
        case "$bare" in
            *-network) src_name="${bare%-network}.network" ;;
            *-volume)  src_name="${bare%-volume}.volume"   ;;
            *-image)   src_name="${bare%-image}.image"     ;;
            *-pod)     src_name="${bare%-pod}.pod"         ;;
            *)         src_name="${bare}.container"        ;;
        esac

        src="${Q_CONFIG_DIR}/${Q_ARCH_PREFIX}${src_name}"
        [[ -f "$src" ]] || continue

        src_mt=$(stat -c %Y "$src" 2>/dev/null || echo 0)
        svc_mt=$(stat -c %Y "$svc_file" 2>/dev/null || echo 0)
        if (( src_mt > svc_mt )); then
            log_warn "${bare}: source file is newer than generated service — Quadlet may have rejected it."
            log_warn "  Check: journalctl --user -xe | grep -i quadlet"
            stale=1
        fi
    done < <(find "$generator_dir" -name "${Q_ARCH_PREFIX}*.service" 2>/dev/null)

    return "$stale"
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
