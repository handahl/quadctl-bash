# Bash Script Templates

## Header Variants

Choose one per script. Do not mix.
No hand-maintained version strings. No static UUIDs. Git is the version of
record; a CI-stamped @BUILD_REF@ placeholder is permitted (§ Versioning).

| Variant  | Use when |
|----------|----------|
| han-sh   | General purpose tooling, infrastructure helpers, monitoring |
| han-qctl | Quadctl subcommands, Podman/Quadlet control plane |

---

## Template: han-sh

```bash
#!/usr/bin/env bash
## ==============================================================================================
### SCRIPT : <filename.sh>
### SCOPE  : <Aurora|ucore|Both>
### DESC   : <One or two sentences defining the strict boundaries of this script's utility.>
## ==============================================================================================
#
set -euo pipefail

## --- 1. XDG BASE DIRECTORIES ---
readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
readonly XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

## --- 2. CONSTANTS ---
readonly SCRIPT_NAME="${0##*/}"

## --- 3. OUTPUT MODE ---
JSON_OUTPUT=false
[[ -t 1 ]] && COLORIZE=true || COLORIZE=false
[[ -z "${NO_COLOR:-}" ]] || COLORIZE=false
[[ "${TERM:-}" != "dumb" ]] || COLORIZE=false

## --- 4. LOGGING ---
# All log output goes to stderr. stdout is reserved exclusively for data.
# Color variables hold real escape bytes (ANSI-C quoting) when enabled and
# empty strings when disabled. This makes them safe to interpolate anywhere —
# log lines AND help heredocs — with plain printf, no echo -e, no branching.
# _apply_colors() is the single decision point: called once at startup, and
# again from any flag that flips COLORIZE (--json, --no-color).
# Reason: not readonly — late flags must be able to re-apply.
RED='' GREEN='' YELLOW='' BLUE='' RESET=''
_apply_colors() {
    if [[ "${COLORIZE}" == true ]]; then
        RED=$'\033[1;31m'
        GREEN=$'\033[1;32m'
        YELLOW=$'\033[1;33m'
        BLUE=$'\033[1;34m'
        RESET=$'\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' RESET=''
    fi
}
_apply_colors

log_info()    { printf '%s\n' "${BLUE}[INFO]${RESET}  $1" >&2; }
log_success() { printf '%s\n' "${GREEN}[OK]${RESET}    $1" >&2; }
log_warn()    { printf '%s\n' "${YELLOW}[WARN]${RESET} $1" >&2; }
log_err()     { printf '%s\n' "${RED}[ERR]${RESET}   $1" >&2; }

## --- 5. ERROR TRAP ---
_on_error() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    log_err "Failed at line ${line_no} (exit ${exit_code})"
    exit "${exit_code}"
}
trap '_on_error ${LINENO}' ERR

## --- 6. TEMP FILE MANAGEMENT ---
TEMP_FILES=()
_cleanup() {
    if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
        rm -rf "${TEMP_FILES[@]}"
    fi
}
trap _cleanup EXIT

# Usage: tmp=$(mktemp); TEMP_FILES+=("$tmp")
```

---

## Template: han-qctl

Minimal header for quadctl control plane scripts. Logic goes in modules.

```bash
#!/usr/bin/env bash
##
### <filename> - <one-line description>
## ==============================================================================================
### TARGET : Aurora / ucore
### DEPS   : <jq|curl|podman>
## ==============================================================================================
#
set -euo pipefail
```

---

## Section: Dependency Check

Use when >3 deps or the list is computed at runtime.

```bash
## --- DEPENDENCY CHECK ---
require_commands() {
    local missing=()
    for cmd in "$@"; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err "Missing required commands: ${missing[*]}"
        exit 3
    fi
}

# Call early in main():
#   require_commands jq curl podman systemctl
```

---

## Section: TTY Guards & Interactive Input

For purely interactive scripts, fail fast if no TTY is present:

```bash
_require_tty() {
    if [[ ! -t 0 ]]; then
        log_err "${SCRIPT_NAME} requires an interactive terminal."
        log_err "Pass required values as flags instead of interactive prompts."
        exit 1
    fi
}
```

