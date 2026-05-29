#!/usr/bin/env bash
# ==============================================================================
# FILE: matrix.bash
# PATH: src/logic/matrix.bash
# PROJECT: quadctl
# DESCRIPTION: High-density reconciliation matrix. Union of disk intent and
#              systemd runtime state, keyed on canonical service names.
# ==============================================================================

source "${INSTALL_ROOT}/src/core/podman.bash"
source "${INSTALL_ROOT}/src/core/systemd.bash"

# ------------------------------------------------------------------------------
# _quadlet_unit_type <service-name>
# Determines the quadlet source type from the generated service name.
#
# Quadlet naming convention (systemd generator output):
#   foo.container → foo.service          (no suffix)
#   foo.network   → foo-network.service  (type appended with hyphen)
#   foo.volume    → foo-volume.service
#   foo.image     → foo-image.service
#   foo.pod       → foo-pod.service
#
# This is the inverse mapping: given a .service name, determine which
# quadlet type generated it. Used for filtering and section grouping.
# ------------------------------------------------------------------------------
_quadlet_unit_type() {
    local stem="${1%.service}"
    # Strip the arch prefix before checking the type suffix
    stem="${stem#"${Q_ARCH_PREFIX}"}"
    case "$stem" in
        *-network) echo "network"   ;;
        *-volume)  echo "volume"    ;;
        *-image)   echo "image"     ;;
        *-pod)     echo "pod"       ;;
        *)         echo "container" ;;
    esac
}

# ------------------------------------------------------------------------------
# _quadlet_disk_service_name <filename>
# Maps a quadlet file basename to the canonical systemd service name.
# Must match what the Quadlet generator produces — tested against Podman 4/5.
# ------------------------------------------------------------------------------
_quadlet_disk_service_name() {
    local filename="$1"
    local ext stem
    ext="${filename##*.}"
    stem="${filename%.*}"
    case "$ext" in
        container) echo "${stem}.service"         ;;
        network)   echo "${stem}-network.service" ;;
        volume)    echo "${stem}-volume.service"  ;;
        image)     echo "${stem}-image.service"   ;;
        pod)       echo "${stem}-pod.service"     ;;
        *)         return 1                        ;;
    esac
}

# ------------------------------------------------------------------------------
# calc_uptime <ActiveEnterTimestamp-string>
# Converts systemd's timestamp string into a human-readable relative duration.
# Returns "-" on empty or unparseable input.
# ------------------------------------------------------------------------------
calc_uptime() {
    local ts_str="$1"
    [[ -z "$ts_str" ]] && echo "-" && return

    local ts_epoch
    ts_epoch=$(date -d "$ts_str" +%s 2>/dev/null) || { echo "-"; return; }
    [[ -z "$ts_epoch" ]] && echo "-" && return

    local now diff
    now=$(date +%s)
    diff=$((now - ts_epoch))

    if   (( diff <    60 )); then echo "${diff}s"
    elif (( diff <  3600 )); then echo "$((diff / 60))m"
    elif (( diff < 86400 )); then echo "$((diff / 3600))h"
    else                          echo "$((diff / 86400))d"
    fi
}

