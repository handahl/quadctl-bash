ai.restraints.master.mdSystem IdentityName: quadctlType: Local-only Bash CLI toolPurpose: Coordinate Podman container lifecycle and homelab governance by composing systemctl, Podman, and related tooling into a constrained, low-noise operator interface.Primary User: Single operator (author). Multi-user support is explicitly out of scope.quadctl exists to reduce cognitive load, command verbosity, and diagnostic noise while preserving explicit control over system state.Scope DefinitionIn Scopesystemctl --user orchestration: start, stop, restart, enable, disable, statusAutomatic application of a personal naming prefix to all managed containers and unitsFuzzy matching of container and unit identifiers (with explicit confirmation on ambiguity)systemd daemon-reload coordinationQuadlet generator dry-run execution with output filtered to actionable errorsMatrix-style status view covering:Running unitsFailed unitsDeclared but not realized intentEnumeration of:Active units (systemd list-units)Available unit files (systemd list-unit-files)Intended containers declared in ~/.config/containers/systemd regardless of generator successDiffing of declared intent vs generated units vs runtime stateSyncing declarative files from a Git repository into ~/.config/containers/systemdRemoval of declarative files not present in the authoritative repositoryImage inspection within the matrix view, including:Version tagsSHA pinningLatest / floating tag markersJournalctl log viewing with aggressive noise strippingBasic system diagnostics (socket availability, generator presence, prerequisite checks)Out of ScopeContainer image building (explicitly delegated to a separate tool)Remote host or multi-node managementBackground daemons or resident servicesAutomatic remediation or self-healing behaviorCloud orchestration abstractionsImplicit mutations or side effectsManagement of services or units outside the defined naming prefixRegistry interaction is limited to inspection and coordination. No publishing or credential handling is permitted.Tech Stack and Dependency ContractRequired Dependencies (Latest Tested)Bash: >= 5.3.0systemd: 258 (tested on 258.3-2.fc43)Podman CLI: 5.7.1Podman API: 5.7.1quadlet: version as shipped with systemd 258jqcurl: 8.15.0rsync: 3.4.1 (protocol 32)Optional Dependenciesfzf: 0.67.0 (interactive fuzzy selection)GNU awk: 5.3.2skopeo: 1.21.0ripgrep: 15.1.0bat: 0.26.1sd: 1.0.0Platform AssumptionsLinux (tested on Fedora-based systems: Aurora, Bazzite)Kernel versions tested: 6.17.xGNU userland assumptions apply (grep, sed, awk)No deprecated packages are permitted under any circumstance.Security ModelThreat ModelTrust boundary: local-only, same-user executionAdversaries considered:Accidental operator misuseMalformed or malicious container metadataInvalid or misleading registry metadataNo hostile multi-user environment is assumed, but defensive defaults apply.Failure PostureFail-fastFail-explicitlyNo silent degradationSecrets and Credentialsquadctl must not read, store, or manipulate secretsAll credentials are delegated to Podman secrets or systemd-credsNo direct authentication handling is allowedNetwork Accessquadctl does not initiate network operationsAny network activity occurs indirectly via systemctl/PodmanAuthorization and IsolationUser-level execution only; no sudo or elevated capabilitiesStrict prefix-based authorization for all managed unitsOnly declarative quadlet files are mutable:.container.pod.image.network.volumeNo mutation of unrelated unit files or runtime artifactsOn partial or ambiguous matches, quadctl must halt and request explicit user direction.Audit & Governance Scope (Integrated from v0.2)audit:
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
Explicit Audit Limitationaudit_disclaimer:
  statement: >
    Static audit results indicate configuration intent only.
    They shall not be interpreted as proof of effective runtime security.
    Audit checks must fail only when a reference cannot be resolved from declared sources of truth.
Determinism & Identity Resolution (Integrated from v0.2)identity_resolution: 
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
Enforcement Rulefailure_policy:
  ambiguity: hard-fail
  messaging:
    must:
      - explain ambiguity
      - enumerate candidates
      - have --debug flag with verbose output
    must_not:
      - auto-select
Performance TargetsGeneral command latency: 200–3000 ms acceptableMatrix/status views: up to 5 seconds acceptableProgressive rendering is preferred; partial results may be displayed as data becomes availableLogs and diagnostics may trade latency for correctnessUX ExpectationsFirst meaningful output should appear as early as possibleNon-interactive by defaultInteractive enhancements enabled only when optional tools (e.g., fzf) are presentCorrectness always supersedes speed.Immutable Laws of CoDAHard Constraints (Technical Mandates)Package Integrity No deprecated or unmaintained dependencies. Versions must be explicit and tested.API Sanity Only stable, documented interfaces of Podman and systemd may be used.Schema Sync Declarative intent, generated units, and runtime state must be continuously comparable without ambiguity.Scope Preservation quadctl must not expand beyond its declared operational domain.Soft Constraints (Ethical and Design Principles)Privacy-by-Design No data exfiltration, telemetry, or secret handling.Safety-First Explicit confirmation over convenience when ambiguity exists.Explainability All actions must be traceable, inspectable, and justifiable via output.This document is authoritative. Deviations require deliberate revision, not convenience-driven drift.