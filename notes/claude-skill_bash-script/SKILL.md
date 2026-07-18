---
name: bash-script
description: >
  Use this skill whenever the user asks to write, generate, scaffold, or review
  a shell script or bash script. Trigger on any request involving: creating a
  new script, adding argument parsing to a script, writing a CLI tool in bash,
  adding logging or error handling to an existing script, or producing any
  executable bash file. Also trigger when the user mentions "shellscript",
  "bash helper", "entrypoint script", or asks to "automate X with a script".
  Always read this skill before producing any bash output — it enforces strict
  hanlab coding standards and prevents correction passes.
---

# Bash Script Skill

Produces disciplined, XDG-compliant, CLIG-aware bash scripts for the hanlab
environment (han1: Aurora-dx/KDE workstation; han3, han7: ucore headless
service nodes). Grounded in references/clig-essentials.md. Enforces
shellcheck before returning output.

---

## Pre-Flight Gate (run before writing any code)

Ask yourself — and if ambiguous, ask the user:

1. Does a han-* script already do part of this?
   If yes, is this an extension or a genuinely separate concern?
   Adapting an existing script is always preferred over writing a new one.

2. Which node(s) will this run on?
   - han1: Aurora-dx, Wayland/KDE Plasma, interactive workstation — prompts OK.
           Immutable (rpm-ostree/bootc): no dnf installs; prefer static
           binaries or distrobox + distrobox-export; avoid homebrew.
   - han3: ucore, headless, primary service node — no TTY, output to journal.
           Different physical location from han1; tailscale-connected.
   - han7: ucore, headless — local media library, home-assistant/mqtt/z2m;
           usually co-located with han1. Treat as han3.
   - all:  use HAN_NODE detection (references/templates.md § Node Detection).

   Aurora and ucore are both uBlue immutable distros (rpm-ostree/bootc);
   ucore is a rebase of Fedora CoreOS with batteries included.

3. What is the output contract?
   - Another script consuming this? Support --json or --plain. Data on stdout.
   - Human only? Colored stderr is fine.

4. What is the interactivity model? (determines TTY handling)
   - Non-interactive: driven entirely by flags/args. No prompts.
   - Purely interactive: requires a human. Fails immediately if no TTY.
   - Mixed-mode: consumes piped data via stdin AND prompts for auth/secrets.
     Must read prompts from /dev/tty, not stdin. Do NOT use _require_tty().

5. Does this delegate to an authoritative tool?
   If the output is a strict subset of a system tool's output (e.g.
   systemd-creds list, podman secret ls), delegate via that tool rather than
   reimplementing. Reimplementation drops information and drifts from upstream.
   Delegate on the tool's documented contract, not observed behavior — a
   delegation that only works because of ambient environment (a stray .bashrc
   export) is a latent defect. Example: systemd-creds list reads the store
   via $CREDENTIALS_DIRECTORY per its manpage; env-scope it per invocation
   (see references/clig-essentials.md § Delegation).

---

## Correctness Requirements (hard — violations are defects)

Every script MUST satisfy all of the following. Missing any one is a bug.

 1. #!/usr/bin/env bash must be line 1.
 2. set -euo pipefail must be line 2.
 3. XDG vars declared with fallbacks (see references/xdg.md).
 4. No source <(command) — code injection vector; use static sourced files.
 5. No hardcoded secrets. No secrets via environment variables. Use Podman
    secrets, systemd-creds, or --credentials-file <path>.
 6. TTY guard must match the interactivity model:
    - Purely interactive → _require_tty() at entry; fail fast if no TTY.
    - Mixed-mode → read prompts via /dev/tty per-prompt; NO _require_tty()
      at entry (it would break piped input on stdin).
    - Non-interactive → no prompts, no guards needed.
 7. Logs to stderr, data to stdout — enables piping without pollution.
 8. Respect NO_COLOR, TERM=dumb, and TTY check before colorizing output.
 9. All mktemp files registered in TEMP_FILES array + cleaned via trap EXIT.
10. shellcheck passes at SC2 level before output is returned.
11. systemd-creds encrypt must use --user for per-user (rootless) credentials.
    Omitting it produces a system-scoped credential that the user manager
    cannot decrypt. The distinction is enforced cryptographically, not by
    convention.
12. Credential files must be chmod 0400 after creation. mktemp default of
    0600 produces 'insecure' status in systemd-creds list.
