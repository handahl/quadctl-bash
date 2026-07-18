#!/usr/bin/env bash
# ==============================================================================
# FILE: migrate.bash
# PATH: src/logic/migrate.bash
# PROJECT: quadctl
# VERSION: 1.0.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Heuristic detection and renaming of Quadlet units to match current prefix.
# ==============================================================================

execute_prefix_migration() {
    local target_dir="$Q_CONFIG_DIR"
    local target_prefix="$Q_ARCH_PREFIX"

    echo ":: [Migration Protocol] Analyzing State..."
    echo "   Target Directory: $target_dir"
    echo "   Desired Prefix:   $target_prefix"
    echo ""

    # 1. GATHER FILES
    # --------------------------------------------------------------------------
    local files=()
    while IFS= read -r f; do
        [[ -e "$f" ]] && files+=("$f")
    done < <(ls "$target_dir"/*.{container,network,volume,pod} 2>/dev/null || true)

    if [[ ${#files[@]} -eq 0 ]]; then
        log_info "No Quadlet files found. System is clean."
        return 0
    fi

    # 2. HEURISTIC ANALYSIS
    # --------------------------------------------------------------------------
    # Attempt to find the most common string before the first hyphen.
    # Logic: ls files -> strip extension -> capture text before first dash -> count
    
    local detected_pattern
    detected_pattern=$(ls "$target_dir" | sed 's/\..*//' | grep "-" | awk -F'-' '{print $1}' | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
    
    local detected_prefix=""
    if [[ -n "$detected_pattern" ]]; then
        detected_prefix="${detected_pattern}-"
    fi

    log_info "Found ${#files[@]} units."
    if [[ -n "$detected_prefix" ]]; then
        log_info "Detected dominant prefix pattern: '${detected_prefix}'"
    else
        log_info "No dominant prefix pattern detected (mixed or flat naming)."
    fi

    # 3. INTERVENTION CHECK
    # --------------------------------------------------------------------------
    if [[ "$detected_prefix" == "$target_prefix" ]]; then
        log_success "System is already aligned with prefix '${target_prefix}'."
        return 0
    fi

    echo ""
    log_warn "Architectural mismatch detected."
    echo "   Current Files: '${detected_prefix}name.container'"
    echo "   Configured:    '${target_prefix}name.container'"
    echo ""
    echo -n ":: Inititate migration? (Renames files in $target_dir) [y/N]: "
    read -r confirm

    if [[ "$confirm" != "y" ]]; then
        echo "   Migration aborted."
        return 0
    fi

    # 4. EXECUTION
    # --------------------------------------------------------------------------
    echo ""
    local count=0
    
    for f in "${files[@]}"; do
        local dir
        dir=$(dirname "$f")
        local filename
        filename=$(basename "$f")
        
        local core_name=""
        
        # Strip old prefix if it exists
        if [[ -n "$detected_prefix" && "$filename" == "$detected_prefix"* ]]; then
            core_name="${filename#$detected_prefix}"
        else
            # If no prefix match, treat whole name as core (unless we want to force-add)
            core_name="$filename"
        fi

        # Construct new path
        local new_filename="${target_prefix}${core_name}"
        local new_path="$dir/$new_filename"

        if [[ "$f" != "$new_path" ]]; then
            mv "$f" "$new_path"
            echo "   [RENAMED] $filename -> $new_filename"
            ((count++))
        else
            echo "   [SKIP]    $filename (Already compliant)"
        fi
    done

    echo ""
    log_success "Migration complete. $count files updated."
    log_info "Recommendation: Run 'systemctl --user daemon-reload' to register changes."
}