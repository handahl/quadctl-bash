#!/usr/bin/env bash
# ==============================================================================
# FILE: help.bash
# PATH: src/ui/help.bash
# PROJECT: quadctl
# VERSION: 11.4.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Help documentation and version output.
# ==============================================================================

show_version() {
    echo "quadctl v${Q_VERSION} (SAC-CP Architecture)"
}

show_help() {
    echo "quadctl - Podman Container Lifecycle & Governance Tool"
    echo "USAGE: quadctl [command] [arguments...]"
    echo ""
    echo "observe"
    echo "  status (qs, s)     View status (Running/Failed only)."
    echo "  status all (s a)   View status (Union View incl. Networks)."
    echo "  tree               Hierarchical view of Pods and Containers."
    echo "  shell (s)          Interactive REPL."
    echo "  doctor             System diagnostics."
    echo "  dr                 Daemon Reload."
    echo "  debug <unit>       Enter Debug Cycle (Stop -> Disable Restart -> Start -> Logs)."
    echo "  logs <unit>        Advanced log viewer (Cleaned JSON output)."
    echo ""
    echo "interact"
    echo "  cat <unit>         Show files and drop-ins of specified units"
    echo "  cat intent <unit>  View the DEPLOYED source file (.container)."
    echo "  edit intent <unit> Edit the SOURCE file."
    echo ""
    echo "govern"
    echo "  audit              Static Intent Analysis."
    echo "  migrate            Prefix Governance (Renaming)."
    echo "  deploy             Dry-run (Check drift)."
    echo "  deploy now         Execute rsync + daemon-reload."
    echo "  dry                Shortcut for 'deploy dry-run'."
    echo ""
    echo "units"
    echo "  start | stop | restart <unit>"
    echo "  enable | disable <unit>"
    echo "  mask | unmask <unit>"

    echo ""
    echo "misc"
    echo "  -h, --help         Show this help message."
    echo "  -v, --version      Show version information."
    echo "  Source (Intent):   ${Q_SRC_DIR:-[Unset]}"
    echo "  Target (.config):  ${Q_CONFIG_DIR:-[Unset]}"
    echo "  Socket:            ${Q_PODMAN_SOCK:-[Unset]}"
}