# ------------------------------------------------------------------------------
# execute_matrix_view [standard|all]
#
# Standard (default): container units only — the operational view.
#   Hides inactive/missing units unless failed or auto-restarting.
#   Hides network/volume/image/pod units entirely.
#
# All: containers first (same filter relaxed), then a separated section
#   showing network/volume/image/pod units. Used with `quadctl matrix --all`.
#
# Deduplication: disk discovery produces canonical service names using
# _quadlet_disk_service_name(), which matches what systemd generates.
# The union merge (sort -u) then correctly deduplicates without ghost rows.
# ------------------------------------------------------------------------------
execute_matrix_view() {
    local filter_type="${1:-standard}"
    [[ "$filter_type" =~ ^(a|all)$ ]] && filter_type="all"

    echo "quadctl"

    # 1. FETCH RUNTIME STATE
    local sys_map pod_map
    sys_map=$(api_systemd_get_state_map)
    pod_map=$(get_containers_map)

    # 2. DISCOVER DISK INTENT
    # Map every quadlet file to its canonical systemd service name.
    # This is what prevents the double-entry bug: hanlab-proxy.network
    # becomes hanlab-proxy-network.service here AND in the systemd map,
    # so sort -u deduplicates them correctly into one row.
    local disk_units=()
    if [[ -d "$Q_CONFIG_DIR" ]]; then
        while IFS= read -r file; do
            local svc
            svc=$(_quadlet_disk_service_name "$(basename "$file")") || continue
            disk_units+=("$svc")
        done < <(find "$Q_CONFIG_DIR" -maxdepth 2 -type f \
            \( -name "${Q_ARCH_PREFIX}*.container" \
            -o -name "${Q_ARCH_PREFIX}*.network"   \
            -o -name "${Q_ARCH_PREFIX}*.volume"    \
            -o -name "${Q_ARCH_PREFIX}*.image"     \
            -o -name "${Q_ARCH_PREFIX}*.pod"       \) 2>/dev/null | sort)
    fi

    # 3. MERGE: union of disk + runtime, deduplicated and sorted
    local runtime_keys all_units
    runtime_keys=$(echo "$sys_map" | jq -r 'keys[]' 2>/dev/null || true)
    all_units=$(printf "%s\n" \
        "${disk_units[@]+"${disk_units[@]}"}" \
        ${runtime_keys:+"$runtime_keys"} \
        | sort -u | grep -v '^$')

    if [[ -z "$all_units" ]]; then
        log_warn "No units found (neither on disk nor in systemd)."
        return
    fi

    # 4. HEADER
    printf "%-27s %-8s %-10s %-10s %-7s %-10s %-13s %s\n" \
        "UNITNAME" "DRIFT" "STATE" "SUB" "UPTIME" "HEALTH" "VERSION" "ROUTING"
    printf '%0.s─' {1..108}; echo

    # 5. ITERATE — collect into typed buffers for ordered output
    local lines_containers=()
    local lines_aux=()

    while IFS= read -r unit; do
        # Only process units that belong to this prefix
        [[ "$unit" != "${Q_ARCH_PREFIX}"* ]] && continue

        local utype
        utype=$(_quadlet_unit_type "$unit")

        # Standard view: skip infrastructure units
        if [[ "$filter_type" != "all" && "$utype" != "container" ]]; then
            continue
        fi

        # --- SYSTEMD STATE ---
        local s_active s_sub s_drift s_ts
        if echo "$sys_map" | jq -e --arg k "$unit" 'has($k)' >/dev/null 2>&1; then
            s_active=$(echo "$sys_map" | jq -r --arg k "$unit" '.[$k].active')
            s_sub=$(echo    "$sys_map" | jq -r --arg k "$unit" '.[$k].sub')
            s_drift=$(echo  "$sys_map" | jq -r --arg k "$unit" '.[$k].drift')
            s_ts=$(echo     "$sys_map" | jq -r --arg k "$unit" '.[$k].ts')
        else
            s_active="missing"
            s_sub="-"
            s_drift="-"
            s_ts=""
        fi

        # Standard view activity filter (containers only at this point)
        if [[ "$filter_type" != "all" ]]; then
            if [[ "$s_active" == "missing" ]]; then continue; fi
            if [[ "$s_active" == "inactive" \
               && "$s_sub" != "failed"      \
               && "$s_sub" != "auto-restart" ]]; then continue; fi
        fi

        # --- DISPLAY VALUES ---
        local clean_name drift_disp uptime_disp
        clean_name="${unit#"${Q_ARCH_PREFIX}"}"
        clean_name="${clean_name%.service}"

        case "$s_drift" in
            yes)  drift_disp="${Q_COLOR_YELLOW}drift${Q_COLOR_RESET}"  ;;
            no)   drift_disp="${Q_COLOR_GREEN}synced${Q_COLOR_RESET}"  ;;
            *)    drift_disp="-"                                        ;;
        esac

        uptime_disp=$(calc_uptime "$s_ts")

        # State color
        local state_color=""
        case "$s_active" in
            active)   state_color="${Q_COLOR_GREEN}"  ;;
            failed)   state_color="${Q_COLOR_RED}"    ;;
            missing)  state_color="${Q_COLOR_GREY}"   ;;
            *)        state_color="${Q_COLOR_YELLOW}" ;;
        esac

        # --- PODMAN PROPS (container units only — others get dashes) ---
        local p_health="-" p_image="-" p_ports="-"

        if [[ "$utype" == "container" ]]; then
            local pod_json
            pod_json=$(echo "$pod_map" | jq -r \
                --arg n1 "${unit%.service}" \
                --arg n2 "$clean_name" \
                '.[$n1] // .[$n2] // empty' 2>/dev/null)

            if [[ -n "$pod_json" ]]; then
                local raw_status raw_image labels rule
                raw_status=$(echo "$pod_json" | jq -r '.Status // ""')
                raw_image=$(echo  "$pod_json" | jq -r '.Image  // ""')
                labels=$(echo     "$pod_json" | jq -r '.Labels // {}')

                case "$raw_status" in
                    *"(healthy)"*)   p_health="healthy"   ;;
                    *"(unhealthy)"*) p_health="unhealthy" ;;
                    *"(starting)"*)  p_health="starting"  ;;
                    *)               p_health="n/a"       ;;
                esac

                if [[ "$raw_image" == *":"* ]]; then
                    p_image="${raw_image##*:}"
                    p_image="${p_image:0:12}"
                else
                    p_image="latest"
                fi

                # Traefik Host rule from container labels (file provider — not socket labels)
                # Labels set via Label= in the quadlet file are present in the Podman API.
                rule=$(echo "$labels" | jq -r '
                    to_entries[]
                    | select(.key | contains("routers"))
                    | .value
                    | capture("Host\\(`(?<host>[^`]+)`\\)")
                    | .host
                ' 2>/dev/null | head -n1)

                if [[ -n "$rule" ]]; then
                    p_ports="● ${rule}"
                else
                    local raw_ports
                    raw_ports=$(echo "$pod_json" | jq -r '
                        .Ports // []
                        | map(select(.hostPort)
                              | "\(.hostPort):\(.containerPort)/\(.protocol)")
                        | join(" ")
                    ' 2>/dev/null)
                    [[ -n "$raw_ports" ]] && p_ports="$raw_ports"
                fi
            fi
        fi

        # --- RENDER ROW into buffer ---
        local rendered
        # Reason: printf -v would be cleaner but doesn't handle embedded color resets
        # portably across all printf implementations. Subshell capture is safe here.
        rendered=$(printf "%-27s %-8s ${state_color}%-10s${Q_COLOR_RESET} %-10s %-7s %-10s %-13s %s\n" \
            "$clean_name" "$drift_disp" "$s_active" "$s_sub" \
            "$uptime_disp" "$p_health" "$p_image" "$p_ports")

        if [[ "$utype" == "container" ]]; then
            lines_containers+=("$rendered")
        else
            lines_aux+=("$rendered")
        fi

    done <<< "$all_units"

    # 6. OUTPUT — containers first, then infrastructure section
    for line in "${lines_containers[@]+"${lines_containers[@]}"}"; do
        echo "$line"
    done

    if [[ "$filter_type" == "all" && ${#lines_aux[@]} -gt 0 ]]; then
        echo ""
        printf "${Q_COLOR_GREY}%-27s %-8s %-10s %-10s %-7s${Q_COLOR_RESET}\n" \
            "  INFRASTRUCTURE" "DRIFT" "STATE" "SUB" "UPTIME"
        printf '%0.s─' {1..108}; echo
        for line in "${lines_aux[@]}"; do
            echo "$line"
        done
    fi
}
