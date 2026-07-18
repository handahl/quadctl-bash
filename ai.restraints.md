---
ai.restraints.md
2026-03-04 — restored to repo root 2026-07-18 (recovered from history_archive/.tmp/)
handahl
project quadctl-bash
replaces: ai.restraints.master.md (deleted; git holds all prior versions)
---

# quadctl

- Type: Local-only Bash CLI tool
- Purpose: Coordinate Podman container lifecycle and homelab governance by composing
  systemctl, Podman, and related tooling into a constrained, low-noise operator interface.
- Primary User: Single operator (handahl). Multi-user support is explicitly out of scope.

quadctl exists to reduce cognitive load, command verbosity, and diagnostic noise while
preserving explicit control over system state.

---

## Change Protocol

Any change to quadctl — proposed by human or AI — must be classified as exactly one of:

| Class | Meaning | Approval |
|---|---|---|
| **Clarification** | No behavior change: comments, docs, messages, help text | not required |
| **Refactor** | Behavior-preserving restructuring; tests must still pass | not required |
| **Narrowing** | Reduces scope, removes capability, tightens a check | operator approval |
| **Extension** | Adds capability or surface area | operator approval, checked against Scope Definition |

Rules:

- A change that cannot be classified is rejected.
- Every proposed change must name the section(s) of this document it touches.
  If the author — human or AI — cannot answer that, the change is rejected.
- "Improvement" is not a class. Unsolicited improvement is authority leakage.
- Commit messages state the class: `fix(Narrowing): ...`, `docs(Clarification): ...`.

---

## Node Target Matrix

quadctl must run on all three declared nodes. Tooling constraints must not
assume Fedora Atomic internals where Rocky 9 differs.

| Node       | OS                              | Podman  | systemd | Bash  | Tier       |
|------------|---------------------------------|---------|---------|-------|------------|
| han1       | Universal Blue Aurora (rpm-ostree) | 5.x+ | 258+    | 5.3+  | preferred  |
| han3       | Universal Blue ucore (bootc)    | 5.x+    | 258+    | 5.3+  | preferred  |
| han3-vps   | Rocky Linux 9                   | 4.9.x+  | 252+    | 5.1+  | compat     |

Tier definitions used by deps.bash:
- **preferred**: full feature set, tested versions — no warnings
- **compat**: minimum viable floor — warn, do not fail

---

## Dependency Version Floors

Two-tier model. `check_runtime_dependencies` warns on compat floor, fails only below minimum.

| Tool    | Minimum (fail below) | Preferred (warn below) | Rocky 9 ships | Notes                               |
|---------|----------------------|------------------------|---------------|-------------------------------------|
| Bash    | 5.0.0                | 5.2.0                  | 5.1.8         | Assoc arrays, nameref: bash 4.3+    |
| systemd | 252                  | 255                    | 252           | Quadlet generator first in 252      |
| Podman  | 4.4.0                | 5.0.0                  | 4.9.4         | Quadlet in podman 4.4+              |
| jq      | 1.6                  | 1.7                    | 1.6           | RHEL 9 repos ship 1.6               |
| curl    | 7.76.0               | 8.0.0                  | 7.76.1        | Rocky 9 base ships 7.76.1           |
| rsync   | 3.1.0                | 3.2.0                  | 3.1.3         | No protocol delta for this use      |

Behavior on version mismatch:
- Below **preferred**: `[WARN]` — emit once, continue execution
- Below **minimum**: `[ERR]` — emit, exit 1

---

## Scope Definition

### In Scope

- systemctl --user orchestration: start, stop, restart, enable, disable, mask, unmask
- Automatic application of a personal naming prefix to all managed containers and units
- Fuzzy matching of container and unit identifiers (with explicit confirmation on ambiguity)
- systemd daemon-reload coordination
- Quadlet generator dry-run execution with output filtered to actionable errors
- Matrix-style status view covering: running units, failed units, declared but not realized intent
- Enumeration of active units, available unit files, and intended containers
- Diffing of declared intent vs generated units vs runtime state
- Syncing declarative files from a Git repository into ~/.config/containers/systemd
- Removal of declarative files not present in the authoritative repository
- Image inspection within the matrix view (version tags, SHA pinning, floating tag markers)
- Journalctl log viewing with noise stripping
- Basic system diagnostics (socket availability, generator presence, prerequisite checks)
- Generation of .image Quadlet files from a declarative `images.yaml` manifest (`quadctl image sync`)
- Generation of .volume Quadlet files for Podman-managed (opaque) volumes from a declarative `volumes.yaml` manifest (`quadctl volume sync`)
- Audit of image references: detect missing .image files, `AutoUpdate=registry` combined with `--pull=never`, images without `hanlab-` prefix where expected
- Audit of volume declarations: detect .volume files missing `VolumeName=`, detect `VolumeName=` not matching the filename stem
- Hierarchical tree display of services with their associated .image and .volume dependencies, joined by `VolumeName=` and image reference. Requires `VolumeName=` enforcement (see Audit checks) for correct join resolution.

