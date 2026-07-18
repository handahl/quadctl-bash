# XDG Base Directory Reference

## What XDG Is

The XDG Base Directory Specification (freedesktop.org) defines where user
files live. It exists to stop every program inventing its own dotfile location.
Aurora and ucore both follow it. Your scripts must too.

## The Five Variables

| Variable | Default | Purpose |
|---|---|---|
| XDG_CONFIG_HOME | ~/.config | User configuration files |
| XDG_DATA_HOME | ~/.local/share | Persistent user data |
| XDG_CACHE_HOME | ~/.cache | Non-essential cached data (can be deleted) |
| XDG_STATE_HOME | ~/.local/state | Logs, history, runtime state across reboots |
| XDG_RUNTIME_DIR | /run/user/$(id -u) | Sockets, locks, short-lived runtime files |

## Canonical Declaration Block

Place immediately after `set -euo pipefail`. Use `:=` to set if unset;
these values are already in the environment on Aurora and ucore.

```bash
readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
readonly XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
```

## Where Each han File Type Lives

| File type | Variable | Example path |
|---|---|---|
| Script configuration | XDG_CONFIG_HOME | ${XDG_CONFIG_HOME}/han-manager/env.conf |
| Registry / metadata | XDG_DATA_HOME | ${XDG_DATA_HOME}/han-scripts/registry.json |
| Script log files | XDG_STATE_HOME | ${XDG_STATE_HOME}/han-log/scriptname.log |
| Temp / sockets | XDG_RUNTIME_DIR | ${XDG_RUNTIME_DIR}/han-scriptname/ |
| Cache (safe to delete) | XDG_CACHE_HOME | ${XDG_CACHE_HOME}/han-scriptname/ |

## Usage Patterns

### Config file
```bash
readonly CONFIG_FILE="${XDG_CONFIG_HOME}/han-<name>/config"
[[ -f "${CONFIG_FILE}" ]] || { log_err "Config not found: ${CONFIG_FILE}"; exit 1; }
```

### State/log directory (create if missing)
```bash
readonly LOG_DIR="${XDG_STATE_HOME}/han-log"
mkdir -p "${LOG_DIR}"
```

### Runtime dir — short-lived, tmpfs on most systems
```bash
readonly RUNTIME_DIR="${XDG_RUNTIME_DIR}/han-<name>"
mkdir -p "${RUNTIME_DIR}"
# Do not persist data here — may vanish at logout
```

### Temp files with cleanup trap
```bash
readonly WORK_DIR="$(mktemp -d "${XDG_RUNTIME_DIR}/han-<name>-XXXXXX")"
TEMP_FILES+=("${WORK_DIR}")
# trap _cleanup EXIT handles deletion
```

## Hard Rules

- Never use ~/. paths or $HOME/.anything directly in scripts
- Never use /tmp/<name> — use XDG_RUNTIME_DIR with mktemp
- Never assume dirs exist — always mkdir -p before writing
- XDG_RUNTIME_DIR lifetime is the login session — do not persist data there
- Use XDG_STATE_HOME (not XDG_DATA_HOME) for logs and history files
