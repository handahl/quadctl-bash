---
name: homelab-quadlet
description: "Use this skill whenever producing, reviewing, or correcting any Quadlet unit file (.container, .volume, .image, .network, .build, .pod, .kube, .artifact) for the hanlab homelab project. Trigger on any request involving: writing a new service container file, producing one-shot migration or init job units, hardening a Quadlet, fixing SELinux labels, reviewing secrets configuration, producing manifest.yaml entries, building local images, declaring pods, or playing Kubernetes YAML via podman kube. Also trigger when the user mentions han3, ucore, quadctl, hanlab-, Traefik, or Podman Quadlet in the context of their homelab. Always read this skill before producing any Quadlet file — it prevents correction passes."
---

# Homelab Quadlet Skill

Produces correct, constraint-compliant Quadlet files for the hanlab project
on the first attempt. The operator (handahl) has specific, non-negotiable
conventions.

## Operator Interaction Rules

Apply all corrections silently. Do not enumerate mistakes found in the
operator's prior files. Just produce the correct output.

---

## Conventions — Apply Always

**Booleans:** `true` / `false` only. Never `0` / `1`.

**Naming:**
- ContainerName: `hanlab-<service>`
- Files: `hanlab-<service>.{container,volume,image,network,pod,kube}`
- VolumeName in .volume: must equal the filename stem (e.g. `hanlab-vaultwarden`)
  This is the join key for `quadctl matrix` — if it doesn't match, the tree breaks.

**Default output:** the `.container` file(s) and a `hanlab-<service>-deployment.md`.
Do not volunteer `.volume`, `.image`, or other files unless explicitly requested.

**No inline comments in `.container` files.** Always use a new line for comments.

**No PodmanArgs= for standard hardening.** Use native Quadlet directives:
- `DropCapability=` not `PodmanArgs=--cap-drop=`
- `NoNewPrivileges=` not `PodmanArgs=--security-opt=no-new-privileges`
- `SecurityLabelType=` not `PodmanArgs=--security-opt label=type:...`
- `PidsLimit=` not `PodmanArgs=--pids-limit=`
- `GroupAdd=keep-groups` not `PodmanArgs=--group-add=keep-groups`

`PodmanArgs=` is permitted only for options with no native Quadlet equivalent.
There are currently NO legitimate uses in the fleet. Before reaching for
PodmanArgs=, check the [Container] options table in podman-systemd.unit(5) —
it almost certainly has a native key.

**SELinux on bind mounts:** use `:z` (shared) or `:Z` (private) per RedHat
convention. No `semanage fcontext` / `restorecon` comment blocks in or
appended to `.container` files.

**No .env files for secrets.** Non-sensitive config → `Environment=`.
Secrets → Secret hierarchy (see below).

---

## Key Ordering Within .container files

Use `## --- Section Name ---` headers to separate logical groups. Omit a
group entirely if it has no content; never leave an empty headed section.

```ini
[Unit]
Description=
Upholds=            ← services that need to be available (list them)
After=              ← same services as Upholds=

# Reference other hanlab quadlets by quadlet filename (hanlab-postgres.container)
# in Wants/Requires/Upholds/After/etc. — the generator translates these to the
# correct .service names. Raw .service names also work but bypass translation.

[Container]
ContainerName=
Pod=                ← only for .container files belonging to a pod: Pod=<podname>.pod
Image=
#AutoUpdate=        ← commented out if disabled for this service
Timezone=           ← default Europe/Berlin

Network=            ← one line per network

PublishPort=        ← one line per port; omit section if not needed

Volume=             ← one line per mount

## --- Environment Variables ---
Environment=        ← as many as necessary; always preferred over .env files
EnvironmentFile=%h/.config/hanlab/<service>/file.env    ← avoid if possible

## --- Health Check ---
HealthCmd=          ← adapt per service; no check configured → omit/comment the ENTIRE block
HealthOnFailure=kill
Notify=healthy
HealthInterval=1m
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=30s

## --- Security / Hardening ---
PidsLimit=
DropCapability=     ← default: all
AddCapability=      ← only if needed; omit line entirely if not
ReadOnly=           ← true where the image tolerates an immutable rootfs; omit otherwise
NoNewPrivileges=    ← default: true
SecurityLabelDisable= ← default: false
GroupAdd=keep-groups  ← only if needed; omit line entirely if not

## --- Labels ---
Label=org.quadctl.routing=https://<service>.handahl.org
Label=org.quadctl.port=
Label=org.quadctl.chain=basic

Label=org.quadctl.flush=true    ← streaming services only (ente-api, garage-s3, immich, paperless)

Label=dev.dozzle.name=
Label=dev.dozzle.group=
```

