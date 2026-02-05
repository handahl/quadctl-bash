#!/usr/bin/env bash
# Logic: Audit (Governance)
# Author: SAC-CP (v2.1)
# Description: Static analysis of intent vs reality. Checks for missing secrets/env files.

execute_audit() {
    # Temporarily relax strict mode to allow error accumulation
    set +e
    
    echo_info "Auditing intent directory: $QUADCTL_INTENT_DIR"
    
    local errors=0
    local warnings=0
    
    # 1. Check if Intent Directory Exists
    if [[ ! -d "$QUADCTL_INTENT_DIR" ]]; then
        echo_error "[CRITICAL] Intent directory not found: $QUADCTL_INTENT_DIR"
        return 1
    fi

    # 2. Iterate over .container files
    while IFS= read -r container_file; do
        local unit_name
        unit_name=$(basename "$container_file")
        
        # A. Prefix Check
        if [[ "$unit_name" != "${QUADCTL_ARCH_PREFIX}"* ]]; then
            echo_warn "[STYLE] Unit '$unit_name' does not strictly follow prefix '${QUADCTL_ARCH_PREFIX}'"
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
                        echo_warn "[OPTIONAL] Missing EnvironmentFile in '$unit_name'"
                        echo "   Reference: '$ref' (Marked as optional '-')"
                        ((warnings++))
                    else
                        echo_error "[CRITICAL] Missing EnvironmentFile in '$unit_name'"
                        echo "   Reference: '$ref'"
                        echo "   File does not exist on system"
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
                        echo_error "[CRITICAL] Missing Secret source in '$unit_name'"
                        echo "   Reference: '$resolved_secret'"
                        ((errors++))
                     fi
                fi
             done <<< "$sec_refs"
        fi

    done < <(find "$QUADCTL_INTENT_DIR" -name "*.container" -print0 | xargs -0 -r ls)

    # Summary
    if [[ $errors -gt 0 ]]; then
        echo_error "Audit failed with $errors error(s) and $warnings warning(s)."
        set -e
        return 1
    else
        echo_success "Audit passed. ($warnings warnings)"
        set -e
        return 0
    fi
}