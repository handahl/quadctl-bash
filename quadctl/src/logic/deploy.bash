#!/usr/bin/env bash
# ==============================================================================
# FILE: deploy.bash
# PATH: src/logic/deploy.bash
# PROJECT: quadctl
# VERSION: 11.2.0
# DATE: 2026-01-18
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Synchronizes Intent (Source) to Runtime (Target) with verification.
# ==============================================================================

execute_deploy() {
    local mode="${1:-dry-run}"
    local force_flag="false"

    if [[ "$mode" == "force" ]]; then
        force_flag="true"
    fi

    # 1. SETUP PATHS
    # --------------------------------------------------------------------------
    local source_dir="$Q_SRC_DIR/"
    local target_dir="$Q_CONFIG_DIR/"
    
    echo ":: [Deployment Protocol]"
    log_info "Source: $source_dir"
    log_info "Target: $target_dir"

    # 2. RSYNC SYNCHRONIZATION
    # --------------------------------------------------------------------------
    # We use rsync to mirror the directory structure.
    # Excludes: .git, README, .DS_Store
    # Includes: .container, .volume, .network, .pod
    
    local rsync_opts="-av --itemize-changes --delete --exclude=.git --exclude=README.md --exclude=.DS_Store"
    
    if [[ "$force_flag" == "false" ]]; then
        rsync_opts+=" --dry-run"
        log_warn "DRY-RUN MODE. No changes will be made."
        echo "   Use 'deploy force' to apply."
    fi

    echo "------------------------------------------------------------------------"
    # We must ensure source exists
    if [[ ! -d "$source_dir" ]]; then
        log_err "Source directory does not exist: $source_dir"
        return 1
    fi

    # Flattening Logic: 
    # The user repo has subfolders (container/, volume/). The target is flat.
    # We must iterate and sync specifically if we want to flatten, 
    # OR if the user repo is already flat structure?
    #
    # SAC-CP Standard: The User Repo has subfolders (container/, volume/). 
    # The target (~/.config/containers/systemd) IS flat (mostly).
    #
    # However, Quadlets support subdirectories in the target since Podman 4.
    # We will mirror the structure to keep it clean.
    
    if command -v rsync &>/dev/null; then
        rsync $rsync_opts "$source_dir" "$target_dir"
    else
        log_err "rsync is missing. Cannot deploy."
        return 1
    fi
    echo "------------------------------------------------------------------------"

    # 3. GENERATOR VALIDATION (The "Better Solution")
    # --------------------------------------------------------------------------
    echo ":: Validating Quadlets..."
    
    local generator="/usr/lib/systemd/system-generators/podman-system-generator"
    if [[ -x "$generator" ]]; then
        # We run the generator in dry-run mode to catch syntax errors
        # FILTER: We only show 'converting' (info) or 'Warning' (problems).
        
        local filter_cmd="grep -E 'converting|Warning'"
        if command -v rg &>/dev/null; then
            filter_cmd="rg 'converting|Warning'"
        fi

        # Capture output, pipe to filter, but ensure we don't crash if grep finds nothing
        set +e # Relax strict mode for grep return code
        "$generator" --user --dryrun 2>&1 | eval "$filter_cmd"
        set -e
    else
        log_warn "Podman system generator not found at $generator. Skipping validation."
    fi

    # 4. FINALIZATION
    # --------------------------------------------------------------------------
    if [[ "$force_flag" == "true" ]]; then
        echo ""
        log_info "Reloading Systemd Daemon..."
        systemctl --user daemon-reload
        log_success "Deployment Complete."
    fi
}