Multi-route services (ente-web, garage) use named variants:
```ini
Label=org.quadctl.routing.photos=https://photos.ente.handahl.org:3000
Label=org.quadctl.chain.photos=chainEnteWeb
Label=org.quadctl.routing.albums=https://albums.ente.handahl.org:3002
Label=org.quadctl.chain.albums=chainEnteWeb
```

Passthrough — verbatim into generated output (kanidm, immich, cryptpad-ws, seadoc):
```ini
Label=org.quadctl.traefik.passthrough.KEY=VALUE
```

The `[Service]` section follows `[Container]`:

```ini
[Service]
Restart=on-failure
RestartSec=15
TimeoutStartSec=60  ← with Notify=healthy: must exceed HealthStartPeriod + first check (use 120)
TimeoutStopSec=60

## --- Resource Limits ---
Slice=hanlab.slice
CPUWeight=
IOWeight=
MemoryMin=
MemoryHigh=
MemoryMax=

## --- Setup ---
ExecStartPre=       ← /usr/bin/mkdir -p for host paths that must pre-exist, one line per path
                      systemd requires the absolute binary path; bare mkdir fails
```

```ini
[Install]
WantedBy=default.target
# Omit or comment out WantedBy= for services that start only as dependencies
# of other units and do not need to auto-start on their own.
```

---

## Decision Trees

### Which .volume mode? (only when a .volume file is explicitly requested)

```
Does the path need to exist with specific content before first start?
├── YES → inline Volume= bind in .container (config files, not a .volume file)
└── NO → use a .volume file
        Does the backup tool need to target a specific host path?
        ├── YES → Mode B: bind-wrapped .volume (Options=bind,src=<full path>)
        └── NO  → Mode A: podman-managed .volume (no Options=)
                  Auto-labeled container_file_t
                  Preferred for: DB files, LFS blobs, opaque runtime data
```

### Which SELinux approach?

```
Standard bind mount (container reads/writes its own data dir)?
├── YES → Is the source a host-system-owned path?
│         (/var/log, /etc, /home, /run/log/journal, /proc, /sys, /run/containers)
│         ├── YES → NEVER use :Z or :z — see "Host system paths" below
│         └── NO  → Shared with other containers?
│                   ├── YES → :z  (shared label, any container can access on escape)
│                   └── NO  → :Z  (private label, exclusive to this container)
└── NO  → Non-root UID inside container?
          ├── YES → podman unshare chown — document in deployment runbook
          ├── Podman socket passthrough → udica policy
          ├── Host system path (read-only access needed) → udica policy (see below)
          └── Other restricted path → udica policy
```

#### Host system paths

Mounting `/var/log`, `/etc`, `/home`, `/run/log/journal`, or any other path
owned by host-side confined services:

- **NEVER `:Z`** — relabels every file under the path, breaking host SELinux
  for journald, auditd, and any non-container confined service writing there.
- **NEVER `:z`** — same destructive relabel, just shared-label instead of
  exclusive.
- **NEVER `SecurityLabelDisable=true`** unless no other option exists.
  On escape, the container process inherits full UID-level host filesystem
  access (equivalent to `spc_t`).

**Preferred: journald socket instead of /var/log bind**

