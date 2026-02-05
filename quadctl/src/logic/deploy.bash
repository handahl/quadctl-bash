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
    local audit_dir="${Q_SRC_DIR}"
    local has_errors="false"
    local error_count=0

    log_info "Auditing intent directory: $audit_dir"

    if [[ ! -d "$audit_dir" ]]; then
        log_err "Intent directory does not exist: $audit_dir"
        return 1
    fi

    # Find all quadlet files (*.container, *.pod, *.image, *.network, *.volume)
    local quadlet_files
    quadlet_files=$(find "$audit_dir" -maxdepth 1 -type f \( -name "*.container" -o -name "*.pod" -o -name "*.image" -o -name "*.network" -o -name "*.volume" \) 2>/dev/null | sort || true)

    if [[ -z "$quadlet_files" ]]; then
        log_warn "No quadlet files found in $audit_dir"
        return 0
    fi

    # Process each quadlet file
    while IFS= read -r quadlet_file; do
        local filename
        filename=$(basename "$quadlet_file")
        local line_no=0

        # CHECK 1: Naming Prefix Governance
        if [[ ! "$filename" =~ ^${Q_ARCH_PREFIX} ]]; then
            log_err "[CRITICAL] Naming prefix violation: '$filename' does not start with '$Q_ARCH_PREFIX'"
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
                # Exclude common false positives (comments, generic examples)
                if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ (example|placeholder|TODO|FIXME) ]]; then
                    log_err "[CRITICAL] Hardcoded secret detected in '$filename' at line $line_no:"
                    echo "   $line" >&2
                    echo "   Secrets must be managed out-of-band via Podman secrets or systemd-creds" >&2
                    has_errors="true"
                    ((error_count++))
                fi
            fi

            # CHECK 3: Missing Environment Files
            if [[ "$line" =~ EnvironmentFiles?= ]]; then
                # Extract the file path(s)
                local env_paths
                env_paths=$(echo "$line" | sed -E 's/.*EnvironmentFiles?=\s*//; s/[[:space:]]*$//')

                # Split multiple paths (systemd allows multiple)
                IFS=':' read -ra env_array <<< "$env_paths"
                for env_file in "${env_array[@]}"; do
                    # Strip leading '-' (means optional in systemd)
                    env_file="${env_file#-}"
                    # Expand ~ to home directory for validation
                    env_file="${env_file/#\~/$HOME}"

                    if [[ ! -f "$env_file" ]]; then
                        log_err "[CRITICAL] Missing EnvironmentFile in '$filename' at line $line_no:"
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
        log_err "Audit failed with $error_count error(s). Fix all [CRITICAL] issues before deploying."
        return 1
    fi

    log_success "Audit passed: Intent directory is compliant."
    return 0
}

execute_deploy() {
    local mode="${1:-dry-run}"
    local force_flag="false"

    if [[ "$mode" == "now" || "$mode" == "force" ]]; then
        force_flag="true"
    fi

    local source_dir="$Q_SRC_DIR/"
    local target_dir="$Q_CONFIG_DIR/"

    # PRE-FLIGHT: Always run audit first
    if ! audit_directory; then
        log_err "Deploy aborted: Intent audit failed. Run 'quadctl audit' for details."
        return 1
    fi

    # 1. RSYNC
    local rsync_opts="-a --delete --exclude=.git --exclude=README.md --exclude=.DS_Store"

    if [[ "$force_flag" == "false" ]]; then
        rsync_opts+=" --dry-run"
        log_warn "dry-run mode - no changes will be made."
        echo "   use 'deploy now' to apply changes."
    else
        echo ":: [deploy] applying intent..."
    fi

    if [[ ! -d "$source_dir" ]]; then
        log_err "source directory does not exist: $source_dir"
        return 1
    fi

    if command -v rsync &>/dev/null; then
        rsync $rsync_opts "$source_dir" "$target_dir"
    else
        log_err "rsync is missing - cannot deploy."
        return 1
    fi

    # 2. GENERATOR CHECK (Filtered)
    echo ":: validating quadlets..."
    local generator="/usr/lib/systemd/system-generators/podman-system-generator"

    if [[ -x "$generator" ]]; then
        # Use ripgrep if available, fallback to grep
        local filter_tool="grep"
        if command -v rg &>/dev/null; then
            filter_tool="rg"
        fi

        local output
        output=$("$generator" --user --dryrun 2>&1 | ($filter_tool -E "Warning|error" || true))

        if [[ -n "$output" ]]; then
            echo "$output"
            log_warn "Generator reported issues."
        else
            log_success "Generator validation passed."
        fi
    fi

    # 3. RELOAD
    if [[ "$force_flag" == "true" ]]; then
        systemctl --user daemon-reload
        log_success "Deployment applied."
    fi
}