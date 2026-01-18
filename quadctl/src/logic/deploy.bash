#!/usr/bin/env bash
# ==============================================================================
# FILE: deploy.bash
# PATH: src/logic/deploy.bash
# PROJECT: quadctl
# VERSION: 10.0.0
# DATE: 2026-01-16
# AUTHOR: SAC-CP (v2.1)
# DESCRIPTION: Deployment engine (Rsync + Validation).
# ==============================================================================

source "${INSTALL_ROOT}/src/api/systemd.bash"

# ------------------------------------------------------------------------------
# execute_deploy
# $1: "force" (optional) to apply changes. Default is dry-run.
# ------------------------------------------------------------------------------
execute_deploy() {
    local mode="${1:-dry-run}"
    local rsync_opts="-aic" # Archive, Itemize changes, Checksum
    
    log_info "Source: $Q_SRC_DIR"
    log_info "Target: $Q_CONFIG_DIR"

    # Pre-flight Check
    if [[ ! -d "$Q_SRC_DIR" ]]; then
        log_err "Source directory not found: $Q_SRC_DIR"
        log_err "Set QUADCTL_SRC environment variable or fix path."
        return 1
    fi

    # Dry Run Logic
    if [[ "$mode" != "force" ]]; then
        rsync_opts="${rsync_opts} --dry-run"
        log_warn "DRY-RUN MODE. No changes will be made."
        echo "Use 'deploy force' to apply."
    else
        log_warn "LIVE MODE. Applying changes..."
    fi

    echo "------------------------------------------------------------------------"
    
    # Sync Quadlet Types
    for type in container volume network image pod; do
        if [[ -d "$Q_SRC_DIR/$type" ]]; then
            # We explicitly include specific types and exclude everything else to be safe
            rsync $rsync_opts \
                --include="*.$type" \
                --exclude="*" \
                "$Q_SRC_DIR/$type/" "$Q_CONFIG_DIR/"
        fi
    done
    
    # Sync Standard User Units (if they exist)
    if [[ -d "$Q_SRC_DIR/user-units" ]]; then
        mkdir -p "$Q_USER_UNIT_DIR"
        rsync $rsync_opts "$Q_SRC_DIR/user-units/" "$Q_USER_UNIT_DIR/"
    fi
    
    echo "------------------------------------------------------------------------"

    # Post-Deploy Actions (Only if forcing)
    if [[ "$mode" == "force" ]]; then
        log_info "Verifying Quadlet Syntax..."
        if ! api_systemd_verify_generator; then
            log_err "Generator validation failed. Check output above."
            # We do NOT exit here, we warn, because sometimes generator warnings are benign
            # but user needs to know.
        else
            log_success "Syntax Verified."
        fi

        log_info "Reloading Systemd Daemon..."
        api_systemd_reload
        log_success "Deployment Complete."
    fi
}