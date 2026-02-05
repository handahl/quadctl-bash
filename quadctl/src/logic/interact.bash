#!/usr/bin/env bash
# UI: Help Documentation
# Author: SAC-CP (v2.1)

ui_show_help() {
    cat <<EOF
quadctl - Podman Container Lifecycle & Governance Tool
v${QUADCTL_VERSION}

USAGE: quadctl [command] [arguments...]

observe
  matrix [all]          Hierarchical reconciliation of intent, units, and containers.
  tree                  Hierarchical view of Pods and Containers.
  shell                 Interactive REPL. (Use 'q shell a' for all units).
  doctor                System diagnostics.
  logs <unit>           Advanced log viewer (cleaned output).
  debug <unit>          Debug Cycle: Stop -> Disable Restart -> Start -> Logs.

govern
  audit                 Static Intent Analysis (Secrets, Env Files, Prefix).
  deploy [force]        Sync intent to runtime.
  migrate               Prefix Governance and Unit Renaming.

units
  start <unit>          Start a unit.
  stop <unit>           Stop a unit.
  restart <unit>        Restart a unit.
  enable|disable        Set auto-start status.

system
  dr (daemon-reload)    Reload systemd manager configuration.

options
  -h, --help            Show this help message.
  -v, --version         Show version information.

paths
  Intent (Source):       $QUADCTL_INTENT_DIR
  Runtime (Config):      $QUADCTL_CONFIG_DIR
  Architecture Prefix:   $QUADCTL_ARCH_PREFIX

EOF
}