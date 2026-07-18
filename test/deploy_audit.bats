#!/usr/bin/env bats
# Audit gate and deploy safety tests. Everything runs against temp fixture
# directories — no systemd, no podman, no rsync into real paths.

load helpers

setup() {
    setup_quadctl_env
    source "${INSTALL_ROOT}/src/core/utils.bash"
    source "${INSTALL_ROOT}/src/logic/deploy.bash"
    set +eu; set +o pipefail

    export Q_SRC_DIR="$BATS_TEST_TMPDIR/intent"
    export Q_CONFIG_DIR="$BATS_TEST_TMPDIR/runtime"
    mkdir -p "$Q_SRC_DIR" "$Q_CONFIG_DIR"
}

@test "audit_directory: compliant intent dir passes" {
    printf '[Container]\nContainerName=hanlab-web\nImage=docker.io/nginx:1.27\n' \
        > "$Q_SRC_DIR/hanlab-web.container"
    run audit_directory
    [ "$status" -eq 0 ]
    [[ "$output" == *"audit passed"* ]]
}

@test "audit_directory: empty intent dir warns but passes" {
    run audit_directory
    [ "$status" -eq 0 ]
    [[ "$output" == *"no quadlet files"* ]]
}

@test "audit_directory: wrong prefix is flagged" {
    printf '[Container]\nImage=x\n' > "$Q_SRC_DIR/oops-web.container"
    run audit_directory
    [ "$status" -eq 1 ]
    [[ "$output" == *"naming format"* ]]
}

@test "audit_directory: missing EnvironmentFile is flagged" {
    printf '[Container]\nEnvironmentFile=%%h/.config/does-not-exist-xyz.env\n' \
        > "$Q_SRC_DIR/hanlab-web.container"
    run audit_directory
    [ "$status" -eq 1 ]
    [[ "$output" == *"EnvironmentFile"* ]]
}

@test "audit_directory: hardcoded secret is flagged" {
    printf '[Container]\nEnvironment=api_key=abc123\n' > "$Q_SRC_DIR/hanlab-web.container"
    run audit_directory
    [ "$status" -eq 1 ]
    [[ "$output" == *"SECURITY"* ]]
}

@test "execute_deploy now: refuses --delete sync from an empty intent dir" {
    # Reason: this is the rsync wipe hazard — an empty source must never
    # empty the runtime dir. Sentinel proves nothing was deleted.
    printf 'sentinel\n' > "$Q_CONFIG_DIR/hanlab-keepme.container"
    run execute_deploy now
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing"* ]]
    [ -f "$Q_CONFIG_DIR/hanlab-keepme.container" ]
}
