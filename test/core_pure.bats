#!/usr/bin/env bats
# Pure-function tests: version comparison, tier checks, specifier expansion.

load helpers

setup() {
    setup_quadctl_env
    source "${INSTALL_ROOT}/src/core/utils.bash"
    source "${INSTALL_ROOT}/src/core/deps.bash"
    set +eu; set +o pipefail
}

@test "vercomp: equal versions return 0" {
    run vercomp 5.2.0 5.2.0
    [ "$status" -eq 0 ]
}

@test "vercomp: greater returns 1" {
    run vercomp 5.3.1 5.2.0
    [ "$status" -eq 1 ]
}

@test "vercomp: lesser returns 2" {
    run vercomp 4.9.4 5.0.0
    [ "$status" -eq 2 ]
}

@test "vercomp: shorter version is zero-padded (5.2 == 5.2.0)" {
    run vercomp 5.2 5.2.0
    [ "$status" -eq 0 ]
}

@test "vercomp: numeric, not lexical (5.10.0 > 5.9.9)" {
    run vercomp 5.10.0 5.9.9
    [ "$status" -eq 1 ]
}

@test "check_version_tiered: at/above preferred passes silently" {
    run check_version_tiered Tool 5.3.0 5.0.0 5.2.0
    [ "$status" -eq 0 ]
}

@test "check_version_tiered: compat tier warns, returns 1" {
    run check_version_tiered Tool 5.1.8 5.0.0 5.2.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"compat"* ]]
}

@test "check_version_tiered: below minimum fails, returns 2" {
    run check_version_tiered Tool 4.4.0 5.0.0 5.2.0
    [ "$status" -eq 2 ]
    [[ "$output" == *"minimum"* ]]
}

@test "expand_specifiers: %h, %t, and tilde" {
    export XDG_RUNTIME_DIR="/run/user/1001"
    [ "$(expand_specifiers '%h/.config')" = "$HOME/.config" ]
    [ "$(expand_specifiers '%t/podman')" = "/run/user/1001/podman" ]
    [ "$(expand_specifiers '~/x')" = "$HOME/x" ]
}
