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

    log_info "auditing intent directory: $Q_SRC_DIR"

    if [[ ! -d "$Q_SRC_DIR" ]]; then
        log_err "intent directory does not exist: $Q_SRC_DIR"
        return 1
    fi

    # Find all quadlet files (*.container, *.pod, *.image, *.network, *.volume)
    local quadlet_files
    quadlet_files=$(find "$Q_SRC_DIR" -maxdepth 2 -type f \( -name "*.container" -o -name "*.pod" -o -name "*.image" -o -name "*.network" -o -name "*.volume" \) 2>/dev/null | sort || true)

    if [[ -z "$quadlet_files" ]]; then
        log_warn "no quadlet files found in $Q_SRC_DIR"
        return 0
    fi

    # Process each quadlet file
    while IFS= read -r quadlet_file; do
        local filename
        filename=$(basename "$quadlet_file")
        local line_no=0

        # CHECK 1: Naming Prefix Governance
        if [[ ! "$filename" =~ ^${Q_ARCH_PREFIX} ]]; then
            log_err "naming format for '$filename' does not follow prefix pattern: '$Q_ARCH_PREFIX'"
            echo "   expected: ${Q_ARCH_PREFIX}${filename}" >&2
            echo "   set QUADCTL_PREFIX to override the expected prefix" >&2
            has_errors="true"
            ((error_count++))
        fi

        # READ file line by line for inline checks
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_no++))

            # CHECK 2: Hardcoded Secrets Detection
            # Patterns: API keys, passwords, tokens (common keywords)
            if [[ "$line" =~ (password|secret|token|api.?key|apikey|auth|credential|private.?key|privatekey)=[\"\']*[A-Za-z0-9] ]]; then
                log_warn "[SECURITY] hardcoded secret found in '$filename' at line $line_no:"
                echo "   $line" >&2
                log_info "   secrets can be managed by podman secrets or systemd-creds" >&2
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
                        log_warn "missing EnvironmentFile in '$filename' at line $line_no:"
                        echo "   reference: $env_file" >&2
                        echo "   file does not exist on system" >&2
                        has_errors="true"
                        ((error_count++))
                    fi
                done
            fi

        done < "$quadlet_file"

    done <<< "$quadlet_files"

    if [[ "$has_errors" == "true" ]]; then
        log_err "audit failed with $error_count error(s). recommended to fix all issues before deploying"
        return 1
    fi

    log_success "audit passed: intent directory is compliant."
    return 0
}

execute_deploy() {
    local mode="${1:-dry-run}"
    local force_flag="false"
    local now_flag="false"

    [[ "$mode" == "force" ]] && force_flag="true"
    [[ "$mode" == "now" ]]   && now_flag="true"

    log_info "starting deployment in mode: $mode"

    # --- STAGE 1: AUDIT ---
    if ! audit_directory; then
        if [[ "$force_flag" == "true" ]]; then
            log_warn "audit violations found. being reckless with deploy force."
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
    local generator
    generator=$(discover_quadlet_generator 2>/dev/null) || true

    if [[ -n "$generator" && -x "$generator" ]]; then
        local output
        output=$("$generator" --user --dryrun 2>&1 || true)

        # Use your portable search logic here
        if [[ -z "$output" ]]; then
            log_success "quadlet generator runs succesfull. all units validated."
        elif echo "$output" | search_pattern "No files parsed" >/dev/null; then
            log_err "quadlet generator run fails. no new units validated."
            [[ "$force_flag" == "false" ]] && return 1
        elif echo "$output" | search_pattern "Warning|error|converting" >/dev/null; then
            # Keep your original log message
            log_warn "quadlet generator reports issues."
            echo "$output" | search_pattern "Warning|error|converting"
        fi
    fi

# --- STAGE 4: RELOAD ---
    if [[ "$now_flag" == "true" || "$force_flag" == "true" ]]; then
        check_git_status 
        
        systemctl --user daemon-reload
        
        local validation_failed="false"
        local deployed_files
        deployed_files=$(rsync $rsync_opts --itemize-changes "$Q_SRC_DIR/" "$Q_CONFIG_DIR/" 2>/dev/null | grep -E "^[<>]" | grep -E "\.(container|pod|network|volume)$" | awk '{print $2}' || true)
        
        # Identify the correct runtime directory for systemd generators
        local run_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        
        if [[ -n "$deployed_files" ]]; then
            while IFS= read -r file; do
                if [[ -n "$file" ]]; then
                    local filename=$(basename "$file")
                    local service_filename="${filename%.*}.service"
                    
                    # THE FIX: Generators output to the transient run directory, NOT the config directory
                    local service_path="$run_dir/systemd/generator/$service_filename"
                    
                    if [[ ! -f "$service_path" ]]; then
                        log_err "service file not generated for $filename. Check 'journalctl --user -xe' for Quadlet generator output."
                        validation_failed="true"
                    else
                        local container_mtime=$(stat -c %Y "$Q_CONFIG_DIR/$filename" 2>/dev/null || stat -f %m "$Q_CONFIG_DIR/$filename" 2>/dev/null)
                        local service_mtime=$(stat -c %Y "$service_path" 2>/dev/null || stat -f %m "$service_path" 2>/dev/null)
                        
                        if [[ -n "$container_mtime" && -n "$service_mtime" && "$container_mtime" -gt "$service_mtime" ]]; then
                            log_err "[GEN_FAIL] Generator ran but rejected $filename (container file is newer than service file)."
                            validation_failed="true"
                        fi
                    fi
                fi
            done <<< "$deployed_files"
        fi
        
        if [[ "$validation_failed" == "true" ]]; then
            return 1
        else
            log_success "Deployment applied."
        fi
    fi
}