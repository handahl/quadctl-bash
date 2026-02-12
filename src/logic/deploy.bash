#!/usr/bin/env bash
# ==============================================================================
# FILE: deploy.bash
# PATH: src/logic/deploy.bash
# PROJECT: quadctl
# VERSION: 11.8.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Synchronizes Intent (Source) to Runtime (Target) with Strict Audit.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# audit_directory
# Strict static intent analysis. Fails hard on violations.
# Source of truth: Intent directory ($QUADCTL_SRC / ~/src/containers/intent)
# Checks:
#   1. Hardcoded secrets detection
#   2. Missing environment files
#   3. Naming prefix governance
# Returns 0 on pass, 1 on fail (exits process).
# ------------------------------------------------------------------------------
audit_directory() {
    local has_errors="false"
    local error_count=0

    log_info "Auditing intent directory: $Q_SRC_DIR"

    if [[ ! -d "$Q_SRC_DIR" ]]; then
        log_err "Intent directory does not exist: $Q_SRC_DIR"
        return 1
    fi

    # Find all quadlet files (*.container, *.pod, *.image, *.network, *.volume)
    local quadlet_files
    quadlet_files=$(find "$Q_SRC_DIR" -maxdepth 2 -type f \( -name "*.container" -o -name "*.pod" -o -name "*.image" -o -name "*.network" -o -name "*.volume" \) 2>/dev/null | sort || true)

    if [[ -z "$quadlet_files" ]]; then
        log_warn "No quadlet files found in $Q_SRC_DIR"
        return 0
    fi

    # Process each quadlet file
    while IFS= read -r quadlet_file; do
        local filename
        filename=$(basename "$quadlet_file")
        local line_no=0

        # CHECK 1: Naming Prefix Governance
        if [[ ! "$filename" =~ ^${Q_ARCH_PREFIX} ]]; then
            log_err "[VIOLATION] Naming prefix: '$filename' does not start with '$Q_ARCH_PREFIX'"
            echo "   Expected: ${Q_ARCH_PREFIX}${filename}" >&2
            echo "   Set QUADCTL_PREFIX to override the expected prefix" >&2
            has_errors="true"
            ((error_count++))
        fi

        # READ file line by line for inline checks
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_no++))

            # CHECK 2: Hardcoded Secrets Detection
            # Patterns: API keys, passwords, tokens (common keywords)
            if [[ "$line" =~ (password|secret|token|api.?key|apikey|auth|credential|private.?key|privatekey)=[\"\']*[A-Za-z0-9] ]]; then
                log_err "[VIOLATION] Hardcoded secret found in '$filename' at line $line_no:"
                echo "   $line" >&2
                echo "   Secrets should be managed out-of-band via Podman secrets or systemd-creds" >&2
                has_errors="true"
                ((error_count++))
           fi

            # CHECK 3: Missing Environment Files
            if [[ "$line" =~ ^[[:space:]]*[^#\;]*EnvironmentFiles?= ]]; then
                # Extract the file path(s)
                local env_paths
                env_paths=$(echo "$line" | sed -E 's/.*EnvironmentFiles?=\s*//; s/[[:space:]]*$//')

                # Split multiple paths (systemd allows multiple)
                IFS=':' read -ra env_array <<< "$env_paths"
                for env_file in "${env_array[@]}"; do
                    # 1. Strip leading '-'
                    env_file="${env_file#-}"
        
                    # 2. Expand systemd specifiers (The missing piece!)
                    env_file="${env_file//%h/$HOME}"
                    env_file="${env_file//%u/$USER}"
                    
                    # 3. Expand ~ to home directory
                    env_file="${env_file/#\~/$HOME}"

                    if [[ ! -f "$env_file" ]]; then
                        log_err "[VIOLATION] Missing EnvironmentFile in '$filename' at line $line_no:"
                        echo "   Reference: $env_file" >&2
                        echo "   File does not exist on system" >&2
                        has_errors="true"
                        ((error_count++))
                    fi
                done
            fi

        done < "$quadlet_file"

    done <<< "$quadlet_files"

    if [[ "$has_errors" == "true" ]]; then
        log_err "Audit failed with $error_count error(s). Recommended to fix all issues before deploying"
        return 1
    fi

    log_success "Audit passed. Intent directory is compliant."
    return 0
}

execute_deploy() {
    local mode="${1:-dry-run}"
    local force_flag="false"
    local now_flag="false"

    [[ "$mode" == "force" ]] && force_flag="true"
    [[ "$mode" == "now" ]]   && now_flag="true"

    log_info "Starting deployment in mode: $mode"

    # --- STAGE 1: AUDIT ---
    if ! audit_directory; then
        if [[ "$force_flag" == "true" ]]; then
            log_warn "Audit violations found. Overriding with deploy force."
        else
            log_err "or use 'deploy force' to override."
            return 1
        fi
    fi

    # --- STAGE 2: STAGING (RSYNC FIRST) ---
    local rsync_opts="-av --delete --exclude=.git"
    
    if [[ "$now_flag" == "false" && "$force_flag" == "false" ]]; then
        rsync_opts+=" --dry-run"
        log_info "no actual changes will be made, use 'deploy now' to apply changes."
    else
        log_info "deploying intent files..."
    fi

    rsync $rsync_opts "$Q_SRC_DIR/" "$Q_CONFIG_DIR/"

    # --- STAGE 3: GENERATOR VALIDATION ---
    log_info "validating intent files..."
    local generator="/usr/lib/systemd/system-generators/podman-system-generator"

    if [[ -x "$generator" ]]; then
        local output
        output=$("$generator" --user --dryrun 2>&1 || true)

        # Use your portable search logic here
        if [[ -z "$output" ]]; then
            log_success "Quadlet Generator succesfull: All units are valid."
        elif echo "$output" | search_pattern "No files parsed" >/dev/null; then
            log_err "Quadlet Generator fails. No files converted."
            [[ "$force_flag" == "false" ]] && return 1
        elif echo "$output" | search_pattern "Warning|error|converting" >/dev/null; then
            # Keep your original log message
            log_warn "Quadlet Generator fails converting some files:"
            echo "$output" | search_pattern "Warning|error|converting"
        fi
    fi

    # --- STAGE 4: RELOAD ---
    if [[ "$now_flag" == "true" || "$force_flag" == "true" ]]; then
        # Restore your git status reminder
        check_git_status 
        
        systemctl --user daemon-reload
        log_success "Deployment applied."
    fi
}