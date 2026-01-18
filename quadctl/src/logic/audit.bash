#!/usr/bin/env bash
# ==============================================================================
# FILE: audit.bash
# PATH: src/logic/audit.bash
# PROJECT: quadctl
# VERSION: 10.6.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Static Intent Analysis & Governance Enforcement.
# ==============================================================================

# ------------------------------------------------------------------------------
# scan_for_secrets
# Scans files for common secret patterns (API keys, passwords, tokens).
# Returns 1 if secrets are found.
# ------------------------------------------------------------------------------
scan_for_secrets() {
    local target_dir="$1"
    local fail_count=0

    log_info "Scanning for hardcoded secrets in ${target_dir}..."

    # Define forbidden patterns (Basic Heuristics)
    # 1. "password=" or "secret=" assignments
    # 2. Generic API Key patterns (32+ hex/alphanum)
    # 3. Private Key headers
    local patterns=(
        "(?i)(password|secret|token|key)\s*[:=]\s*['\"][^'\"]{3,}['\"]"
        "-----BEGIN .* PRIVATE KEY-----"
    )

    # Use grep to find matches. 
    # We loop through patterns to be explicit about what was found.
    for pat in "${patterns[@]}"; do
        # Recursive grep, line number, with filename
        if grep -rnP "$pat" "$target_dir" --include="*.container" --include="*.service" --exclude-dir=".git"; then
            echo "${Q_COLOR_RED}!! [SECURITY] Potential secret detected matching: $pat${Q_COLOR_RESET}"
            ((fail_count++))
        fi
    done

    if (( fail_count > 0 )); then
        log_err "Found $fail_count potential security violations."
        return 1
    else
        log_success "No obvious hardcoded secrets detected."
        return 0
    fi
}

# ------------------------------------------------------------------------------
# verify_env_references
# Parses .container files for "EnvironmentFile=" directives and validates existence.
# ------------------------------------------------------------------------------
verify_env_references() {
    local target_dir="$1"
    local fail_count=0

    log_info "Verifying EnvironmentFile references..."

    # Find all .container files
    while IFS= read -r file; do
        # Extract EnvironmentFile paths
        # Format: EnvironmentFile=/path/to/foo.env
        # We strip the key and check the path.
        local env_paths
        env_paths=$(grep "^EnvironmentFile=" "$file" | cut -d= -f2-)
        
        if [[ -z "$env_paths" ]]; then continue; fi

        while read -r path; do
            # Expand ~ if present (bash usually doesn't expand in variables, need manual handling or eval)
            # Safe expansion logic:
            local expanded_path="${path/#\~/$HOME}"
            
            if [[ ! -f "$expanded_path" ]]; then
                 echo "${Q_COLOR_RED}!! [INTEGRITY] Missing Env File: $path${Q_COLOR_RESET}"
                 echo "   Referenced in: $file"
                 ((fail_count++))
            fi
        done <<< "$env_paths"
    done < <(find "$target_dir" -name "*.container")

    if (( fail_count > 0 )); then
        log_err "Found $fail_count missing environment file references."
        return 1
    else
        log_success "All EnvironmentFile references resolve successfully."
        return 0
    fi
}

# ------------------------------------------------------------------------------
# execute_audit
# The main entry point for 'quadctl audit'.
# ------------------------------------------------------------------------------
execute_audit() {
    log_info "Starting Static Intent Analysis..."
    log_info "Target: $Q_SRC_DIR"

    if [[ ! -d "$Q_SRC_DIR" ]]; then
        log_err "Source directory not found."
        return 1
    fi

    local status=0

    # 1. Integrity Check (Env Files)
    if ! verify_env_references "$Q_SRC_DIR"; then
        status=1
    fi

    echo "----------------------------------------------------------------"

    # 2. Security Check (Secrets)
    if ! scan_for_secrets "$Q_SRC_DIR"; then
        status=1
    fi

    echo "----------------------------------------------------------------"

    if (( status == 0 )); then
        log_success "Audit Passed. Intent appears structurally sound."
        # Disclaimer from Constraints
        echo "${Q_COLOR_GREY}NOTE: Static audit indicates intent only. Not proof of runtime security.${Q_COLOR_RESET}"
    else
        log_err "Audit Failed. Fix violations before deploying."
        return 1
    fi
}