For mixed-mode scripts (piped data to stdin + password prompt), read directly
from /dev/tty to avoid consuming stdin or hanging in a pipeline:

```bash
# Safely read a secret while preserving a data pipe on stdin
read -r -s -p "Enter secret: " USER_SECRET < /dev/tty
echo "" >&2   # newline after silent prompt
```

---

## Section: Argument Parsing (long + short flags)

Includes the --credentials-file pattern to prevent passing secrets via
environment variables or plaintext flags.

```bash
## --- ARGUMENT PARSING ---
usage() {
    # Reason: color vars are escape bytes or empty — heredocs colorize
    # automatically and degrade to plain text when color is disabled.
    cat <<EOF
${BLUE}Usage:${RESET} ${SCRIPT_NAME} [OPTIONS]

<Description of what the script does.>

${BLUE}Options:${RESET}
  -h, --help                    Show this help
  -n, --dry-run                 Show what would happen without doing it
  -c, --credentials-file PATH   Path to credentials file (must be 0400)
      --json                    Output in JSON format (disables color)
      --no-color                Disable color output

${BLUE}Environment:${RESET}
  NO_COLOR    Disable color (standard convention)
  HAN_NODE    Override node identity (default: hostname -s)

EOF
}

DRY_RUN=false
CREDS_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)              usage; exit 0 ;;
        -n|--dry-run)           DRY_RUN=true; shift ;;
        -c|--credentials-file)  CREDS_FILE="$2"; shift 2 ;;
        --json)                 JSON_OUTPUT=true; COLORIZE=false; _apply_colors; shift ;;
        --no-color)             COLORIZE=false; _apply_colors; shift ;;
        --)                     shift; break ;;
        -*)                     log_err "Unknown option: $1"; usage; exit 2 ;;
        *)                      break ;;
    esac
done

# Validate credentials file if provided
if [[ -n "${CREDS_FILE}" ]]; then
    [[ -f "${CREDS_FILE}" ]] || { log_err "Credentials file not found: ${CREDS_FILE}"; exit 4; }
    local perms
    perms="$(stat -c '%a' "${CREDS_FILE}")"
    # Reason: accept 0400 (preferred) or 0600; reject anything more permissive
    [[ "${perms}" == "400" || "${perms}" == "600" ]] \
        || { log_err "Credentials file too permissive: ${CREDS_FILE} (${perms}). Must be 0400 or 0600."; exit 5; }
fi
```

---

## Section: Node Detection

This is the single source of truth for the fleet — SKILL.md points here.
Keep this list current as the fleet changes; one comment per entry
describing OS and role.

```bash
## --- NODE IDENTITY ---
readonly HAN_NODE="${HAN_NODE:-$(hostname -s)}"

case "${HAN_NODE}" in
    han1) ;; # Aurora-dx, KDE Plasma/Wayland, interactive workstation
    han3) ;; # ucore, headless, primary service node (remote site, tailscale)
    han7) ;; # ucore, headless, media library + home-assistant/mqtt/z2m — treat as han3
    *)
        log_warn "Unknown node '${HAN_NODE}'. Proceeding with defaults."
        ;;
esac
```

---

## Section: JSON Output

When --json is passed, emit newline-delimited JSON to stdout. No color.
Use jq for construction; do not hand-roll JSON strings — it is fragile.

```bash
if [[ "${JSON_OUTPUT}" == true ]]; then
    jq -n \
        --arg status "ok" \
        --arg node "${HAN_NODE}" \
        '{status: $status, node: $node}'
fi
```

---

## Section: Credential Consumption Patterns (Quadlet / systemd-creds)

For scripts that write Quadlet files or consume systemd credentials.
See references/linux-literacy.md § systemd-creds for full context.

### Pattern A — LoadCredentialEncrypted + _FILE convention (preferred)

Use when the application supports the `_FILE` suffix convention (reads the
secret from a file path in the env var rather than the value itself).
Docker-compatible apps, Vaultwarden, most twelve-factor apps support this.

