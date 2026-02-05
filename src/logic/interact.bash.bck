#!/usr/bin/env bash
# ==============================================================================
# FILE: interact.bash
# PATH: src/logic/interact.bash
# PROJECT: quadctl
# VERSION: 1.0.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Interactive commands for viewing and editing Intent vs Runtime.
# ==============================================================================

# ------------------------------------------------------------------------------
# execute_cat
# Usage: quadctl cat [intent] <name>
# ------------------------------------------------------------------------------
execute_cat() {
    local mode="$1"
    local input_name="$2"

    # 1. RUNTIME VIEW (Standard systemctl)
    # --------------------------------------------------------------------------
    if [[ "$mode" != "intent" ]]; then
        # If arg1 wasn't 'intent', it's the name (e.g., 'quadctl cat foo')
        local unit_name="$mode"
        
        echo ":: [Runtime View] Querying systemd for '$unit_name'..."
        
        # Try exact match, then prefix match
        if systemctl --user list-unit-files "${unit_name}*" | grep -q "$unit_name"; then
            systemctl --user cat "$unit_name"
        elif systemctl --user list-unit-files "${Q_ARCH_PREFIX}${unit_name}*" | grep -q "${Q_ARCH_PREFIX}"; then
            echo "   (Resolved to ${Q_ARCH_PREFIX}${unit_name})"
            systemctl --user cat "${Q_ARCH_PREFIX}${unit_name}"
        else
            log_err "Unit '$unit_name' (or '${Q_ARCH_PREFIX}${unit_name}') not found in systemd runtime."
            return 1
        fi
        return 0
    fi

    # 2. INTENT VIEW (Target Directory ~/.config/...)
    # --------------------------------------------------------------------------
    local name="$input_name"
    echo ":: [Intent View] Inspecting Deployed Quadlet..."

    # Search for the file in Q_CONFIG_DIR
    # Priority: Prefix+Name.container -> Name.container -> Other extensions
    local candidates=(
        "${Q_CONFIG_DIR}/${Q_ARCH_PREFIX}${name}.container"
        "${Q_CONFIG_DIR}/${name}.container"
        "${Q_CONFIG_DIR}/${Q_ARCH_PREFIX}${name}.volume"
        "${Q_CONFIG_DIR}/${name}.volume"
        "${Q_CONFIG_DIR}/${Q_ARCH_PREFIX}${name}.network"
        "${Q_CONFIG_DIR}/${name}.network"
    )

    local found=""
    for f in "${candidates[@]}"; do
        if [[ -f "$f" ]]; then found="$f"; break; fi
    done

    if [[ -n "$found" ]]; then
        echo "   File: $found"
        echo "   ------------------------------------------------------------"
        cat "$found"
    else
        log_err "Quadlet file for '$name' not found in $Q_CONFIG_DIR"
    fi
}

# ------------------------------------------------------------------------------
# execute_edit
# Usage: quadctl edit intent <name>
# ------------------------------------------------------------------------------
execute_edit() {
    local mode="$1"
    local name="$2"

    # Strict Gatekeeping
    if [[ "$mode" != "intent" ]]; then
        log_err "Invalid syntax."
        log_info "Usage: quadctl edit intent <name>"
        log_warn "Direct editing of runtime artifacts is forbidden."
        return 1
    fi

    echo ":: [Source Edit] locating source file for '$name'..."

    # Search the Source of Truth ($Q_SRC_DIR)
    # We use 'find' to handle subdirectories (container/, volume/, etc.)
    # We look for *name* to be forgiving about extensions.
    
    local found
    found=$(find "$Q_SRC_DIR" -type f -name "*${name}*" -print -quit)

    if [[ -z "$found" ]]; then
        log_err "File matching '$name' not found in Source of Truth ($Q_SRC_DIR)."
        return 1
    fi

    # Detect Editor
    local editor="${EDITOR:-nano}"
    
    echo "   Target: $found"
    echo "   Editor: $editor"
    echo ""
    
    # Execute
    "$editor" "$found"

    # Post-Action Reminder
    echo ""
    log_success "Edit session closed."
    log_warn "Remember to run 'quadctl deploy' to apply changes."
}