For log-reading services (VictoriaLogs, vector, Loki), prefer the journald
socket over raw filesystem access. It avoids relabeling entirely:

```ini
Volume=/run/log/journal:/run/log/journal:ro,z
```

Add `DBUS_SYSTEM_BUS_ADDRESS` if the image uses `sd_journal_open`.
Use `:z` (not `:Z`) — journal files are shared with the host journald process.

**When a file bind is unavoidable: udica policy**

```bash
# 1. Create the container (don't run yet)
podman create --name <svc> -v /var/log:/logs:ro <image>

# 2. Generate policy (run from toolbox on ucore if udica not on base system)
podman inspect -l | udica <policy_name>

# 3. Install policy
sudo semodule -i <policy_name>.cil \
  /usr/share/udica/templates/{base_container.cil,log_container.cil}

# 4. Reference in .container file
SecurityLabelType=<policy_name>.process
```

Document the policy name and source container in the service deployment.md.

### Which secret tier?

```
Does the application read from a file path (/run/secrets/<n>)?
├── YES → Secret=name,type=mount  (preferred)
│         Even better: LoadCredentialEncrypted= + Volume=%d:/run/secrets:ro
└── NO  → Does it require an environment variable? (no _FILE convention)
          └── YES → Secret=name,type=env,target=VAR
```

### AutoUpdate policy?

```
Is the image built from forge.handahl.org?
├── YES → AutoUpdate=local
└── NO  → Is it data-migration-sensitive?
          (Forgejo, PostgreSQL major, Kanidm, Vaultwarden, Paperless-ngx)
          ├── YES → comment out: #AutoUpdate=registry
          └── NO  → AutoUpdate=registry
```

---

## Hardening Defaults — Every Container

```ini
## --- Security / Hardening ---
PidsLimit=200
DropCapability=all
NoNewPrivileges=true
SecurityLabelDisable=false
```

PidsLimit guidance: 100 for simple viewers/proxies, 200 default, 300 for
databases and high-concurrency services.

**ReadOnly / ReadOnlyTmpfs semantics (per podman-systemd.unit(5)):**
`ReadOnly=true` is the directive that makes the rootfs immutable.
`ReadOnlyTmpfs=` defaults to `true` and ONLY takes effect when `ReadOnly=true`
is set — it then keeps /dev, /dev/shm, /run, /tmp, /var/tmp as writable tmpfs.
Writing `ReadOnlyTmpfs=true` on its own is a no-op and must not appear as a
hardening line. Adopt `ReadOnly=true` per service where the image tolerates it
(stateless proxies/viewers first); writable data paths come from `Volume=`.

`SecurityLabelDisable=false` is podman's default; it stays in every file as an
explicit, grep-able assertion against accidental `true`.

**Health checks are all-or-nothing.** The tuning keys (`HealthInterval=`,
`HealthTimeout=`, `HealthRetries=`, `HealthStartPeriod=`) fail `podman run` on
images with no HEALTHCHECK when `HealthCmd=` is absent. Either the block is
active with a real `HealthCmd=`, or the whole block is omitted. When active,
pair with:
- `Notify=healthy` — READY is postponed until the first passing check, so
  dependents ordered with `After=` get compose-style `service_healthy`
  semantics. `TimeoutStartSec` must exceed `HealthStartPeriod` + first check.
- `HealthOnFailure=kill` — unhealthy container gets killed; systemd
  `Restart=on-failure` brings it back. Without this, checks observe but never act.

**Other native keys worth knowing:**
- `RunInit=true` — minimal init for signal forwarding / zombie reaping;
  use for Node.js and other multi-process images without a proper PID 1
- `Retry=` / `RetryDelay=` — image pull robustness on flaky networks
- `Mask=` / `Unmask=` — path-level hardening beyond capabilities
- `HealthStartupCmd=` family — a startup probe; cleaner than inflating
  `HealthStartPeriod` for slow-booting services

