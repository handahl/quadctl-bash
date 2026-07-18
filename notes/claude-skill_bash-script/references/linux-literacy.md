# Linux Literacy Reference

This file explains the "why" behind tools and standards referenced in the
skill. When a design decision is questioned, the answer is here.

---

## Git vs. Metadata (The Fallacy of Hardcoded IDs)

The anti-pattern: hardcoding static UUIDs or VERSION="1.2.3" strings into
script templates.

Why it fails: when you copy a template to create a new script, you carry over
the metadata. Over time, different scripts claim the same UUID. Developers
never remember to bump version strings in bash files consistently.

The solution: use Git. The commit SHA is your true ID. The tag is your version.
Scripts are execution engines, not databases for their own metadata.
Keep headers lean and functional.

A CI-stamped placeholder (readonly BUILD_REF="@BUILD_REF@", substituted at
packaging time from git describe) does not violate this rule: no human
maintains it, and git remains the single source of truth. What is banned is
hand-maintained metadata. See templates.md § Versioning.

---

## POSIX

What it is: a family of standards (IEEE Std 1003) defining what a Unix-like
system must provide — filesystem layout, system calls, shell behavior.

The shell subset: POSIX specifies `sh`, which runs on every compliant system
(Linux, macOS, BSD, Alpine). It excludes features added by individual shells.

What POSIX sh cannot do:
- Arrays (bash: arr=(a b c))
- pipefail (set -o pipefail is bash-only)
- Process substitution (<(command))
- [[ ]] double-bracket test
- local (available in most shells but not standardized)

Why hanlab doesn't need strict POSIX: Aurora and ucore always have bash.
The portability that POSIX buys is not a scenario hanlab scripts encounter.
The safety features bash adds (pipefail, [[ ]]) outweigh the constraint.

Rule: #!/usr/bin/env bash + set -euo pipefail. End of decision.

---

## XDG Base Directory Specification

What it is: a standard from freedesktop.org (2003) defining five environment
variables that specify where user files live.

Why it exists: before XDG, every program invented its own dotfile.
~/.vim, ~/.ssh, ~/.bash_history — the home directory became a graveyard.
XDG provides a taxonomy.

The five variables:

| Variable        | Meaning                         | Analogy              |
|-----------------|---------------------------------|----------------------|
| XDG_CONFIG_HOME | Settings the user controls      | /etc but for you     |
| XDG_DATA_HOME   | Data your program produces      | A database           |
| XDG_CACHE_HOME  | Recomputable cached data        | Safe to rm -rf       |
| XDG_STATE_HOME  | Logs, history, runtime state    | /var/log but for you |
| XDG_RUNTIME_DIR | Sockets, locks, PIDs            | tmpfs; dies at logout|

Why immutable systems care: on Aurora and ucore, the base system is read-only.
User-space programs cannot write to /etc or /usr. XDG paths are the only
viable target. This makes XDG compliance a requirement, not a preference.

The fallback pattern: always use ${XDG_CONFIG_HOME:-${HOME}/.config} so the
script degrades gracefully in minimal containers or early boot.

---

## shellcheck

What it is: a static analysis tool for bash/sh. It identifies bugs, unsafe
patterns, and style issues without running the script.

Why it matters: bash is permissive. It executes scripts containing serious
bugs without complaint. Quoting errors are syntactically valid bash but
produce wrong behavior when values contain spaces or special characters.

How to run:
```bash
shellcheck scriptname.sh            # all levels
shellcheck -S warning scriptname.sh # warnings and above (sufficient)
```

Common violations:

SC2086 — Unquoted variable (breaks on spaces):
```bash
rm $VAR      # wrong
rm "$VAR"    # right
```

SC2046 — Unquoted command substitution:
```bash
for f in $files; do ...    # wrong
for f in ./*; do ...       # right (use glob when possible)
```

SC2155 — Declare and assign separately (hides exit code):
```bash
local foo=$(cmd)   # wrong — if cmd fails, foo is empty, error is lost
local foo          # right
foo=$(cmd)
```

SC2164 — cd without error check:
```bash
cd /some/dir && do_thing                           # acceptable with set -e
cd /some/dir || { log_err "Cannot cd"; exit 1; }   # explicit is better
```

---

## TTY

What it is: teletypewriter — the historical name for a physical terminal.
Today it means an interactive terminal session: a human at a keyboard.

Why scripts care: stdin/stdout connect to a TTY when run interactively.
When piped or called from another script, they do not. This affects:
- Prompts: `read -p "..."` blocks forever if stdin is a pipe
- Colors: ANSI codes appear as literal characters in log files
- Progress bars: corrupt output in CI / journal logging

How to check:
```bash
[[ -t 0 ]]   # stdin is a TTY  (prompts safe)
[[ -t 1 ]]   # stdout is a TTY (color safe)
[[ -t 2 ]]   # stderr is a TTY
```

The three interactivity models:

Non-interactive: no prompts, no TTY checks needed. All input via flags.

Purely interactive: designed for a human. Fail fast at entry:
```bash
[[ -t 0 ]] || { log_err "Requires interactive terminal."; exit 1; }
```

Mixed-mode: consumes piped data on stdin AND needs to prompt for auth.
Do NOT check [[ -t 0 ]] at entry — it would reject valid piped input.
Instead, read prompts directly from /dev/tty:
```bash
read -r -s -p "Enter secret: " USER_SECRET < /dev/tty
echo "" >&2
```
/dev/tty always refers to the controlling terminal regardless of stdin
redirection, so this is safe even when stdin is a pipe.

