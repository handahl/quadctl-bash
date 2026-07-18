# quadctl

A constrained, local-only CLI for governing Podman Quadlets and systemd user units
on the hanlab fleet (han1 Aurora, han3/han7 ucore, han3-vps Rocky 9).

quadctl is a **reconciliation viewer with explicitly bounded actuation**: it reveals
the truth across three states — intent on disk, generated units, runtime — and wraps
lifecycle actions thinly around `systemctl --user`, `journalctl`, and the Podman socket.
It observes and reports; it does not orchestrate, remediate, or guess.

Governance: [ai.restraints.md](ai.restraints.md) (tool constitution, includes the
Change Protocol) and [hanlab.constraints.json](hanlab.constraints.json) (homelab policy).

## The two directories

| Role | Path | Rule |
|---|---|---|
| Intent (source of truth) | `~/src/containers/intent` (`$QUADCTL_SRC`) | The only place you edit |
| Runtime config | `~/.config/containers/systemd` | Managed by `quadctl deploy`; hands off |

## Usage

```
quadctl [global flags] <command> [target]
```

Bare `quadctl` prints the matrix — the reconciliation table (DRIFT / STATE / SUB /
UPTIME / HEALTH / VERSION / ROUTING) for all prefixed units.

| Command | Effect |
|---|---|
| `matrix [--all]` | Reconciliation view; `--all` includes infrastructure units |
| `doctor` | System diagnostics (D-Bus link, generator, job queue, failed units) |
| `status <unit>` | `systemctl --user status` passthrough |
| `tree` | Pod/container hierarchy |
| `start/stop/restart <unit>` | Lifecycle with pre-flight validation; `-f` tails logs from the action |
| `enable/disable/mask/unmask <unit>` | Thin systemctl wrappers |
| `logs <unit> [lines]` | journalctl with noise stripping, then follow |
| `debug <unit>` | Stop → disable restart (runtime) → start → tail |
| `cat <unit>` / `cat intent <unit>` | Show generated unit / deployed quadlet file |
| `edit intent <name>` | Open the source intent file in `$EDITOR` |
| `depends-on / depended-by <unit>` | Dependency queries |
| `audit` | Static analysis of intent files (warn-first posture) |
| `deploy` / `deploy now` | Dry-run / apply: rsync intent → runtime + daemon-reload + generator validation |
| `dr` | daemon-reload with stale-generator detection |

Global flags: `-v` verbose, `--debug`, `-q` quiet, `-m` print matrix after command,
`-f` follow logs, `-V` version.

## Install

The entry point is [src/quadctl_shim](src/quadctl_shim). Symlink it into `$PATH`:

```bash
ln -s "$(pwd)/src/quadctl_shim" ~/.local/bin/quadctl
```

Configuration: `~/.config/quadctl/config` (`prefix = hanlab-`, `src_dir = …`,
`verbosity = …`) or the `QUADCTL_PREFIX` / `QUADCTL_SRC` environment variables.
Precedence: flags > env > config > defaults.

Dependencies: bash 5+, systemd 252+, podman 4.4+, jq, curl, rsync
(tiered floors in [ai.restraints.md](ai.restraints.md); compat tier warns, never blocks).

## Development

- Version of record is git — `quadctl -V` reports `git describe`. No version strings in files.
- Every change is classified per the Change Protocol in ai.restraints.md
  (Clarification / Refactor / Narrowing / Extension).
- `bats test/` runs the test suite; shellcheck must stay clean (pre-commit hook in `.githooks/`).

License: [LICENSE.md](LICENSE.md)
