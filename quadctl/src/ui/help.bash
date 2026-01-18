#!/usr/bin/env bash
# ==============================================================================
# FILE: help.bash
# PATH: src/ui/help.bash
# PROJECT: quadctl
# VERSION: 11.2.0
# DATE: 2026-01-18
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Help documentation and version output.
# ==============================================================================

show_version() {
    echo "quadctl v${Q_VERSION}"
}

show_help() {
    echo "quadctl - Container Lifecycle & Governance Tool"
    echo ""
    echo "USAGE"
    echo "  quadctl [command] [arguments...]"
    echo ""
    echo "OBSERVABILITY"
    echo "  matrix, status     High-density reconciliation view (Intent vs Runtime)."
    echo "  tree               Hierarchical view of Pods and Containers."
    echo "  doctor             System diagnostics (D-Bus latency, job queues)."
    echo ""
    echo "INTERACTION (Intent vs Runtime)"
    echo "  cat <name>         View the GENERATED unit (Runtime / systemctl cat)."
    echo "  cat intent <name>  View the DEPLOYED source file (Intent)."
    echo "  edit intent <name> Edit the SOURCE file in your Git repo."
    echo ""
    echo "GOVERNANCE & DEPLOYMENT"
    echo "  audit              Static Intent Analysis (Security & Integrity checks)."
    echo "  migrate            Prefix Governance (Standardize naming conventions)."
    echo "  deploy             Synchronize Intent to Runtime."
    echo "                     deploy          -> Dry-run (Preview changes)."
    echo "                     deploy force    -> Execute rsync + daemon-reload."
    echo ""
    echo "UNIT CONTROL"
    echo "  start | stop | restart   <unit>"
    echo "  enable | disable         <unit>"
    echo "  mask | unmask            <unit>"
    echo "  "
    echo "  * Note: If <unit> is omitted, interactive selection (fzf) is launched."
    echo ""
    echo "DEBUGGING & TOOLS"
    echo "  debug <unit>       Enter Debug Cycle (Stop -> Disable Restart -> Start -> Logs)."
    echo "  logs <unit>        Advanced log viewer (Cleaned JSON output)."
    echo "  shell              Enter interactive REPL."
    echo "  rd, dr             Fast alias for 'systemctl --user daemon-reload'."
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