**DropCapability workflow:** Deploy with `DropCapability=all`. If it fails,
`ausearch -m AVC -ts recent | grep <service>` identifies needed caps.
Add `AddCapability=` with a comment on its own line citing the source. Never
remove `DropCapability=all`. Never leave it commented out.

**Capability reference:**

| Capability | What it allows | Typical need |
|---|---|---|
| `CHOWN` | Change file UID/GID | lsio s6-overlay, init scripts |
| `SETUID` | Switch process UID | lsio s6-overlay, su-exec |
| `SETGID` | Switch process GID | lsio s6-overlay, su-exec |
| `FOWNER` | Bypass permission checks when UID mismatch | init scripts touching /data |
| `DAC_OVERRIDE` | Read/write/exec regardless of mode bits | broad file access at startup |
| `NET_BIND_SERVICE` | Bind to ports < 1024 | Traefik, any port 80/443 |
| `NET_ADMIN` | Network config (routes, iptables) | VPNs, WireGuard |
| `MKNOD` | Create device nodes | some init systems |
| `AUDIT_WRITE` | Write to kernel audit log | PAM-based services |
| `SYS_PTRACE` | ptrace other processes | debuggers; avoid in production |
| `SYS_ADMIN` | Broad — mount, namespaces, etc. | almost never acceptable |

**Known profiles:**
- PostgreSQL: `AddCapability=SETGID SETUID CHOWN FOWNER DAC_OVERRIDE`
- Traefik: `AddCapability=NET_BIND_SERVICE DAC_OVERRIDE`
- Forgejo: `AddCapability=CHOWN SETUID SETGID FOWNER DAC_OVERRIDE NET_BIND_SERVICE`
- Kanidm: none — `DropCapability=all` works; uses `UserNS=keep-id:uid=1000,gid=1000`
- lsio/s6-overlay images: `AddCapability=CHOWN SETGID SETUID FOWNER DAC_OVERRIDE`
  Also requires `NoNewPrivileges=false` — s6-overlay must exec as PUID:PGID

**PUID / PGID on han3 (ucore):**
UID 1000 = `core` system user. `handahl` operator = UID **1001**.
Use `Environment=PUID=1001` / `Environment=PGID=1001` for lsio images.
Do not assume 1000 on han3.

---

## Special Hardware / Namespace Patterns

**Device passthrough (e.g. Zigbee dongle):**
```ini
AddDevice=/dev/ttyUSB0
GroupAdd=keep-groups
SecurityLabelType=zigbee.process
```
`GroupAdd=keep-groups` and `SecurityLabelType=` are the native Quadlet keys —
do not use `PodmanArgs=--group-add=keep-groups` or
`PodmanArgs=--security-opt label=type:...`.

**User namespace pinning (Kanidm pattern):**
```ini
UserNS=keep-id:uid=1000,gid=1000
```
Use when the container image expects a fixed UID that differs from the host
user, and capabilities are not required.

---

## One-Shot Companion Units (migrations, init jobs)

For services shipping a separate migration/predeploy step (AFFiNE, anything
running Prisma/Alembic before the server), model it as a second .container:

```ini
# hanlab-<service>-migrate.container — deltas from the standard template:

[Container]
Exec=               ← the migration command, e.g. sh -c "node ./scripts/predeploy.js"

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=300
# Type=oneshot disables the start timeout by default (infinity) —
# always set TimeoutStartSec explicitly on job units.

[Install]
# WantedBy omitted: started only as a dependency
```

The server unit gates on it:

```ini
[Unit]
After=hanlab-<service>-migrate.service
Requires=hanlab-<service>-migrate.service
```

- `Requires=` (not `Wants=`): a failed migration must abort the server start.
- `RemainAfterExit=yes` keeps the job "active" so `Requires=` doesn't
  re-trigger or tear down the server mid-run.
- Upgrades: `systemctl --user restart hanlab-<service>-migrate` re-executes
  the job against the new image; the restart propagates through `Requires=`
  to the server.
