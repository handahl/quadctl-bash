#!/usr/bin/env bash
# ==============================================================================
# FILE: deploy.bash
# PATH: src/logic/deploy.bash
# PROJECT: quadctl
# VERSION: 11.4.0
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Synchronizes Intent (Source) to Runtime (Target) with verification.
# ==============================================================================

execute_deploy() {
    local mode="${1:-dry-run}"
    local force_flag="false"

    if [[ "$mode" == "now" || "$mode" == "force" ]]; then
        force_flag="true"
    fi

    local source_dir="$Q_SRC_DIR/"
    local target_dir="$Q_CONFIG_DIR/"
    
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
        # Check for ripgrep (rg), fallback to grep
        local filter_tool="grep"
        if command -v rg &>/dev/null; then
            filter_tool="rg"
        fi

        # Filter: Only show "Warning" or "converting" errors
        # Note: We capture stderr (2>&1) because that's where generator logs.
        
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