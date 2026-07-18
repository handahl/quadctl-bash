#!/usr/bin/env bash
##
### help.bash - Usage documentation and version output.
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : (none)
## ==============================================================================================

show_version() {
    # Reason: git is the version of record (ai.restraints.md § Version of Record).
    # --always keeps output useful on an untagged clone; --dirty flags local edits.
    local v=""
    if command -v git >/dev/null 2>&1; then
        v=$(git -C "${INSTALL_ROOT:-.}" describe --tags --always --dirty 2>/dev/null || true)
    fi
    printf "quadctl %s\n" "${v:-unversioned}"
}

show_help() {
    local b="${Q_COLOR_BOLD}"
    local y="${Q_COLOR_YELLOW}"
    local r="${Q_COLOR_RESET}"

    printf "%squadctl%s — Podman/Quadlet lifecycle and governance tool\n\n" "$b" "$r"
    printf "%sUSAGE%s\n" "$b" "$r"
    printf "  quadctl [global flags] <command> [target] [flags]\n\n"

    printf "%sGLOBAL FLAGS%s\n" "$b" "$r"
    printf "  %s-v, --verbose%s     show resolved commands before executing\n" "$y" "$r"
    printf "  %s    --debug%s       resolution trace and raw data\n" "$y" "$r"
    printf "  %s-q, --quiet%s       errors only\n" "$y" "$r"
    printf "  %s-m, --matrix%s      print matrix after command completes\n" "$y" "$r"
    printf "  %s-f, --follow%s      tail logs after start/restart\n" "$y" "$r"
    printf "  %s-h, --help%s        this message\n" "$y" "$r"
    printf "  %s-V, --version%s     version\n\n" "$y" "$r"

    printf "%sOBSERVE%s\n" "$b" "$r"
    printf "  quadctl                  matrix view (standard filter)\n"
    printf "  quadctl matrix           matrix view (explicit)\n"
    printf "  quadctl matrix --all     matrix view including standby/missing units\n"
    printf "  quadctl doctor           system diagnostics\n"
    printf "  quadctl status <unit>    systemctl status passthrough\n"
    printf "  quadctl tree             pod/container hierarchy view\n\n"

    printf "%sUNIT CONTROL%s\n" "$b" "$r"
    printf "  quadctl start   <unit>   start (with pre-flight validation)\n"
    printf "  quadctl stop    <unit>\n"
    printf "  quadctl restart <unit>   restart (with pre-flight validation)\n"
    printf "  quadctl enable  <unit>\n"
    printf "  quadctl disable <unit>\n"
    printf "  quadctl mask    <unit>\n"
    printf "  quadctl unmask  <unit>\n\n"
    printf "  Pass -f/--follow to tail logs from the moment of start/restart:\n"
    printf "    quadctl -f restart vector\n\n"

    printf "%sLOGS%s\n" "$b" "$r"
    printf "  quadctl logs <unit> [lines]    follow logs (default 50 lines)\n"
    printf "  quadctl logs <unit> 200        last 200 lines, then follow\n"
    printf "  quadctl debug <unit>           stop → disable-restart → start → tail\n\n"

    printf "%sINSPECT%s\n" "$b" "$r"
    printf "  quadctl cat <unit>             show deployed Quadlet file\n"
    printf "  quadctl cat intent <unit>      show source intent file\n"
    printf "  quadctl edit intent <unit>     open source intent file in \$EDITOR\n"
    printf "  quadctl depends-on <unit>      list dependencies\n"
    printf "  quadctl depended-by <unit>     list reverse dependencies\n\n"

    printf "%sGOVERNANCE%s\n" "$b" "$r"
    printf "  quadctl audit              static analysis of intent files\n"
    printf "  quadctl deploy             dry-run: show pending file changes\n"
    printf "  quadctl deploy force       apply: sync intent → runtime + daemon-reload\n"
    printf "  quadctl dr                 daemon-reload with generator validation\n\n"

    printf "%sPATHS%s\n" "$b" "$r"
    printf "  Intent (source):   %s\n" "${Q_SRC_DIR:-[unset]}"
    printf "  Runtime (config):  %s\n" "${Q_CONFIG_DIR:-[unset]}"
    printf "  Podman socket:     %s\n" "${Q_PODMAN_SOCK:-[unset]}"
    printf "  Prefix:            %s\n" "${Q_ARCH_PREFIX:-[unset]}"
    printf "  Config file:       %s/quadctl/config\n\n" "${XDG_CONFIG_HOME:-$HOME/.config}"
}
