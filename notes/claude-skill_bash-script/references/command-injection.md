# Command Injection Essentials for bash

Distilled from OWASP "Command Injection" and CWE-77/CWE-78 for bash
authorship. The originals are C/PHP/Java-centric; this extracts the rules
that apply when the language you are writing IS the shell.

Core principle: never let data become code. In bash, data becomes code
through four channels: eval, string-built commands re-parsed by a shell,
word splitting of unquoted expansions, and values parsed as options.
Close all four.

---

## 1. eval is prohibited on externally influenced data

Arguments, file contents, env vars, stdin, command output — anything not a
literal in the script is external. eval hands it to the parser: `x; rm -rf ~`
in a value becomes two commands. There is almost always a data-structure
answer (arrays, associative arrays, case dispatch) where eval seems needed.
Related hard rule: no source <(command) — same channel, same defect.

---

## 2. Build commands as arrays, execute as argv

The mental model is Java's Runtime.exec vs C's system(): an argv vector is
executed directly — no shell parse — so `;`, `&&`, `|`, `$( )` inside a
value are inert bytes in a single argument. A concatenated string handed to
`sh -c` or eval is re-parsed, and every metacharacter is live.

```bash
# Wrong — string concatenation, re-parsed by a shell:
cmd="podman run --rm ${image} ${user_args}"
sh -c "${cmd}"

# Right — array construction, direct execution:
cmd=(podman run --rm "${image}")
[[ -n "${extra_mount}" ]] && cmd+=(-v "${extra_mount}")
"${cmd[@]}"
```

This is also the answer for conditionally assembled flags — never build a
flag string and rely on word splitting to separate it.

---

## 3. Quoting is an injection defense, not just shellcheck lint

An unquoted expansion undergoes word splitting and glob expansion — data
partially becomes syntax. `rm ${file}` with file='a b' removes two paths;
with file='*' it removes everything matching. SC2086 is a security finding,
not style.

---

## 4. Terminate option parsing with --

A value beginning with `-` is parsed as an option: file='-rf' turns
`rm "${file}"` into `rm -rf`. Quoting does not help — the receiving command
parses its argv regardless.

```bash
rm -- "${file}"
cp -- "${src}" "${dst}"
grep -e "${pattern}" -- "${files[@]}"    # -e for patterns starting with -
```

Rule: `--` before user-supplied positionals in every file-operating command
that supports it.

---

## 5. Environment and PATH are attacker-influenced in privileged contexts

OWASP examples 3–4: a privileged program trusting $APPHOME, and a relative
`make` hijacked via $PATH. The bash translation: for anything invoked from
systemd units, timers, or with elevated privilege, do not trust inherited
environment for control flow or command resolution. Invoke by absolute path
or verify with command -v; treat env-derived paths as untrusted input.
Existing hanlab rules follow from this channel: no secrets via env, and
CREDENTIALS_DIRECTORY is a reserved runtime contract (clig-essentials
§ Delegation).

---

## 6. Allowlist validation (positive security model)

Define legal input, reject everything else — easier and safer than
enumerating bad characters. The han-creds bare-names invariant is the
canonical instance:

```bash
[[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || { log_err "Invalid name: ${name}"; exit 2; }
```

One regex at intake blocks traversal (../), metacharacters, and
leading-dash option injection simultaneously.

---

References: OWASP Command Injection (owasp.org/www-community/attacks/
Command_Injection); CWE-77; CWE-78.
