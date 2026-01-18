# **Quadctl: Systemctl and Podman Container Administration Companion**

**Version:** 10.6.0

**Architecture:** SAC-CP (v2.1)

**License:** tbd

## **1\. Introduction**

**Quadctl** is a constrained, local-only command-line interface (CLI) designed to govern the lifecycle of Podman containers and Systemd user units. Unlike traditional orchestrators that abstract away the underlying system, Quadctl acts as an **Epistemic Tool**—its primary function is to reveal the "truth" of the system state by reconciling your declared intent (files on disk) with the actual runtime reality (Systemd/Podman).

It is built on the philosophy of **Constraint-Driven Administration**, reducing cognitive load by enforcing strict naming conventions, directory structures, and safety checks before allowing changes to the system.

## **2\. Core Philosophy**

### **The Epistemic Gap**

In many home-lab and single-node environments, a "drift" occurs between what the administrator *thinks* is running (the config files) and what is *actually* running (orphaned containers, failed units, old images). Quadctl bridges this gap. It does not guess; it observes, reports, and explicitly synchronizes.

### **Cattle, Not Pets**

Quadctl enforces the **XDG Base Directory Specification**. It treats configuration as disposable and reproducible.

* **Intent (Source):** Your Git repository (\~/src/containers/intent). This is the only place you should edit files.  
* **Target (Runtime Config):** The system directory (\~/.config/containers/systemd). Quadctl manages this; you do not.

## **3\. Installation & Requirements**

### **Prerequisites**

Quadctl enforces strict dependency versioning to ensure stability and security:

* **Bash**: 5.3.0 or higher  
* **Systemd**: 258 or higher  
* **Podman**: 5.7.1 or higher  
* **Utilities**: jq, curl, rsync

### **Setup**

Quadctl is distributed as a modular Bash application. The entry point is a shim located at \~/.local/bin/quadctl. Ensure this directory is in your $PATH.

## **4\. Usage & Workflows**

### **The Observability Cycle**

The most common workflow involves checking the system state.

#### **The Matrix View**

The status (or matrix) command provides a high-density table reconciling three data sources: Systemd Unit State, Podman Container State, and Configuration Drift.

quadctl matrix

**Columns:**

* **UNIT:** The service name (minus the architecture prefix).  
* **DRIFT:** Indicates if the file on disk has changed since the service started (synced vs drift).  
* **STATE/SUB:** The systemd lifecycle state (e.g., active, failed).  
* **HEALTH:** The container health check status.  
* **VER:** The image tag currently running.  
* **ROUTING:** Exposed ports or Traefik router rules.

#### **The Tree View**

For a topological perspective, use the tree command. This visualizes the relationship between Pods and their constituent Containers.

quadctl tree

### **The Deployment Cycle**

To make changes, you edit your source files in \~/src/containers/intent, then "push" them to the system.

1. **Audit:** Run quadctl audit to scan your source files for hardcoded secrets (API keys, passwords) and broken environment file references.  
   quadctl audit

2. **Dry Run:** Run quadctl deploy to see what files would be changed (added, modified, or deleted) without actually touching the system.  
   quadctl deploy

3. **Apply:** If the audit passes and the dry-run looks correct, apply the changes. This uses rsync to mirror the source to the target and triggers a systemctl daemon-reload.  
   quadctl deploy force

### **The Control Cycle**

Quadctl provides wrappers around standard systemctl commands to reduce typing. It supports fuzzy matching and interactive selection (via fzf).

Interactive Selection:  
If you run a control command without a target, Quadctl will launch an interactive selector:  
quadctl restart  
\# \> Opens fzf menu to select unit

Direct Targeting:  
You can also target units directly. You do not need to type the full prefix (e.g., hanlab-); Quadctl resolves it automatically.  
quadctl restart traefik  
quadctl logs traefik

## **5\. Command Reference**

### **audit**

Purpose: Static Analysis & Governance.  
Behavior: Scans the Q\_SRC\_DIR for security violations. Fails if hardcoded secrets are detected or if EnvironmentFile directives point to missing files.  
When to use: Always run this before deploy force.

### **deploy \[force\]**

Purpose: State Synchronization.  
Behavior:

* Default: Runs an rsync \--dry-run to show pending file changes.  
* force: Destructively syncs Q\_SRC\_DIR to Q\_CONFIG\_DIR, removes extraneous files, validates Quadlet syntax using the generator, and reloads the systemd daemon.

### **doctor**

Purpose: System Diagnostics.  
Behavior: Checks the health of the Systemd D-Bus connection (latency), the size of the job queue, and verifies that the Podman socket is responsive.

### **tree**

Purpose: Hierarchy Visualization.  
Behavior: Groups containers by their Pod ID. Useful for verifying that sidecar containers are correctly grouped with their primary application.

### **debug \<unit\>**

Purpose: Advanced Troubleshooting.  
Behavior: Enters a specific "Debug Cycle" for a unit:

1. Stops the unit.  
2. Disables automatic restarts (Runtime only) to prevent crash loops.  
3. Prints recent critical errors from the journal.  
4. Starts the unit manually.  
5. Tails the logs immediately.

## **6\. Configuration**

Quadctl is configured via environment variables. These can be set in your .bashrc or shell profile.

| Variable | Default | Description |
| :---- | :---- | :---- |
| QUADCTL\_PREFIX | hanlab- | The naming prefix applied to all your units. Quadctl uses this to filter its view. |
| QUADCTL\_SRC | \~/src/containers/intent | The directory containing your declarative Quadlet files (Source of Truth). |
| XDG\_CONFIG\_HOME | \~/.config | Base path for configuration targets. |
| XDG\_DATA\_HOME | \~/.local/share | Base path for internal tool state. |

## **7\. Troubleshooting**

If Quadctl behaves unexpectedly:

1. **Check Dependencies:** Run quadctl \--version to verify the shim is working.  
2. **Run Doctor:** Run quadctl doctor to check for system-level latency or socket issues.  
3. **Verify Socket:** Ensure the Podman socket is active: systemctl \--user status podman.socket.