- Job units omit the health block and the `org.quadctl.routing/port/chain`
  labels (nothing to route); keep dozzle labels and `traefik.enable=false`.
- Networks: backend only — never `hanlab-proxy.network`.

---

## Fleet-Wide Drop-In (boilerplate only)

Quadlet searches dash-truncated drop-in directories: every
`hanlab-*.container` also reads `hanlab-.container.d/*.conf`. One file can
carry the non-security boilerplate for the whole fleet:

```ini
# ~/.config/containers/systemd/hanlab-.container.d/10-defaults.conf
[Container]
Timezone=Europe/Berlin
Retry=3
RetryDelay=5s

[Service]
Slice=hanlab.slice
```

Rules:
- Boilerplate only. Security keys (`DropCapability=`, `NoNewPrivileges=`,
  `PidsLimit=`, SELinux options) stay per-file — a unit rsynced to a host
  missing the drop-in must not silently lose its hardening.
- The drop-in directory is part of the intent tree; verify `quadctl deploy`
  carries directories, not just `*.container` files.
- Per-unit keys override the drop-in where both are set.

---

## Labels

Standard label block for every **routed** container:

```ini
## --- Labels ---
Label=org.quadctl.routing=https://SERVICE.handahl.org
Label=org.quadctl.port=PORT
Label=org.quadctl.chain=basic
Label=dev.dozzle.name="Service Display Name"
Label=dev.dozzle.group=GROUP
Label=traefik.enable=false
```

Non-routed units (one-shot jobs, dependency-only backends with no HTTP
surface) omit the three `org.quadctl.*` routing lines and keep the rest.

**`traefik.enable=false`** for all services — routing is handled via
`dynamic-config.yml` (file provider only). Label discovery is not active.

**Dozzle groups:** ipsec, backend, docs, media, home-auto, observability,
utility, dev, ai, logs

**Chains:** basic, oidc, enteWeb, s3, garageAdmin, garageWeb, immich,
kanidm, cryptpad, passthrough, trusted

### Traefik label block (future / reference — not written to .container files today)

```ini
Label=traefik.enable=true
Label=traefik.http.routers.hanlab-SERVICE.rule=Host(`SERVICE.handahl.org`)
Label=traefik.http.routers.hanlab-SERVICE.entrypoints=websecure
Label=traefik.http.routers.hanlab-SERVICE.tls=true
Label=traefik.http.routers.hanlab-SERVICE.middlewares=chainBasic@file
Label=traefik.http.services.hanlab-SERVICE.loadbalancer.server.port=PORT
```

---

## Volume Reference Pattern

```ini
# Persistent data — bind mount, SELinux relabeled inline
Volume=%h/.local/share/hanlab/SERVICE:/container/data:rw,Z

# Config bind — must pre-exist before container start; read-only
Volume=%h/.config/hanlab/SERVICE/config.yml:/etc/SERVICE/config.yml:ro,z

# Podman socket — requires udica policy
Volume=%t/podman/podman.sock:/var/run/docker.sock:ro,z
```

`%h` is the Quadlet specifier for the user's home directory. Never use `~/`.

---

## Networks

Every container must be on at least one named network. Default bridge is
never acceptable.

```
hanlab-proxy.network   → services needing Traefik ingress
hanlab-backend.network → internal service-to-service only
runner-isolated.network → Forgejo runner; no route to backend
```

Databases: `hanlab-backend.network` only. Never on `hanlab-proxy.network`.

---

## Host Path Conventions

| Purpose | Host path | .container specifier |
|---|---|---|
| Persistent data | `~/.local/share/hanlab/<service>/` | `%h/.local/share/hanlab/<service>/` |
| Config files | `~/.config/hanlab/<service>/` | `%h/.config/hanlab/<service>/` |

Never use `/var/lib/hanlab/` — rootless containers on ucore/han3 write to
the user's home tree.

---

## Deploy Workflow

Files are authored on han1 via VSCodium over SSH tunnel, or downloaded and
rsynced:

