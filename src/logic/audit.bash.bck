#!/usr/bin/env bash
# ==============================================================================
# FILE: audit.bash
# PATH: src/logic/audit.bash
# PROJECT: quadctl
# VERSION: 10.6.1
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Static Intent Analysis & Governance Enforcement.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Internal helper to handle systemd/quadlet path specifiers.
# ------------------------------------------------------------------------------

_expand_quadlet_path() {
local raw_path="$1"

Handle %h (systemd home) and ~ (shell home)

local expanded="${raw_path/%h/$HOME}"
expanded="${expanded/#~/$HOME}"
echo "$expanded"
}

# ------------------------------------------------------------------------------
# Scans files for common secret patterns.
# ------------------------------------------------------------------------------

scan_for_secrets() {
local target_dir="$1"
local fail_count=0

# Requirement Check
if ! command -v grep &> /dev/null; then
    log_err "Required tool 'grep' not found."
    return 1
fi

log_info "Scanning for hardcoded secrets in ${target_dir}..."

local patterns=(
    "(?i)(password|secret|token|key)\s*[:=]\s*['\"][^'\"]{3,}['\"]"
    "-----BEGIN .* PRIVATE KEY-----"
)

for pat in "${patterns[@]}"; do
    if grep -rnP "$pat" "$target_dir" --include="*.container" --include="*.service" --exclude-dir=".git"; then
        echo -e "${Q_COLOR_RED}!! [SECURITY] Potential secret detected matching: $pat${Q_COLOR_RESET}"
        ((fail_count++))
    fi
done

if (( fail_count > 0 )); then
    log_err "Found $fail_count potential security violations."
    return 1
fi
log_success "No obvious hardcoded secrets detected."
return 0
}

# ------------------------------------------------------------------------------
# Validates EnvironmentFile existence with path expansion.
# ------------------------------------------------------------------------------

verify_env_references() {
local target_dir="$1"
local fail_count=0

log_info "Verifying EnvironmentFile references..."

while IFS= read -r file; do
    local env_paths
    env_paths=$(grep "^EnvironmentFile=" "$file" | cut -d= -f2-)
    
    [[ -z "$env_paths" ]] && continue

    while read -r path; do
        local expanded_path
        expanded_path=$(_expand_quadlet_path "$path")
        
        if [[ ! -f "$expanded_path" ]]; then
             echo -e "${Q_COLOR_RED}!! [INTEGRITY] Missing Env File: $path${Q_COLOR_RESET}"
             echo "   Referenced in: $file"
             ((fail_count++))
        fi
    done <<< "$env_paths"
done < <(find "$target_dir" -name "*.container")

if (( fail_count > 0 )); then
    log_err "Found $fail_count missing environment file references."
    return 1
fi

log_success "All EnvironmentFile references resolve."
return 0
}

# ------------------------------------------------------------------------------
# Checks Podman secrets. Interactive only if TTY is present.
# ------------------------------------------------------------------------------

verify_runtime_secrets() {
local target_dir="$1"
local fail_count=0

# Dependency Check
if ! command -v podman &> /dev/null; then
    log_err "Podman not found. Cannot verify runtime secrets."
    return 1
fi

log_info "Verifying Podman Secret existence..."

while read -r line; do
    local secret_def="${line#Secret=}"
    local secret_name="${secret_def%%,*}"
    
    [[ -z "$secret_name" ]] && continue

    if ! podman secret exists "$secret_name"; then
        echo -e "${Q_COLOR_RED}!! [RUNTIME] Missing Podman Secret: $secret_name${Q_COLOR_RESET}"
        ((fail_count++))
        
        # Interactive Fix Logic (Check for TTY)
        if [[ -t 0 ]]; then
            echo -n "   > Generate random 32-byte key for '$secret_name'? (y/N): "
            read -r choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if command -v openssl &> /dev/null; then
                    if openssl rand -base64 32 | podman secret create "$secret_name" -; then
                        echo -e "      ${Q_COLOR_GREEN}✔ Created.${Q_COLOR_RESET}"
                        ((fail_count--))
                    fi
                else
                    log_err "openssl not found. Cannot generate key."
                fi
            fi
        fi
    fi
done < <(grep -h "^Secret=" "$target_dir"/*.container 2>/dev/null || true)

return $(( fail_count > 0 ? 1 : 0 ))


}

# ------------------------------------------------------------------------------
# Validates host directory existence for volume mounts.
# ------------------------------------------------------------------------------

verify_runtime_volumes() {
local target_dir="$1"
local fail_count=0

log_info "Verifying Host Volume paths..."

while read -r line; do
    local vol_def="${line#Volume=}"
    local host_path="${vol_def%%:*}"
    local expanded_path
    expanded_path=$(_expand_quadlet_path "$host_path")
    
    # Filter: Skip non-absolute paths (named volumes) and sockets
    [[ "$expanded_path" != /* ]] && continue
    [[ "$expanded_path" == *.sock ]] && continue

    if [[ ! -d "$expanded_path" ]]; then
         echo -e "${Q_COLOR_RED}!! [RUNTIME] Missing Host Directory: $expanded_path${Q_COLOR_RESET}"
         ((fail_count++))
         
         if [[ -t 0 ]]; then
             echo -n "   > Create directory? (y/N): "
             read -r choice
             if [[ "$choice" =~ ^[Yy]$ ]]; then
                if mkdir -p "$expanded_path"; then
                    echo -e "      ${Q_COLOR_GREEN}✔ Created.${Q_COLOR_RESET}"
                    ((fail_count--))
                fi
             fi
         fi
    fi
done < <(grep -h "^Volume=" "$target_dir"/*.container 2>/dev/null || true)

return $(( fail_count > 0 ? 1 : 0 ))


}

# ------------------------------------------------------------------------------
# Main entry point.
# ------------------------------------------------------------------------------

execute_audit() {
log_info "Starting Static Intent Analysis & Runtime Verification..."

# Ensure Q_SRC_DIR is set (Defaulting to XDG if missing for portability)
local target="${Q_SRC_DIR:-$HOME/.config/containers/systemd}"

if [[ ! -d "$target" ]]; then
    log_err "Target directory not found: $target"
    return 1
fi

local status=0

verify_env_references "$target" || status=1
echo "----------------------------------------------------------------"
scan_for_secrets "$target" || status=1
echo "----------------------------------------------------------------"
verify_runtime_secrets "$target" || status=1
echo "----------------------------------------------------------------"
verify_runtime_volumes "$target" || status=1
echo "----------------------------------------------------------------"

if (( status == 0 )); then
    log_success "Audit Passed. Intent matches runtime state."
else
    log_err "Audit Failed. Unresolved discrepancies exist."
    return 1
fi


}