13. No eval on externally influenced data. Build dynamic commands as bash
    arrays and execute the array ("${cmd[@]}"), never string concatenation
    handed to sh -c. See references/command-injection.md.
14. Terminate option parsing with -- before user-supplied paths or values in
    file-operating commands (rm -- "${file}", cp -- "${src}" "${dst}").

shellcheck: Before returning output, verify each function and variable
reference. Most common violations: unquoted variables ("$var" not $var),
[ ] vs [[ ]], missing local declarations, read without -r.

---

## Style Conventions (soft — surface as suggestions, not blocks)

These are hanlab aesthetic standards. Violations are lint, not defects.

- Header: han-sh or han-qctl variant from references/templates.md. Keep it
  lean. No hand-maintained version strings; a CI-stamped @BUILD_REF@
  placeholder is permitted (see templates.md § Versioning). No static UUIDs.
  Git is the version of record.
- Numbered section comments: ## --- 1. SECTION NAME ---
- Log functions: log_info, log_success, log_warn, log_err — colors via
  escape-byte variables + _apply_colors() (templates.md § LOGGING)
- Constants declared readonly
- Subcommand dispatch: prefer cmd_<subcommand>() functions called from main()
  over monolithic scripts when a tool has multiple distinct operations
- main "$@" as the exact last line

---

## Workflow

1. Run Pre-Flight Gate above.
2. Read references/templates.md — select correct header variant and sections.
3. Read references/xdg.md — apply correct path logic.
4. Read references/clig-essentials.md — apply output/error/flag rules.
5. If the script consumes external input (arguments, files, env, stdin),
   read references/command-injection.md — apply data-vs-code rules.
6. Generate the script.
7. Mentally run shellcheck — fix SC2-level issues.
8. Annotate non-obvious decisions with # Reason: comments.

---

## Node Detection Pattern

Single source of truth: references/templates.md § Node Detection. Copy the
case statement from there — do not maintain a second copy here. (The two
copies drifted once already; the fleet changes, duplicates forget.)

Set HAN_NODE in /etc/environment on each host. Do not rely on hostname alone.

---

## Output Contract Patterns

Human-only output (default): colored stderr for logs, plain stdout for data.

Machine-consumable: --json flag, strip color, newline-delimited JSON to stdout.

Both: check --json first; if not set, detect TTY, NO_COLOR, and TERM.

```bash
JSON_OUTPUT=false
[[ -t 1 ]] && COLORIZE=true || COLORIZE=false
[[ -z "${NO_COLOR:-}" ]] || COLORIZE=false
[[ "${TERM:-}" != "dumb" ]] || COLORIZE=false
```

Flags that flip COLORIZE later (--json, --no-color) must re-run
_apply_colors() — see templates.md § LOGGING.

---

## Quality Checklist

Correctness (all must pass before returning output):
- [ ] #!/usr/bin/env bash present
- [ ] set -euo pipefail is line 2
- [ ] XDG vars with :- fallbacks
- [ ] No source <(cmd) patterns
- [ ] No eval on external data; dynamic commands built as arrays
- [ ] -- terminates options before user-supplied positionals
- [ ] Secrets via Podman/systemd-creds/--credentials-file only
- [ ] TTY guard matches interactivity model (pure vs mixed-mode vs none)
- [ ] Mixed-mode prompts use /dev/tty, not stdin
- [ ] mktemp files have trap EXIT cleanup
- [ ] All variable expansions quoted
- [ ] Logs to stderr, data to stdout
- [ ] NO_COLOR, TERM=dumb, and TTY respected
- [ ] systemd-creds encrypt uses --user for per-user credentials
- [ ] Credential files chmod 0400

Style (note if missing, do not block):
- [ ] han-sh or han-qctl lean header (no hand-maintained version string;
      @BUILD_REF@ placeholder OK; no static UUID)
- [ ] Subcommand dispatch via cmd_<n>() functions
- [ ] main "$@" is last line
- [ ] Functions before main()
- [ ] Constants are readonly

---

## References

- references/templates.md         — Header variants, sections, credential patterns
- references/xdg.md               — XDG path logic and fallbacks
- references/clig-essentials.md   — Distilled CLI design rules (from clig.dev)
- references/command-injection.md — Data-vs-code rules: eval ban, argv arrays,
                                    -- termination, PATH/env (from OWASP/CWE-78)
- references/linux-literacy.md    — Why POSIX, XDG, shellcheck, TTY, systemd-creds