### Out of Scope

- Container image building (delegated to a separate tool)
- Remote host or multi-node management
- Background daemons or resident services
- Automatic remediation or self-healing behavior
- Cloud orchestration abstractions
- Implicit mutations or side effects
- Management of services or units outside the defined naming prefix
- Registry interaction is limited to inspection and coordination. No publishing or
  credential handling is permitted.

---

## Tech Stack and Dependencies

### Required (latest tested on han3 / han1)

- Bash: 5.3.0 (tested on 5.3.0(1)-release)
- systemd: 258 (tested on 258.3-2.fc43)
- Podman: 5.7.1
- jq: 1.7+
- curl: 8.15.0
- rsync: 3.4.1 (protocol 32)

### Minimum Viable (han3-vps / Rocky 9)

See dependency table above. quadctl must degrade gracefully on compat-tier nodes,
emitting warnings but remaining operational for all declared commands.

### Optional Dependencies

- fzf: 0.67.0 (interactive fuzzy selection)
- GNU awk: 5.3.2
- skopeo: 1.21.0
- ripgrep: 15.1.0
- bat: 0.26.1
- sd: 1.0.0

### Platform Assumptions

- Linux only. GNU userland (grep, sed, awk) — standard on all target nodes.
- No deprecated packages permitted.
- Quadlet generator path must be discovered dynamically — do not hardcode.
  See: `discover_quadlet_generator()` in `src/core/utils.bash`.

---

## Quadlet Generator Path Discovery

The generator binary location differs across distributions and podman versions.
All code that references the generator must use `discover_quadlet_generator()`.

Discovery order:
1. `/usr/lib/systemd/user-generators/podman-user-generator` — Fedora 5.x+ (user units)
2. `/usr/lib/systemd/system-generators/podman-system-generator` — Fedora/Rocky older
3. `/usr/libexec/podman/quadlet` — alternative package layout

If none of the above are found, emit `[ERR]` with remediation hint. Do not assume.

---

## Manifest Files

### images.yaml

Single source of truth for all image references, update policies, and build sources.
Command: `quadctl image sync` — renders `.image` Quadlet files from manifest.

| Field | Description |
|---|---|
| `ref` | Full image reference including registry, name, and tag |
| `auto_update` | `registry` \| `local` \| `none` |
| `pin_digest` | boolean — if true, lock to digest rather than floating tag |
| `build_source` | optional — Forgejo repo path if image is built internally |

Constraint: `--pull=never` and `auto_update: registry` must not be combined.

### volumes.yaml

Declares Podman-managed (opaque) volumes. Config-path bind mounts are not declared
here — they remain as inline `Volume=` in `.container` files.
Command: `quadctl volume sync` — renders `.volume` Quadlet files for `type: podman-managed` entries.

| Field | Description |
|---|---|
| `name` | Volume name. Must match the generated `.volume` filename stem exactly. |
| `type` | `podman-managed` (Mode A, opaque, auto-labeled) \| `bind` (Mode B, explicit path, not generated) |
| `labels` | optional key-value map passed to `Label=` in the `.volume` file |

Constraint: `VolumeName=` in every generated `.volume` file must equal the `name` field.
This is the join key for matrix tree display — the value must be identical across:
the `Volume=` directive in `.container`, `VolumeName=` in `.volume`, and `podman volume ls` output.

`type: bind` entries are documented in `volumes.yaml` for inventory purposes but do not
generate `.volume` files. They remain as inline `Volume=` directives in `.container` files.

---

## Security Model

### Threat Model

Trust boundary: local-only, same-user execution.

Adversaries considered:
- Accidental operator misuse
- Malformed or malicious container metadata
- Invalid or misleading registry metadata
- No hostile multi-user environment assumed; defensive defaults apply.

### Failure Posture

- Fail-fast
- Fail-explicitly
- No silent degradation

### Secrets and Credentials

- quadctl must not read, store, or manipulate secrets
- All credentials are delegated to Podman secrets or systemd-creds
- No direct authentication handling is allowed

### Network Access

- quadctl does not initiate network operations
- Any network activity occurs indirectly via systemctl/Podman

### Authorization and Isolation

- User-level execution only; no sudo or elevated capabilities
- Strict prefix-based authorization for all managed units
- Only declarative quadlet files are mutable: .container, .image, .network, .volume
- No mutation of unrelated unit files or runtime artifacts
- On partial or ambiguous matches, quadctl must halt and request explicit user direction.

---

## Audit & Governance Scope