---

## NO_COLOR

What it is: a community standard (no-color.org, 2017). When NO_COLOR is set
(to any value, including empty), programs must not output ANSI color codes.

Why it exists: screen readers, log parsers, custom terminal themes, and
accessibility needs all benefit from plain text output.

Implementation:
```bash
[[ -z "${NO_COLOR:-}" ]] || COLORIZE=false
```

Check for empty string, not unset. NO_COLOR= (set to empty string) must
still disable color per the spec.

---

## Exit Codes

When a process terminates, it returns a number (0–255) to its parent.
Zero means success. Any non-zero means failure.

hanlab conventions:
```
0 = success
1 = general / unclassified error
2 = argument/usage error (wrong flags, missing required args)
3 = dependency missing (command not found)
4 = resource not found (file, container, secret)
5 = permission error
```

pipefail: without it, the exit code of `cmd1 | cmd2 | cmd3` is cmd3's code
only. With `set -o pipefail`, it is the first failing command's code.
This is the difference between silent data loss and a visible failure.

---

## Podman Secrets vs Environment Variables

Why not env vars: environment variables are globally readable.
- Any process can read another's via /proc/<pid>/environ
- systemd units expose all env vars via `systemctl show`
- `docker/podman inspect` shows container environment

Rule: scripts read secrets from Podman secrets, systemd-creds, or a
credentials file (--credentials-file path, chmod 0600). Never from
environment variables or positional arguments.

Podman secrets in scripts:
```bash
podman secret inspect my-secret --showsecret --format '{{.SecretData}}'
```

---

## systemd-creds

What it is: a systemd tool for hardware-bound credential storage. Credentials
are encrypted at rest using TPM2, FIDO2, or both. They are decrypted only
when the service unit runs. Appropriate for service-level secrets: API tokens,
database passwords, SMTP credentials.

### Encrypt / decrypt

```bash
# Encrypt for a per-user (rootless) service manager:
systemd-creds encrypt --user --name=my-secret /dev/stdin /path/to/my-secret.cred

# Encrypt for the system service manager:
systemd-creds encrypt --name=my-secret /dev/stdin /path/to/my-secret.cred

# Decrypt (for inspection only — in production, services consume via %d):
systemd-creds decrypt --user my-secret.cred -
```

### The --user / system split — this causes silent failures if wrong

Credentials are scoped at encrypt time, enforced cryptographically.

- A credential encrypted with `--user` can ONLY be decrypted by the per-user
  service manager (the one running as your UID, i.e. `systemctl --user`).
- A credential encrypted without `--user` can ONLY be decrypted by the system
  service manager (root-owned systemd).

Getting this wrong produces a decryption failure at service start with no
obvious error message. Match the flag to who will consume the credential.

### XDG credstore search path (short form vs absolute path)

When `LoadCredentialEncrypted=name` is used without a path in a Quadlet file,
the per-user service manager searches these locations in order:
1. `$XDG_CONFIG_HOME/credstore.encrypted/`
2. `/etc/credstore.encrypted/`
3. `/run/credstore.encrypted/`

If your credential store IS `$XDG_CONFIG_HOME/credstore.encrypted/`, the
short form `LoadCredentialEncrypted=name` is more portable than an absolute
path. It survives home directory changes and works in committed Quadlet files
without hardcoded paths.

Use absolute path only when the file lives outside the default credstore:
```ini
LoadCredentialEncrypted=name:/custom/path/name.cred
```

### File permissions

Credential files must be 0400 (read by owner only). 0600 is flagged as
`INSECURE` by `systemd-creds list`. mktemp creates files at 0600 by default —
always chmod after creation:

```bash
tmp=$(mktemp)
TEMP_FILES+=("${tmp}")
printf '%s' "${secret_value}" | systemd-creds encrypt --user --name="${name}" - "${output_file}"
chmod 0400 "${output_file}"
```

### Consuming credentials in services

At runtime, credentials are available in the directory referenced by `%d`
in unit files, or the path in `$CREDENTIALS_DIRECTORY`. Prefer `%d`:

```ini
[Service]
LoadCredentialEncrypted=db-password

[Container]
Environment=DB_PASSWORD_FILE=%d/db-password
```

`systemd-creds list` to inspect the current credential store:
```bash
# Per-user store:
# Reason: 'list' is documented to read $CREDENTIALS_DIRECTORY — env-scope it
# per invocation. Never export this reserved variable globally (at service
# runtime it points at the plaintext credentials of the current unit); a
# global export makes delegation "work" by accident and corrupts the
# contract for every child process. Delegate on the documented contract,
# not observed behavior (clig-essentials § Delegation).
CREDENTIALS_DIRECTORY="${XDG_CONFIG_HOME}/credstore.encrypted" systemd-creds list --user

# System store:
systemd-creds list
```

---

## Idempotency

What it means: running an operation multiple times produces the same result
as running it once. Safe to retry after a partial failure.

Implementation patterns:
```bash
# Files — check before create:
[[ -f "${TARGET}" ]] || create_it

# Directories — -p is always idempotent:
mkdir -p "${DIR}"

# Podman secrets:
if podman secret inspect "${SECRET_NAME}" &>/dev/null; then
    log_info "Secret '${SECRET_NAME}' already exists. Skipping."
else
    podman secret create "${SECRET_NAME}" -
fi

# systemd units:
systemctl --user is-enabled myservice &>/dev/null || systemctl --user enable myservice
```
