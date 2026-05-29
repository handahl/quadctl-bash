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

execute_audit() {
    # Temporarily relax strict mode to allow error accumulation
    set +e
    
    log_info "auditing intent directory: $Q_SRC_DIR"
    
    local errors=0
    local warnings=0
    
    # 1. Check if Intent Directory Exists
    if [[ ! -d "$Q_SRC_DIR" ]]; then
        log_err "intent directory not found: $Q_SRC_DIR"
        return 1
    fi

    # 2. Iterate over .container files
    while IFS= read -r container_file; do
        local unit_name
        unit_name=$(basename "$container_file")
        
        # A. Prefix Check
        if [[ "$unit_name" != "${Q_ARCH_PREFIX}"* ]]; then
            log_warn "naming format for unit '$unit_name' does not follow prefix pattern: '${Q_ARCH_PREFIX}'"
            ((warnings++))
        fi

        # B. EnvironmentFile Check
        # Regex: Start of line, optional whitespace, literal "EnvironmentFile="
        local env_refs
        env_refs=$(grep -E "^\s*EnvironmentFile=" "$container_file")
        
        if [[ -n "$env_refs" ]]; then
            while IFS= read -r line; do
                # Extract value part (everything after the first =)
                local ref="${line#*=}"
                
                # 1. Trim Leading Whitespace
                ref="${ref#"${ref%%[![:space:]]*}"}"
                
                # 2. Trim Trailing Whitespace
                ref="${ref%"${ref##*[![:space:]]}"}"
                
                # 3. Handle Optional Prefix (-)
                local is_optional=false
                if [[ "$ref" == -* ]]; then
                    is_optional=true
                    ref="${ref:1}" # Strip the dash
                fi

                # 4. Resolve %h to $HOME
                local resolved_path="${ref//%h/$HOME}"
                
                # 5. Check existence
                if [[ ! -f "$resolved_path" ]]; then
                    if [[ "$is_optional" == "true" ]]; then
                        log_warn "missing optional EnvironmentFile in '$unit_name'"
                        echo "   reference: '$ref' (marked as optional '-')"
                        ((warnings++))
                    else
                        log_err "missing necessary EnvironmentFile in '$unit_name'"
                        echo "   reference: '$ref'"
                        echo "   file does not exist on system"
                        ((errors++))
                    fi
                fi
            done <<< "$env_refs"
        fi

        # C. Secret Check
        local sec_refs
        sec_refs=$(grep -E "^\s*Secret=" "$container_file" | cut -d= -f2-)
        if [[ -n "$sec_refs" ]]; then
             while IFS= read -r ref; do
                if [[ "$ref" == /* || "$ref" == %h* ]]; then
                     local resolved_secret="${ref//%h/$HOME}"
                     resolved_secret=$(echo "$resolved_secret" | cut -d, -f1)
                     
                     if [[ ! -e "$resolved_secret" ]]; then
                        log_err "missing necessary secret source in '$unit_name'"
                        echo "   reference: '$resolved_secret'"
                        ((errors++))
                     fi
                fi
             done <<< "$sec_refs"
        fi

    done < <(find "$Q_SRC_DIR" -name "*.container" -print0 | xargs -0 -r ls)

    # Summary
    if [[ $errors -gt 0 ]]; then
        log_err "audit failed with $errors error(s) and $warnings warning(s)."
        set -e
        return 1
    else
        echo "audit passed. ($warnings warnings)"
        set -e
        return 0
    fi
}