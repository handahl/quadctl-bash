---
ai.restraints.master.md
2026-02-19
handahl
project quadctl
---

# quadctl

- Type: Local-only Bash CLI tool
-Purpose: Coordinate Podman container lifecycle and homelab governance by composing systemctl, Podman, and related tooling into a constrained, low-noise operator interface.
- Primary User: Single operator (author). Multi-user support is explicitly out of scope.

quadctl exists to reduce cognitive load, command verbosity, and diagnostic noise while preserving explicit control over system state.

## Scope Definition

### In Scope

- systemctl --user orchestration: start, stop, restart, enable, disable, status
- Automatic application of a personal naming prefix to all managed containers and unitsFuzzy matching of container and unit identifiers (with explicit confirmation on ambiguity)
- systemd daemon-reload coordination
- Quadlet generator dry-run execution with output filtered to actionable errors
- Matrix-style status view covering:Running unitsFailed unitsDeclared but not realized intent
- Enumeration of:
  - Active units (systemd list-units)
  - Available unit files (systemd list-unit-files)
  - Intended containers declared in ~/.config/containers/systemd regardless of generator success
- Diffing of declared intent vs generated units vs runtime state
- Syncing declarative files from a Git repository into ~/.config/containers/systemd
- Removal of declarative files not present in the authoritative repository
- Image inspection within the matrix view, including:
  - Version tags
  - SHA pinning
  - Latest / floating tag markers
- Journalctl log viewing with aggressive noise stripping
- Basic system diagnostics (socket availability, generator presence, prerequisite checks)

### Out of Scope

- Container image building (explicitly delegated to a separate tool)
- Remote host or multi-node management
- Background daemons or resident services
- Automatic remediation or self-healing behavior
- Cloud orchestration abstractions
- Implicit mutations or side effects
- Management of services or units outside the defined naming prefix
- Registry interaction is limited to inspection and coordination. No publishing or credential handling is permitted.

### Tech Stack and Dependencies

- Required Dependencies (Latest Tested)
- Bash: >= 5.3.0
- systemd: 258 (tested on 258.3-2.fc43)
- Podman: 5.7.1
- quadlet: version as shipped with systemd 258
- jqcurl: 8.15.0
- rsync: 3.4.1 (protocol 32)

#### Optional Dependencies
- fzf: 0.67.0 (interactive fuzzy selection)
- GNU awk: 5.3.2
- skopeo: 1.21.0
- ripgrep: 15.1.0
- bat: 0.26.1
- sd: 1.0.0

### Platform Assumptions
- Linux (tested on Fedora-based systems: Aurora, Bazzite, ucore)
Kernel versions tested: 6.17.x
- GNU userland assumptions apply (grep, sed, awk)
- No deprecated packages are permitted under any circumstance.

## Security Model

### Threat Model

Trust boundary: local-only, same-user execution

#### Adversaries considered:
- Accidental operator misuse
- Malformed or malicious container metadataInvalid or misleading registry metadata
- No hostile multi-user environment is assumed, but defensive defaults apply.

#### Failure Posture
- Fail-fast
- Fail-explicitly
- No silent degradation

#### Secrets and Credentials
- quadctl must not read, store, or manipulate secrets
- All credentials are delegated to Podman secrets or systemd-creds
- No direct authentication handling is allowed

#### Network Access
- quadctl does not initiate network operations
- Any network activity occurs indirectly via systemctl/Podman

#### Authorization and Isolation
- User-level execution only; no sudo or elevated capabilities
- Strict prefix-based authorization for all managed units
- Only declarative quadlet files are mutable:
  - .container
  - .pod
  - .image
  - .network
  - .volume
- No mutation of unrelated unit files or runtime artifacts
- On partial or ambiguous matches, quadctl must halt and request explicit user direction.

### Audit & Governance Scope

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
    Audit checks must fail only when a reference cannot be resolved from declared sources of truth.
```

Determinism & Identity Resolution

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

### Performance Targets

- General command latency: 200–3000 ms acceptable
- Matrix/status views: up to 5 seconds acceptable
- Progressive rendering is preferred; partial results may be displayed as data becomes availableLogs and diagnostics may trade latency for correctness

### UX Expectations

- First meaningful output should appear as early as possible
- Non-interactive by default
- Interactive enhancements enabled only when optional tools (e.g., fzf) are present
- Correctness always supersedes speed.

### Immutable Laws of CoDA

#### Hard Constraints (Technical Mandates)

Package Integrity: No deprecated or unmaintained dependencies. Versions must be explicit and tested.

API Sanity: Only stable, documented interfaces of Podman and systemd may be used.

Schema Sync: Declarative intent, generated units, and runtime state must be continuously comparable without ambiguity.

Scope Preservation: quadctl must not expand beyond its declared operational domain.

#### Soft Constraints (Ethical and Design Principles)

Privacy-by-Design: No data exfiltration, telemetry, or secret handling.

Safety-First: Explicit confirmation over convenience when ambiguity exists.

Explainability: All actions must be traceable, inspectable, and justifiable via output.

This document is authoritative. Deviations require deliberate revision, not convenience-driven drift.