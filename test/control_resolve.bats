#!/usr/bin/env bats
# Identity resolution tests — only the branches that need no systemd.

load helpers

setup() {
    setup_quadctl_env
    source "${INSTALL_ROOT}/src/logic/control.bash"
    set +eu; set +o pipefail
}

@test "resolve_unit_name: fully qualified .service passes through unchanged" {
    run resolve_unit_name 'hanlab-traefik.service'
    [ "$status" -eq 0 ]
    [ "$output" = "hanlab-traefik.service" ]
}

@test "resolve_unit_name: other unit extensions pass through unchanged" {
    run resolve_unit_name 'hanlab-lego.timer'
    [ "$output" = "hanlab-lego.timer" ]
}
