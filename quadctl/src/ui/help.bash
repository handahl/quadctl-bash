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
    echo "quadctl - Container Lifecycle & Governance Tool"
    echo ""
    echo "USAGE: quadctl [command] [arguments...]"
    echo ""
    echo "OBSERVABILITY"
    echo "  status (qs, s)     View status (Running/Failed only)."
    echo "  status all (s a)   View status (Union View incl. Networks)."
    echo "  tree               Hierarchical view of Pods and Containers."
    echo "  shell (s)          Interactive REPL."
    echo "  doctor             System diagnostics."
    echo "  dr                 Daemon Reload."
    echo "  debug <unit>       Enter Debug Cycle (Stop -> Disable Restart -> Start -> Logs)."
    echo "  logs <unit>        Advanced log viewer (Cleaned JSON output)."
    echo ""
    echo "INTERACTION"
    echo "  cat <unit>         Show files and drop-ins of specified units"
    echo "  cat intent <unit>  View the DEPLOYED source file (.container)."
    echo "  edit intent <unit> Edit the SOURCE file."
    echo ""
    echo "GOVERNANCE & DEPLOYMENT"
    echo "  audit              Static Intent Analysis."
    echo "  migrate            Prefix Governance (Renaming)."
    echo "  deploy             Dry-run (Check drift)."
    echo "  deploy now         Execute rsync + daemon-reload."
    echo "  dry                Shortcut for 'deploy dry-run'."
    echo ""
    echo "UNIT CONTROL"
    echo "  start | stop | restart <unit>"
    echo "  enable | disable <unit>"
    echo "  mask | unmask <unit>"

    echo ""
    echo "OPTIONS"
    echo "  -h, --help         Show this help message."
    echo "  -v, --version      Show version information."
    echo ""
    echo "ENVIRONMENT"
    echo "  Source (Intent):   ${Q_SRC_DIR:-[Unset]}"
    echo "  Target (Config):   ${Q_CONFIG_DIR:-[Unset]}"
    echo "  Socket:            ${Q_PODMAN_SOCK:-[Unset]}"
}