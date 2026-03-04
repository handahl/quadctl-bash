#!/usr/bin/env bash
# ==============================================================================
## FILE: quadctl/src/core/utils.bash |   VERSION: 11.1.0   |   DATE: 2026-03-04
# ==============================================================================

# Portable search: rg (if available) vs grep -E
search_pattern() {
    local pattern="$1"
    local input="${2:-$(cat)}"
    if command -v rg &>/dev/null; then
        echo "$input" | rg -iq "$pattern" # -i for case insensitive, -q for exit code
    else
        echo "$input" | grep -Eiq "$pattern"
    fi
}

# Systemd Specifier Expander
expand_specifiers() {
    local input="$1"
    # %h -> Home, %u -> User, %t -> Runtime Dir
    input="${input//%h/$HOME}"
    input="${input//%u/$USER}"
    input="${input//%t/$XDG_RUNTIME_DIR}"
    # Also handle the standard shell tilde
    input="${input/#\~/$HOME}"
    echo "$input"
}

# ------------------------------------------------------------------------------
# discover_quadlet_generator
# Locates the Quadlet generator binary across known distribution layouts.
# Prints the path to stdout. Returns 1 if not found.
#
# Discovery order (per ai.restraints.md):
#   1. /usr/lib/systemd/user-generators/podman-user-generator  (Fedora 5.x+)
#   2. /usr/lib/systemd/system-generators/podman-system-generator (Fedora/Rocky)
#   3. /usr/libexec/podman/quadlet                              (alternative layout)
# ------------------------------------------------------------------------------
discover_quadlet_generator() {
    local candidates=(
        "/usr/lib/systemd/user-generators/podman-user-generator"
        "/usr/lib/systemd/system-generators/podman-system-generator"
        "/usr/libexec/podman/quadlet"
    )
    for path in "${candidates[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

check_git_status() {
    # Check if we are in a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi

    # Check for uncommitted changes in the source directory
    if [[ -n "$(git status --short "$Q_SRC_DIR")" ]]; then
        log_warn "You have uncommitted changes in your intent directory."
        echo "   Recommendation: git commit before deploying to keep a clean history."
    fi
}

auto_git_commit() {
    local mode="$1"
    
    # Only proceed if it's a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi

    # Check for changes
    if [[ -z "$(git status --short "$Q_SRC_DIR")" ]]; then
        return 0 # No changes to commit
    fi

    log_info "Autocommitting intent changes..."
    git add "$Q_SRC_DIR"
    
    local msg="quadctl deploy ($mode): $(date '+%Y-%m-%d %H:%M:%S')"
    if git commit -m "$msg"; then
        log_success "Changes committed to history."
    else
        log_warn "Git commit failed (check your git config)."
    fi
}