#!/usr/bin/env bash
# ==============================================================================
# FILE: help.bash
# PATH: src/ui/help.bash
# PROJECT: quadctl
# VERSION: 10.6.4
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: CLIG-compliant help and usage documentation.
# ==============================================================================

show_version() {
    echo "quadctl v10.6.4 (SAC-CP Architecture)"
    echo "Compliance: XDG, POSIX, Bash 5.3+"
}

show_help() {
    cat <<EOF
${Q_COLOR_BLUE}quadctl${Q_COLOR_RESET} - Container Lifecycle & Governance Tool

${Q_COLOR_YELLOW}USAGE${Q_COLOR_RESET}
  quadctl [command] [arguments...]

${Q_COLOR_YELLOW}OBSERVABILITY${Q_COLOR_RESET}
  ${Q_COLOR_GREEN}matrix, status${Q_COLOR_RESET}    High-density reconciliation view (Intent vs Runtime).
  ${Q_COLOR_GREEN}tree${Q_COLOR_RESET}              Hierarchical view of Pods and Containers.
  ${Q_COLOR_GREEN}doctor${Q_COLOR_RESET}            System diagnostics (D-Bus latency, job queues).

${Q_COLOR_YELLOW}GOVERNANCE & DEPLOYMENT${Q_COLOR_RESET}
  ${Q_COLOR_GREEN}audit${Q_COLOR_RESET}             Static Intent Analysis (Security & Integrity checks).
  ${Q_COLOR_GREEN}deploy${Q_COLOR_RESET}            Synchronize Intent to Runtime.
                    ${Q_COLOR_BLUE}deploy${Q_COLOR_RESET}         -> Dry-run (Preview changes).
                    ${Q_COLOR_BLUE}deploy force${Q_COLOR_RESET}   -> Execute rsync + daemon-reload.

${Q_COLOR_YELLOW}UNIT CONTROL${Q_COLOR_RESET}
  ${Q_COLOR_GREEN}start | stop | restart${Q_COLOR_RESET}   <unit>
  ${Q_COLOR_GREEN}enable | disable${Q_COLOR_RESET}         <unit>
  ${Q_COLOR_GREEN}mask | unmask${Q_COLOR_RESET}            <unit>
  
  ${Q_COLOR_GREY}* Note: If <unit> is omitted, interactive selection (fzf) is launched.${Q_COLOR_RESET}

${Q_COLOR_YELLOW}DEBUGGING & TOOLS${Q_COLOR_RESET}
  ${Q_COLOR_GREEN}debug <unit>${Q_COLOR_RESET}      Enter Debug Cycle (Stop -> Disable Restart -> Start -> Logs).
  ${Q_COLOR_GREEN}logs <unit>${Q_COLOR_RESET}       Advanced log viewer (Cleaned JSON output).
  ${Q_COLOR_GREEN}shell${Q_COLOR_RESET}             Enter interactive REPL.
  ${Q_COLOR_GREEN}rd${Q_COLOR_RESET}                Fast alias for 'systemctl --user daemon-reload'.

${Q_COLOR_YELLOW}OPTIONS${Q_COLOR_RESET}
  -h, --help        Show this help message.
  -v, --version     Show version information.

${Q_COLOR_YELLOW}ENVIRONMENT${Q_COLOR_RESET}
  Source (Intent):  ${Q_SRC_DIR}
  Target (Config):  ${Q_CONFIG_DIR}
  Socket:           ${Q_PODMAN_SOCK}

EOF
}