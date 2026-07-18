#!/usr/bin/env bats
# Matrix naming and drift-state tests: the quadlet-file ↔ service-name mapping
# is the join key of the whole matrix — it must never regress.

load helpers

setup() {
    setup_quadctl_env
    source "${INSTALL_ROOT}/src/logic/matrix.bash"
    set +eu; set +o pipefail
}

@test "_quadlet_disk_service_name: .container maps without suffix" {
    [ "$(_quadlet_disk_service_name 'hanlab-web.container')" = "hanlab-web.service" ]
}

@test "_quadlet_disk_service_name: .network appends -network" {
    [ "$(_quadlet_disk_service_name 'hanlab-proxy.network')" = "hanlab-proxy-network.service" ]
}

@test "_quadlet_disk_service_name: .volume/.image/.pod append their type" {
    [ "$(_quadlet_disk_service_name 'hanlab-db.volume')" = "hanlab-db-volume.service" ]
    [ "$(_quadlet_disk_service_name 'hanlab-app.image')" = "hanlab-app-image.service" ]
    [ "$(_quadlet_disk_service_name 'hanlab-stack.pod')" = "hanlab-stack-pod.service" ]
}

@test "_quadlet_disk_service_name: unknown extension fails" {
    run _quadlet_disk_service_name 'hanlab-web.toml'
    [ "$status" -eq 1 ]
}

@test "_quadlet_unit_type: inverse mapping per type" {
    [ "$(_quadlet_unit_type 'hanlab-web.service')" = "container" ]
    [ "$(_quadlet_unit_type 'hanlab-proxy-network.service')" = "network" ]
    [ "$(_quadlet_unit_type 'hanlab-db-volume.service')" = "volume" ]
    [ "$(_quadlet_unit_type 'hanlab-app-image.service')" = "image" ]
    [ "$(_quadlet_unit_type 'hanlab-stack-pod.service')" = "pod" ]
}

@test "calc_uptime: empty and unparseable input return '-'" {
    [ "$(calc_uptime '')" = "-" ]
    [ "$(calc_uptime 'not a date')" = "-" ]
}

@test "calc_uptime: 90 seconds ago renders as minutes" {
    local ts
    ts=$(date -d '-90 seconds' '+%Y-%m-%d %H:%M:%S')
    [ "$(calc_uptime "$ts")" = "1m" ]
}

@test "_unit_drift_state: NeedDaemonReload wins as 'reload'" {
    [ "$(_unit_drift_state 'hanlab-web.service' 'yes' '' 'container')" = "reload" ]
}

@test "_unit_drift_state: non-container units report 'no'" {
    [ "$(_unit_drift_state 'hanlab-proxy-network.service' 'no' '' 'network')" = "no" ]
}

@test "_unit_drift_state: src edited but not deployed → 'pending'" {
    export Q_SRC_DIR="$BATS_TEST_TMPDIR/intent"
    export Q_CONFIG_DIR="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$Q_SRC_DIR" "$Q_CONFIG_DIR"
    printf '[Container]\nImage=a\n' > "$Q_SRC_DIR/hanlab-web.container"
    printf '[Container]\nImage=b\n' > "$Q_CONFIG_DIR/hanlab-web.container"
    [ "$(_unit_drift_state 'hanlab-web.service' 'no' '' 'container')" = "pending" ]
}

@test "_unit_drift_state: identical src and deployed → 'no'" {
    export Q_SRC_DIR="$BATS_TEST_TMPDIR/intent"
    export Q_CONFIG_DIR="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$Q_SRC_DIR" "$Q_CONFIG_DIR"
    printf '[Container]\nImage=a\n' > "$Q_SRC_DIR/hanlab-web.container"
    printf '[Container]\nImage=a\n' > "$Q_CONFIG_DIR/hanlab-web.container"
    [ "$(_unit_drift_state 'hanlab-web.service' 'no' '' 'container')" = "no" ]
}
