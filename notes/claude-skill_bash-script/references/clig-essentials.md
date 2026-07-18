# CLIG Essentials for hanlab Scripts

Distilled from the CLI Guidelines (clig.dev). The full document is the
authoritative source — read it when designing any new user-facing interface.
This file extracts the rules most directly applicable to hanlab bash scripts.

---

## stdout vs stderr — the contract

stdout is for DATA. stderr is for everything else.
This is not a preference. It is the contract that makes pipes work.

- Logs, progress, warnings, errors → stderr
- Machine-readable output, query results → stdout
- If a human and a script might both consume the output, provide --json

A script that mixes human messages into stdout breaks every downstream pipe.

---

## Exit codes

Zero means success. Non-zero means failure. Always.
Map your failure modes to distinct codes so callers can act on them.

```bash
exit 0  # success
exit 1  # general error (unspecified)
exit 2  # usage/argument error
exit 3  # dependency missing
exit 4  # resource not found
```

---

## Color rules (required, not optional)

Three conditions that must disable color:

1. stdout is not a TTY:           [[ ! -t 1 ]]
2. NO_COLOR is set and non-empty: [[ -n "${NO_COLOR:-}" ]]
3. TERM=dumb:                     [[ "${TERM:-}" == "dumb" ]]

Also respect the --no-color flag (and --json, which implies no color).
Apply the decision once in _apply_colors(): color variables hold real escape
bytes (ANSI-C quoting, $'\033[1;31m') when enabled, empty strings when
disabled. Log functions and help heredocs interpolate them unconditionally —
no branching per call, no echo -e. Re-run _apply_colors() from any flag that
flips COLORIZE. See templates.md § LOGGING.

---

## Interactivity rules

Only prompt if stdin is a TTY. Always.

```bash
[[ -t 0 ]] || { log_err "Interactive terminal required."; exit 1; }
```

If a flag can substitute for a prompt, provide it. --yes, --force, --name=X
are all better than blocking on a prompt in a pipeline.

If --no-input is passed, fail immediately with a clear message if required
input is missing. Do not attempt to provide a default silently.

Password prompts: always use read -rs (no echo).

---

## Help text

Every script must respond to -h and --help with:
- One-line description of what the script does
- Usage line
- Flag descriptions
- At least one example invocation
- Where to get more help if something is wrong

Do not print help text on error. Print the error, then suggest --help.

```bash
# Right:
log_err "Missing required argument: --name"
log_err "Run '${SCRIPT_NAME} --help' for usage."
exit 2

# Wrong:
usage
exit 1
```

---

## Error messages

Error messages are documentation. Write them for someone seeing the error
for the first time, not for yourself.

Good:
```
[ERR]  Cannot write to /run/user/1000/han-vault/. Directory may not exist.
       Run: mkdir -p /run/user/1000/han-vault/
```

Bad:
```
[ERR]  Failed.
```

Rules:
- Say what happened
- Say why it happened (if you know)
- Say what to do next (if deterministic)
- Never print a raw bash error message as the final output

Anti-pattern — ${1:?usage...} is prohibited. It looks like a compact guard
but violates the last rule:

```bash
local name="${1:?Usage: creds check <name>}"
# prints: creds: line 42: 1: Usage: creds check <name>   <- raw bash noise
```

Use the explicit guard instead (templates.md § Required-Argument Guard):

```bash
_require_name "${1:-}" "<name>" "check"
# prints: [ERR]  Missing required argument: <name>
#         [ERR]  Run 'creds check --help' for usage.     <- exit 2
```

---

## Flags vs arguments

- Flags (--name, -n) for optional configuration
- Positional arguments for the primary thing being operated on
- Prefer flags over positional arguments for anything beyond one required item
- Keep flags consistent across all han-* scripts:
  --dry-run always means dry run
  --json always means JSON output
  --verbose/-v always means more output
  --quiet/-q always means suppress non-essential output

---

## Dry-run

Any script that modifies state should support --dry-run.
In dry-run mode: print what would happen, exit 0, change nothing.

```bash
if [[ "${DRY_RUN}" == true ]]; then
    log_info "[DRY RUN] Would create: ${TARGET_PATH}"
else
    mkdir -p "${TARGET_PATH}"
fi
```

---

## State changes

Tell the user when you change something. Silence after a state change
looks like a hang or a crash. A one-line confirmation is sufficient.

```bash
log_success "Created database: ${DB_NAME}"
log_success "Registered vault: ${VAULT_NAME} → ${CIPHER_DIR}"
```

---

## Configuration precedence

Apply in this order (highest wins):

1. Flags passed on the command line
2. Environment variables
3. Project-level config file (XDG_CONFIG_HOME/han-<n>/config)
4. System-wide defaults

Never silently use a default that might surprise the user. Log it at INFO
level so they know what value was chosen.

---

## Secrets

Do not read secrets from environment variables in production scripts.
Environment variables are globally readable via /proc/<pid>/environ and
systemctl show on systemd units.

Correct sources:
- Podman secrets: podman secret inspect <n> --showsecret --format '{{.SecretData}}'
- systemd-creds: systemd-creds decrypt --name=<n> <file>
- File passed as flag: --credentials-file /path/to/file (0400 preferred,
  0600 accepted; reject anything more permissive)

---

## Delegation to authoritative tools

If your output is a strict subset of a system tool's output, delegate to
that tool (SKILL.md Pre-Flight #5). Reimplementation drops information and
drifts from upstream.

Delegate on the tool's documented contract, not observed behavior. A
delegation that only works because of ambient environment — a stray .bashrc
export, a coincidental default — is a latent defect that breaks on the next
clean host.

Example: systemd-creds list is documented to read $CREDENTIALS_DIRECTORY.
The correct delegation env-scopes it per invocation:

```bash
CREDENTIALS_DIRECTORY="${STORE}" systemd-creds list --user
```

This honors both the delegation rule and the variable's reserved systemd
runtime contract — never read or export CREDENTIALS_DIRECTORY globally; at
service runtime it points at the plaintext credentials of the current unit.

---

## Idempotency

Scripts that provision or configure should be runnable more than once
without changing the result after the first successful run.

Check before acting:
```bash
if [[ -f "${CONFIG_FILE}" ]]; then
    log_info "Config already exists. Skipping."
else
    # create it
fi
```

---

## Naming

han-* scripts follow: han-<noun> or han-<noun>-<verb>
Subcommands follow: noun verb (e.g. han-vault open, han-vault close)
Flags follow POSIX short (-v) + GNU long (--verbose) convention.