```yaml
audit:
  scope: static-intent-analysis
  targets:
    - original quadlet files in repo
    - synced quadlet files in generator location
  allowed_checks:
    - resolution of referenced filesystem paths
    - resolution of referenced unit identifiers
    - validation of referenced directive names against known schemas
    - presence of hardening flags
    - detection of hardcoded secrets
    - referenced env files exist
    - keys exist if explicitly declared as required
    # Advisory checks — warn only, never exit non-zero alone
    - z/Z volume flags present in committed intent files
    - Secret=type=env for values that appear to be credentials
    - AutoUpdate=registry combined with PodmanArgs=--pull=never (contradictory directives)
    - missing .image file for an image referenced in a .container file
    - missing VolumeName= in a .volume file
    - VolumeName= value does not match the .volume filename stem
    - missing DropCapability=all
    - SecurityLabelDisable=true present

  audit_posture: "warn, not block — operator is sole decision-maker. No audit check may exit non-zero on advisory findings alone."

  forbidden_assumptions:
    - runtime enforcement
    - security guarantees
    - assert that values are correct
    - expand variables
    - infer defaults

audit_disclaimer:
  statement: >
    Static audit results indicate configuration intent only.
    They shall not be interpreted as proof of effective runtime security.
    Audit checks must fail only when a reference cannot be resolved
    from declared sources of truth.
```

---

## Determinism & Identity Resolution

```yaml
identity_resolution:
  requirements:
    - deterministic
    - reversible
  user-requirements:
    - fuzzy matching
  forbidden:
    - silent fallback
  solution:
    strict mode:
      - machines
      - scripts
      - JSON
      - automation
    interactive mode:
      - humans
      - when explicit
      - opt-in
    must:
      - emit warning on use
      - be trivially removable
failure_policy:
  ambiguity: hard-fail
  messaging:
    must:
      - explain ambiguity
      - enumerate candidates
      - have --debug flag with verbose output
    must_not:
      - auto-select
```

---

## Performance Targets

- General command latency: 200–3000 ms acceptable
- Matrix/status views: up to 5 seconds acceptable
- Progressive rendering preferred; partial results may be displayed as data becomes available
- Logs and diagnostics may trade latency for correctness

---

## UX Expectations

- First meaningful output should appear as early as possible
- Non-interactive by default
- Interactive enhancements enabled only when optional tools (e.g., fzf) are present
- Correctness always supersedes speed

---

## Relationship to hanlab.constraints.json

quadctl implements the container workload intent layer defined in `hanlab.constraints.json`
(kept alongside this document at the repo root).
Where the two documents conflict:

- `hanlab.constraints.json` is authoritative for **homelab policy**
- `ai.restraints.md` is authoritative for **tool behavior**

quadctl must not encode homelab policy — it reads consequences from quadlet files and
reports them. Policy decisions belong to the operator.

---

## Immutable Laws of CoDA

### Hard Constraints (Technical Mandates)

**Package Integrity**: No deprecated or unmaintained dependencies. Required versions
must meet minimum viable floors per node tier. Preferred versions documented.

**API Sanity**: Only stable, documented interfaces of Podman and systemd may be used.

**Schema Sync**: Declarative intent, generated units, and runtime state must be
continuously comparable without ambiguity.

**Scope Preservation**: quadctl must not expand beyond its declared operational domain.

**Path Discovery**: Generator and runtime paths must be discovered dynamically.
Hardcoded distribution-specific paths are a violation.

**Version of Record**: Git is the version of record. No hand-maintained version
strings, dates, or author tags in source file headers. The user-facing version
comes from `git describe --tags`.

### Soft Constraints (Ethical and Design Principles)

**Privacy-by-Design**: No data exfiltration, telemetry, or secret handling.

**Safety-First**: Explicit confirmation over convenience when ambiguity exists.

**Explainability**: All actions must be traceable, inspectable, and justifiable via output.

**Platform Transparency**: When running on compat-tier nodes, quadctl must emit which
tier it detected and what (if any) capability is reduced. The operator decides whether
to proceed.

---

## Known Gaps

Commands declared in help text or planned in scope but not yet implemented.
Each entry is a discrete work item and the only sanctioned backlog. Their presence
here prevents help text from implying capabilities that do not exist.

| Gap | Status |
|---|---|
| `quadctl image sync` | Planned, not implemented |
| `quadctl volume sync` | Planned, not implemented |
| Drift detection layer 0 (git → src) | Not surfaced; matrix covers src → deployed → running |
| Restart-loop detection ("loopy" services) | Planned (td3) |
| Matrix cleanup of ghost/leftover units | Planned (td6) |
| `--json` output for matrix | Planned |
| depends-on / depended-by as true soft wrappers with flag pass-through | Planned — current grep-filtered output is flawed |
| Default prefix `homelab-` vs fleet standard `hanlab-` | Open decision (Narrowing) — see notes/review-2026-07-18.md §4.9 |

Resolved since 2026-03-04: `edit intent <name>` is implemented (interact.bash);
the `quadctl shell` REPL was removed by design — replaced by the `-m/--matrix`
post-command flag.

---

This document is authoritative. Deviations require deliberate revision via the
Change Protocol above. The previous version (ai.restraints.master.md) is superseded.
