#!/usr/bin/env bash
# ==============================================================================
# FILE: help.bash
# PATH: src/ui/help.bash
# PROJECT: quadctl
# VERSION: 11.9.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Help documentation and version output (Capability-Aware).
# ==============================================================================

show_version() {
    echo "quadctl v${Q_VERSION} (SAC-CP Architecture)"
}

show_help() {
    echo "quadctl - Podman Container Lifecycle & Governance Tool"
    echo "USAGE: quadctl [command] [arguments...]"
    echo ""
    echo "observe"
    echo "  status [all]           View status. Optional: 'all' shows all unit states incl. Networks."
    echo "  matrix                 Hierarchical reconciliation of intent, units, and containers."
    echo "  tree                   Hierarchical view of Pods and Containers."
    echo "  shell                  Interactive REPL."
    echo "  doctor                 System diagnostics."
    echo "  reload-daemon (rd)     Systemd daemon reload."
    echo "  logs <unit>            Advanced log viewer (cleaned output)."

    # Conditional: Only show debug if the module is present
    if [[ -f "${QUADCTL_HOME}/src/logic/debug.bash" ]]; then
        echo "  debug <unit>           Debug Cycle: Stop -> Disable Restart -> Start -> Logs."
    fi

    echo ""
    echo "inspect"
    echo "  cat <unit>             Show systemd unit files and drop-ins."
    echo "  depends-on <unit>      List dependencies required by <unit>."
    echo "  depended-by <unit>     List units that depend on <unit> (reverse)."

    echo ""
    echo "govern"
    echo "  audit                  Static Intent Analysis (Secrets, Env Files, Prefix)."
    echo "  migrate                Prefix Governance and Unit Renaming."
    echo "  deploy [force]         Sync intent to runtime. Optional: 'force' applies changes."

    echo ""
    echo "units"
    echo "  start <unit>           Start a unit. Pre-flight: existence + dependency check."
    echo "  stop <unit>            Stop a unit."
    echo "  restart <unit>         Restart a unit. Pre-flight: existence + dependency check."
    echo "  enable <unit>          Enable unit for auto-start."
    echo "  disable <unit>         Disable unit from auto-start."
    echo "  mask <unit>            Prevent unit from being started."
    echo "  unmask <unit>          Allow masked unit to start."

    echo ""
    echo "options"
    echo "  -h, --help             Show this help message."
    echo "  -v, --version          Show version information."

    echo ""
    echo "paths"
    echo "  Intent (Source):       ${Q_SRC_DIR:-[Unset]}"
    echo "  Runtime (Config):      ${Q_CONFIG_DIR:-[Unset]}"
    echo "  Podman Socket:         ${Q_PODMAN_SOCK:-[Unset]}"
    echo "  Architecture Prefix:   ${Q_ARCH_PREFIX:-[Unset]}"
}