```ini
[Service]
LoadCredentialEncrypted=my-secret
# Reason: short form; per-user manager searches
# $XDG_CONFIG_HOME/credstore.encrypted/ automatically

[Container]
Environment=MY_SECRET_FILE=%d/my-secret
# %d expands to /run/credentials/<unit>/ at runtime
```

### Pattern B — Short form vs absolute path

```ini
# Preferred: short form — portable, survives home dir changes
LoadCredentialEncrypted=db-password

# Only when the credential lives outside the default store
LoadCredentialEncrypted=db-password:/custom/path/db-password.cred
```

Use the short form in committed Quadlet files. It is more portable and
does not hardcode filesystem paths that will break if the user is renamed
or the credential store is relocated.

### Pattern C — No _FILE convention available

When the application does not support `_FILE` and requires the secret value
directly in an environment variable, use the Quadlet Secret= directive:

```ini
[Container]
Secret=my-podman-secret,type=env,target=MY_VAR
# Reason: application does not support _FILE convention.
# Podman secret, not systemd-creds. Cross-reference the Quadlet skill
# secret tier decision tree for when to use each.
```

This is a known limitation of the application, not a configuration error.
Prefer Pattern A whenever the application supports it.

---

## Section: Versioning (CI-stamped BUILD_REF)

No hand-maintained version strings. The placeholder is stamped at packaging
time by Forgejo CI: sed -i "s/@BUILD_REF@/$(git describe --tags --always)/".
Git is the version of record; the script only reports what CI stamped.

```bash
## --- VERSION ---
readonly BUILD_REF="@BUILD_REF@"

cmd_version() {
    # Reason: prefix glob, not full-string match — the CI sed would rewrite
    # a literal "@BUILD_REF@" comparison and break the unpackaged fallback.
    if [[ "${BUILD_REF}" == '@BUILD_'* ]]; then
        printf '%s %s\n' "${SCRIPT_NAME}" "dev (unpackaged)"
    else
        printf '%s %s\n' "${SCRIPT_NAME}" "${BUILD_REF}"
    fi
}

# Dispatch: version|-V|--version → cmd_version.
# NEVER -v: reserved fleet-wide for --verbose (clig-essentials, hps precedent).
```

---

## Section: Required-Argument Guard

${1:?usage...} is prohibited — it prints raw bash line-noise
(see clig-essentials.md § Error messages). Use the explicit guard:

```bash
_require_name() {
    # $1 = value to test, $2 = human name of the argument,
    # $3 = subcommand for the --help hint (optional)
    [[ -n "${1:-}" ]] && return 0
    log_err "Missing required argument: ${2}"
    log_err "Run '${SCRIPT_NAME}${3:+ ${3}} --help' for usage."
    exit 2
}

# In a subcommand:
#   cmd_open() {
#       _require_name "${1:-}" "<vault-name>" "open"
#       ...
#   }
```

---

## Subcommand Dispatch Pattern

For scripts with multiple distinct operations, dispatch from main() via
named functions. This avoids monolithic scripts and makes each command
unit-testable in isolation.

```bash
cmd_open()  { ... }
cmd_close() { ... }
cmd_list()  { ... }

main() {
    local subcommand="${1:-}"
    shift || true

    case "${subcommand}" in
        open)   cmd_open "$@" ;;
        close)  cmd_close "$@" ;;
        list)   cmd_list "$@" ;;
        ""|--help|-h) usage; exit 0 ;;
        *)      log_err "Unknown subcommand: ${subcommand}"; usage; exit 2 ;;
    esac
}
```

---

## Composition Order

```
#!/usr/bin/env bash
[header block]
set -euo pipefail

[XDG block]
[constants]
[output mode detection]
[logging: color vars + _apply_colors() + _apply_colors call + log functions]
[error trap]
[temp file management]
[version block — if the tool is CI-packaged]

[dependency check — if >3 deps or dynamic]
[TTY guard — if purely interactive ONLY]

usage()
[cmd_<subcommand>() functions — if subcommand pattern]
[your functions]

main() {
    [argument parsing]
    [require_commands call]
    [node detection — if node-conditional]
    [logic or subcommand dispatch]
}

main "$@"       <- last line, always
```
