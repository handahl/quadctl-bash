#!/usr/bin/env bash
##
### helpers.bash - Shared bats bootstrap: isolated env, controlled prefix.
## ==============================================================================================
### TARGET : test only — never sourced by the tool itself
### DEPS   : bats-core
## ==============================================================================================
#
# Reason: tests must be hermetic. The operator's real ~/.config/quadctl/config,
# prefix, and verbosity must not leak in; nothing here may touch systemd or podman.

setup_quadctl_env() {
    INSTALL_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INSTALL_ROOT

    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export QUADCTL_PREFIX="hanlab-"
    export Q_SILENT_ENV=1
    export Q_VERBOSITY=0
    mkdir -p "$XDG_CONFIG_HOME"

    source "${INSTALL_ROOT}/src/core/env.bash"

    # Reason: env.bash enables strict mode for the tool; bats manages its own
    # error handling and must not inherit errexit/nounset from the sourced code.
    set +eu
    set +o pipefail
}