```bash
rsync -avhP ~/downloads/files/*.container handahl@han3:~/src/containers/intent/
```

On han3:
```bash
quadctl deploy now
podman pull <image>
quadctl start <servicename>
```

DNS rewrite in AdGuardHome **before** `quadctl start`:
```bash
# Web UI: https://han0.handahl.org:3000 → Filters → DNS rewrites
# Or direct edit: /tmp/mnt/han0-entw/entware/etc/AdGuardHome/AdGuardHome.yaml
# under dns.rewrites: - domain: service.handahl.org / answer: <han3-ip>
```

---

## Traefik dynamic-config.yml — Manual Updates Required

File provider only (`providers.file` in traefik.yml). For each new service
add to `~/.config/hanlab/traefik/dynamic-config.yml`:

```yaml
# under http.routers:
  service-name:
    rule: "Host(`service.handahl.org`)"
    service: "service-name-service"
    middlewares: ["chainBasic"]
    tls: {}

# under http.services:
  service-name-service:
    loadBalancer:
      servers: [{url: "http://hanlab-SERVICE:PORT"}]
```

---

## Quick Reference — Common Mistakes to Avoid

| Wrong | Correct |
|---|---|
| `Volume=/var/log/...:/logs:Z` | udica policy; never relabel host system paths |
| `Volume=/var/log/...:/logs:z` | udica policy or journald socket instead |
| `SecurityLabelDisable=true` for log/host-path access | udica policy (preserves SELinux confinement) |
| `SecurityLabelDisable=true` | Only if host path is truly unmovable AND shared with host processes AND udica is not feasible |
| `NoNewPrivileges=1` | `NoNewPrivileges=true` |
| `SecurityLabelDisable=0` | `SecurityLabelDisable=false` |
| `ReadOnlyTmpfs=true` as a hardening line | no-op without `ReadOnly=true`; the hardening key is `ReadOnly=true` |
| `PodmanArgs=--cap-drop=ALL` | `DropCapability=all` |
| `PodmanArgs=--group-add=keep-groups` | `GroupAdd=keep-groups` |
| `PodmanArgs=--security-opt label=type:X` | `SecurityLabelType=X` |
| `HealthInterval=` etc. with `HealthCmd` absent | all-or-nothing: active `HealthCmd=` or omit the whole block |
| `HealthCmd=` without `Notify=healthy` + `HealthOnFailure=kill` | add both; otherwise checks observe but never act |
| `ExecStartPre=mkdir -p ...` | `ExecStartPre=/usr/bin/mkdir -p ...` (absolute path) |
| `Type=oneshot` without `TimeoutStartSec=` | set explicitly — oneshot start timeout defaults to infinity |
| `Volume=~/...` | `Volume=%h/...` |
| `/var/lib/hanlab/` paths | `%h/.local/share/hanlab/` paths |
| Bind mount without `:z`/`:Z` | Add `:rw,Z` or `:ro,z` |
| Inline comments in .container body | New line for comments |
| `EnvironmentFile=path/to/.env` for secrets | `Secret=name,type=env,target=VAR` |
| `AutoUpdate=registry` + `PodmanArgs=--pull=never` | Never combine |
| `DropCapability=all` commented out | Always present and active |
| `Environment=PUID=1000` on han3 | `Environment=PUID=1001` (handahl is 1001) |
| Producing `.volume`/`.image` by default | Only on explicit request |
| Starting container before DNS entry exists | AdGuardHome rewrite first |
| `Label=traefik.enable=true` | `Label=traefik.enable=false` (file provider) |
| `Label=org.hanlab.routing=` | `Label=org.quadctl.routing=` |
| Missing `Label=org.quadctl.routing=` | Include in every routed service |
| Routing labels on one-shot job units | Omit `org.quadctl.routing/port/chain`; keep dozzle labels |
| `middlewares: ["chainGlobal", "chainBasic"]` | `middlewares: ["chainBasic"]` (chainGlobal removed) |